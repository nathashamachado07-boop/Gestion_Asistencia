const crypto = require('crypto');
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();
const PASSWORD_ITERATIONS = 60000;
const PASSWORD_KEY_LENGTH = 32;
const PASSWORD_DIGEST = 'sha256';
const RECOVERY_CODE_EXPIRATION_MINUTES = 10;
const RECOVERY_MIN_INTERVAL_SECONDS = 60;
const RECOVERY_MAX_ATTEMPTS = 5;

function setCorsHeaders(res) {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');
}

function handleCors(req, res) {
  setCorsHeaders(res);

  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return true;
  }

  return false;
}

function getRequestBody(req) {
  if (req.body && typeof req.body === 'object') {
    return req.body;
  }

  if (typeof req.body === 'string' && req.body.trim()) {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return {};
    }
  }

  return {};
}

function normalizeEmail(value) {
  return (value || '').toString().trim().toLowerCase();
}

function createPasswordPayload(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(
    password,
    salt,
    PASSWORD_ITERATIONS,
    PASSWORD_KEY_LENGTH,
    PASSWORD_DIGEST
  );

  return {
    passwordHash: hash.toString('base64'),
    passwordSalt: salt.toString('base64'),
    passwordAlgorithm: 'pbkdf2-sha256',
    passwordVersion: 1,
    passwordIterations: PASSWORD_ITERATIONS,
  };
}

function verifySecret({
  secret,
  expectedHash,
  salt,
  iterations = PASSWORD_ITERATIONS,
}) {
  if (!secret || !expectedHash || !salt) {
    return false;
  }

  try {
    const saltBuffer = Buffer.from(salt, 'base64');
    const hash = crypto.pbkdf2Sync(
      secret,
      saltBuffer,
      Number(iterations) || PASSWORD_ITERATIONS,
      PASSWORD_KEY_LENGTH,
      PASSWORD_DIGEST
    ).toString('base64');

    const left = Buffer.from(hash, 'utf8');
    const right = Buffer.from(expectedHash, 'utf8');

    if (left.length !== right.length) {
      return false;
    }

    return crypto.timingSafeEqual(left, right);
  } catch (_) {
    return false;
  }
}

function validatePasswordStrength(password) {
  const value = (password || '').toString().trim();

  if (value.length < 8) {
    return 'La contrasena debe tener al menos 8 caracteres.';
  }

  if (!/[A-Z]/.test(value)) {
    return 'La contrasena debe incluir al menos una letra mayuscula.';
  }

  if (!/[a-z]/.test(value)) {
    return 'La contrasena debe incluir al menos una letra minuscula.';
  }

  if (!/\d/.test(value)) {
    return 'La contrasena debe incluir al menos un numero.';
  }

  return '';
}

function generateRecoveryCode() {
  return crypto.randomInt(0, 1000000).toString().padStart(6, '0');
}

async function findUserByEmail(correo) {
  const snapshot = await db
    .collection('usuarios')
    .where('correo', '==', correo)
    .limit(1)
    .get();

  if (snapshot.empty) {
    return null;
  }

  const doc = snapshot.docs[0];
  return {
    doc,
    data: doc.data() || {},
  };
}

function getTrustedTokens(data) {
  return Array.isArray(data.fcmTokens)
    ? data.fcmTokens
        .map((token) => (token || '').toString().trim())
        .filter(Boolean)
    : [];
}

function verifyUserPassword(data, password) {
  const passwordHash = (data.passwordHash || '').toString();
  const passwordSalt = (data.passwordSalt || '').toString();

  if (passwordHash && passwordSalt) {
    return verifySecret({
      secret: password,
      expectedHash: passwordHash,
      salt: passwordSalt,
      iterations: data.passwordIterations,
    });
  }

  const legacyPassword = (data.password || '').toString();
  return legacyPassword !== '' && legacyPassword === password;
}

async function sendRecoveryCodeToTokens(tokens, code) {
  if (!tokens.length) {
    return 0;
  }

  const invalidTokens = [];
  let successCount = 0;

  for (const batchTokens of chunk(tokens, 500)) {
    const response = await messaging.sendEachForMulticast({
      tokens: batchTokens,
      notification: {
        title: 'Codigo de recuperacion INTESUD',
        body: `Tu codigo temporal es ${code}. Caduca en ${RECOVERY_CODE_EXPIRATION_MINUTES} minutos.`,
      },
      data: {
        tipo: 'password_recovery',
        code,
        expiresInMinutes: RECOVERY_CODE_EXPIRATION_MINUTES.toString(),
      },
      android: {
        priority: 'high',
        notification: {
          channelId: 'intesud_high_importance',
          sound: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    });

    successCount += response.successCount;

    response.responses.forEach((result, index) => {
      if (result.success) {
        return;
      }

      const code = result.error?.code || '';
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
      ) {
        invalidTokens.push(batchTokens[index]);
      }
    });
  }

  await cleanupInvalidTokens(invalidTokens);
  return successCount;
}

function chunk(items, size) {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

function uniqueTokens(users) {
  const tokens = new Set();

  for (const user of users) {
    const rawTokens = Array.isArray(user.fcmTokens) ? user.fcmTokens : [];
    for (const token of rawTokens) {
      if (typeof token === 'string' && token.trim()) {
        tokens.add(token.trim());
      }
    }
  }

  return [...tokens];
}

async function collectRecipients(aviso) {
  const destinatarioCorreo =
    (aviso.destinatarioCorreo || '').toString().trim().toLowerCase();
  const sedeId = (aviso.sedeId || '').toString().trim();

  if (destinatarioCorreo) {
    const snapshot = await db
      .collection('usuarios')
      .where('correo', '==', destinatarioCorreo)
      .get();

    return snapshot.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
  }

  if (!sedeId) {
    return [];
  }

  const snapshot = await db
    .collection('usuarios')
    .where('sedeId', '==', sedeId)
    .get();

  return snapshot.docs
    .map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }))
    .filter((user) => {
      const rol = (user.rol || '').toString().trim().toLowerCase();
      return rol === 'docente' || rol === 'administrativo';
    });
}

async function cleanupInvalidTokens(invalidTokens) {
  if (!invalidTokens.length) {
    return;
  }

  const snapshot = await db.collection('usuarios').get();
  const batch = db.batch();

  snapshot.docs.forEach((doc) => {
    const data = doc.data();
    const tokens = Array.isArray(data.fcmTokens) ? data.fcmTokens : [];
    const filtered = tokens.filter((token) => !invalidTokens.includes(token));

    if (filtered.length !== tokens.length) {
      batch.update(doc.ref, {
        fcmTokens: filtered,
        tokenActualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  });

  await batch.commit();
}

exports.sendPushForAviso = functions.firestore
  .document('avisos/{avisoId}')
  .onCreate(async (snapshot, context) => {
    const aviso = snapshot.data() || {};
    const recipients = await collectRecipients(aviso);
    const tokens = uniqueTokens(recipients);

    if (!tokens.length) {
      await snapshot.ref.set(
        {
          pushStatus: 'sin_tokens',
          pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
          pushCount: 0,
        },
        { merge: true }
      );
      return null;
    }

    const title = (aviso.titulo || 'INTESUD').toString();
    const body = (aviso.mensaje || 'Tienes una notificacion nueva.').toString();
    const tipo = (aviso.tipo || 'aviso').toString();
    const invalidTokens = [];
    let successCount = 0;

    for (const batchTokens of chunk(tokens, 500)) {
      const response = await messaging.sendEachForMulticast({
        tokens: batchTokens,
        notification: {
          title,
          body,
        },
        data: {
          title,
          body,
          tipo,
          avisoId: context.params.avisoId,
          solicitudId: (aviso.solicitudId || '').toString(),
          sedeId: (aviso.sedeId || '').toString(),
        },
        android: {
          priority: 'high',
          notification: {
            channelId: 'intesud_high_importance',
            sound: 'default',
          },
        },
        apns: {
          payload: {
            aps: {
              sound: 'default',
            },
          },
        },
      });

      successCount += response.successCount;

      response.responses.forEach((result, index) => {
        if (result.success) {
          return;
        }

        const code = result.error?.code || '';
        if (
          code === 'messaging/registration-token-not-registered' ||
          code === 'messaging/invalid-registration-token'
        ) {
          invalidTokens.push(batchTokens[index]);
        }
      });
    }

    await cleanupInvalidTokens(invalidTokens);

    await snapshot.ref.set(
      {
        pushStatus: 'enviado',
        pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
        pushCount: successCount,
      },
      { merge: true }
    );

    return null;
  });

exports.requestPasswordRecovery = functions.https.onRequest(
  async (req, res) => {
    if (handleCors(req, res)) {
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ message: 'Metodo no permitido.' });
      return;
    }

    try {
      const body = getRequestBody(req);
      const correo = normalizeEmail(body.correo);

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      const user = await findUserByEmail(correo);
      if (!user) {
        res.status(200).json({
          delivery: 'support',
          message:
            'Si la cuenta dispone de un dispositivo confiable vinculado, recibiras un codigo temporal. Si no lo recibes, contacta a RRHH o al administrador.',
        });
        return;
      }

      const recoveryData = user.data.passwordRecovery || {};
      const lastRequestedAt = recoveryData.requestedAt?.toDate?.();
      if (lastRequestedAt instanceof Date) {
        const elapsedSeconds = Math.floor(
          (Date.now() - lastRequestedAt.getTime()) / 1000
        );

        if (elapsedSeconds < RECOVERY_MIN_INTERVAL_SECONDS) {
          const waitSeconds = RECOVERY_MIN_INTERVAL_SECONDS - elapsedSeconds;
          res.status(429).json({
            delivery: 'device',
            message: `Espera ${waitSeconds} segundos antes de solicitar un nuevo codigo.`,
          });
          return;
        }
      }

      const trustedTokens = getTrustedTokens(user.data);
      if (!trustedTokens.length) {
        await user.doc.ref.set(
          {
            passwordRecovery: {
              status: 'requires_support',
              delivery: 'support',
              requestedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        res.status(200).json({
          delivery: 'support',
          message:
            'No encontramos un dispositivo confiable activo para esta cuenta. Solicita el restablecimiento a RRHH o al administrador.',
        });
        return;
      }

      const code = generateRecoveryCode();
      const codePayload = createPasswordPayload(code);
      const expiresAt = admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + RECOVERY_CODE_EXPIRATION_MINUTES * 60 * 1000)
      );

      await user.doc.ref.set(
        {
          passwordRecovery: {
            codeHash: codePayload.passwordHash,
            codeSalt: codePayload.passwordSalt,
            codeAlgorithm: codePayload.passwordAlgorithm,
            codeVersion: codePayload.passwordVersion,
            codeIterations: codePayload.passwordIterations,
            requestedAt: admin.firestore.FieldValue.serverTimestamp(),
            expiresAt,
            attempts: 0,
            maxAttempts: RECOVERY_MAX_ATTEMPTS,
            status: 'pending',
            delivery: 'device',
          },
          actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const deliveredCount = await sendRecoveryCodeToTokens(trustedTokens, code);
      if (deliveredCount <= 0) {
        await user.doc.ref.set(
          {
            passwordRecovery: {
              status: 'requires_support',
              delivery: 'support',
              requestedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        res.status(200).json({
          delivery: 'support',
          message:
            'No pudimos entregar el codigo a un dispositivo activo. Solicita el restablecimiento a RRHH o al administrador.',
        });
        return;
      }

      res.status(200).json({
        delivery: 'device',
        message:
          'Te enviamos un codigo temporal a tu dispositivo movil vinculado. Caduca en 10 minutos.',
      });
    } catch (error) {
      console.error('Password recovery request failed:', error);
      res.status(500).json({
        message:
          'No se pudo iniciar la recuperacion segura en este momento. Intenta nuevamente.',
      });
    }
  }
);

exports.confirmPasswordRecovery = functions.https.onRequest(
  async (req, res) => {
    if (handleCors(req, res)) {
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ message: 'Metodo no permitido.' });
      return;
    }

    try {
      const body = getRequestBody(req);
      const correo = normalizeEmail(body.correo);
      const codigo = (body.codigo || '').toString().trim();
      const nuevaPassword = (body.nuevaPassword || '').toString().trim();

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      if (codigo.length !== 6) {
        res.status(400).json({
          message: 'Ingrese el codigo temporal de 6 digitos.',
        });
        return;
      }

      const passwordValidation = validatePasswordStrength(nuevaPassword);
      if (passwordValidation) {
        res.status(400).json({ message: passwordValidation });
        return;
      }

      const user = await findUserByEmail(correo);
      if (!user) {
        res.status(400).json({
          message: 'No se pudo validar la recuperacion solicitada.',
        });
        return;
      }

      const recoveryData = user.data.passwordRecovery || {};
      const expiresAt = recoveryData.expiresAt?.toDate?.();
      const attempts = Number(recoveryData.attempts || 0);
      const maxAttempts = Number(
        recoveryData.maxAttempts || RECOVERY_MAX_ATTEMPTS
      );

      if (
        !recoveryData.codeHash ||
        !recoveryData.codeSalt ||
        !(expiresAt instanceof Date)
      ) {
        res.status(400).json({
          message: 'Solicita un nuevo codigo temporal antes de continuar.',
        });
        return;
      }

      if (Date.now() > expiresAt.getTime()) {
        await user.doc.ref.set(
          {
            passwordRecovery: admin.firestore.FieldValue.delete(),
          },
          { merge: true }
        );

        res.status(400).json({
          message: 'El codigo temporal ya expiro. Solicita uno nuevo.',
        });
        return;
      }

      if (attempts >= maxAttempts) {
        res.status(400).json({
          message:
            'Se agotaron los intentos permitidos. Solicita un nuevo codigo temporal.',
        });
        return;
      }

      const codeIsValid = verifySecret({
        secret: codigo,
        expectedHash: recoveryData.codeHash,
        salt: recoveryData.codeSalt,
        iterations: recoveryData.codeIterations,
      });

      if (!codeIsValid) {
        const nextAttempts = attempts + 1;
        await user.doc.ref.set(
          {
            passwordRecovery: {
              ...recoveryData,
              attempts: nextAttempts,
              lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
          },
          { merge: true }
        );

        res.status(400).json({
          message:
            nextAttempts >= maxAttempts
              ? 'Se agotaron los intentos permitidos. Solicita un nuevo codigo temporal.'
              : 'El codigo temporal ingresado no es correcto.',
        });
        return;
      }

      const passwordPayload = createPasswordPayload(nuevaPassword);
      await user.doc.ref.set(
        {
          ...passwordPayload,
          password: admin.firestore.FieldValue.delete(),
          passwordRecovery: admin.firestore.FieldValue.delete(),
          passwordChangedAt: admin.firestore.FieldValue.serverTimestamp(),
          actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      res.status(200).json({
        message: 'Contrasena actualizada correctamente.',
      });
    } catch (error) {
      console.error('Password recovery confirmation failed:', error);
      res.status(500).json({
        message:
          'No se pudo completar la recuperacion de contrasena en este momento.',
      });
    }
  }
);

exports.changePasswordWithCurrentPassword = functions.https.onRequest(
  async (req, res) => {
    if (handleCors(req, res)) {
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).json({ message: 'Metodo no permitido.' });
      return;
    }

    try {
      const body = getRequestBody(req);
      const correo = normalizeEmail(body.correo);
      const passwordActual = (body.passwordActual || '').toString().trim();
      const nuevaPassword = (body.nuevaPassword || '').toString().trim();

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      if (!passwordActual) {
        res.status(400).json({
          message: 'Ingrese la contrasena actual.',
        });
        return;
      }

      const passwordValidation = validatePasswordStrength(nuevaPassword);
      if (passwordValidation) {
        res.status(400).json({ message: passwordValidation });
        return;
      }

      if (passwordActual === nuevaPassword) {
        res.status(400).json({
          message:
            'La nueva contrasena debe ser diferente de la contrasena actual.',
        });
        return;
      }

      const user = await findUserByEmail(correo);
      if (!user || !verifyUserPassword(user.data, passwordActual)) {
        res.status(400).json({
          message: 'La contrasena actual no es correcta.',
        });
        return;
      }

      const passwordPayload = createPasswordPayload(nuevaPassword);
      await user.doc.ref.set(
        {
          ...passwordPayload,
          password: admin.firestore.FieldValue.delete(),
          passwordRecovery: admin.firestore.FieldValue.delete(),
          passwordChangedAt: admin.firestore.FieldValue.serverTimestamp(),
          actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      res.status(200).json({
        message: 'Contrasena actualizada correctamente.',
      });
    } catch (error) {
      console.error('Change password with current password failed:', error);
      res.status(500).json({
        message:
          'No se pudo actualizar la contrasena en este momento. Intenta nuevamente.',
      });
    }
  }
);
