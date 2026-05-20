const crypto = require('crypto');
const functions = require('firebase-functions');
const admin = require('firebase-admin');
const forge = require('node-forge');
const { PDFDocument } = require('pdf-lib');
const { SignPdf } = require('@signpdf/signpdf');
const { P12Signer } = require('@signpdf/signer-p12');
const { pdflibAddPlaceholder } = require('@signpdf/placeholder-pdf-lib');
const { SUBFILTER_ETSI_CADES_DETACHED } = require('@signpdf/utils');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();
const PASSWORD_ITERATIONS = 60000;
const PASSWORD_KEY_LENGTH = 32;
const PASSWORD_DIGEST = 'sha256';
const RECOVERY_CODE_EXPIRATION_MINUTES = 10;
const RECOVERY_MIN_INTERVAL_SECONDS = 60;
const RECOVERY_MAX_ATTEMPTS = 5;
const DIGITAL_CERTIFICATE_MAX_BYTES = 512 * 1024;
const DIGITAL_CERTIFICATE_ITERATIONS = 120000;
const DIGITAL_CERTIFICATE_KEY_LENGTH = 32;
const DIGITAL_CERTIFICATE_IV_LENGTH = 12;
const DIGITAL_CERTIFICATE_ALGORITHM = 'aes-256-gcm';

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

async function findUserByIdentity({ userDocId, correo }) {
  const docId = (userDocId || '').toString().trim();
  if (docId) {
    const snapshot = await db.collection('usuarios').doc(docId).get();
    if (snapshot.exists) {
      return {
        doc: snapshot,
        data: snapshot.data() || {},
      };
    }
  }

  return findUserByEmail(correo);
}

function normalizeCertificateFileName(fileName) {
  const value = (fileName || '').toString().trim();
  return value || 'certificado.p12';
}

function decodeBase64Binary(value) {
  try {
    return Buffer.from((value || '').toString(), 'base64');
  } catch (_) {
    return Buffer.alloc(0);
  }
}

function formatCertificateDn(attributes = []) {
  return attributes
    .map((attribute) => {
      const key = attribute.shortName || attribute.name || 'attr';
      return `${key}=${attribute.value}`;
    })
    .join(', ');
}

function parsePkcs12Bundle(certificateBuffer, passphrase) {
  const binary = certificateBuffer.toString('binary');
  const asn1 = forge.asn1.fromDer(binary);
  return forge.pkcs12.pkcs12FromAsn1(asn1, false, passphrase);
}

function extractPkcs12Metadata(certificateBuffer, passphrase) {
  const p12 = parsePkcs12Bundle(certificateBuffer, passphrase);
  const bags = p12.getBags({ bagType: forge.pki.oids.certBag });
  const certBagKey = forge.pki.oids.certBag;
  const certEntry = Array.isArray(bags[certBagKey])
    ? bags[certBagKey].find((item) => item && item.cert)
    : null;

  if (!certEntry || !certEntry.cert) {
    throw new Error(
      'El archivo .p12 no contiene un certificado utilizable para firmar.'
    );
  }

  const cert = certEntry.cert;
  const certDer = forge.asn1.toDer(forge.pki.certificateToAsn1(cert)).getBytes();
  const fingerprintSha256 = crypto
    .createHash('sha256')
    .update(Buffer.from(certDer, 'binary'))
    .digest('hex');

  return {
    subject: formatCertificateDn(cert.subject.attributes || []),
    issuer: formatCertificateDn(cert.issuer.attributes || []),
    serialNumber: (cert.serialNumber || '').toString(),
    validFrom: cert.validity?.notBefore || null,
    validTo: cert.validity?.notAfter || null,
    fingerprintSha256,
  };
}

function encryptBinaryPayload(buffer, secret) {
  const salt = crypto.randomBytes(16);
  const iv = crypto.randomBytes(DIGITAL_CERTIFICATE_IV_LENGTH);
  const key = crypto.pbkdf2Sync(
    secret,
    salt,
    DIGITAL_CERTIFICATE_ITERATIONS,
    DIGITAL_CERTIFICATE_KEY_LENGTH,
    PASSWORD_DIGEST
  );
  const cipher = crypto.createCipheriv(DIGITAL_CERTIFICATE_ALGORITHM, key, iv);
  const encrypted = Buffer.concat([cipher.update(buffer), cipher.final()]);
  const authTag = cipher.getAuthTag();

  return {
    encryptedBase64: encrypted.toString('base64'),
    encryptionSalt: salt.toString('base64'),
    encryptionIv: iv.toString('base64'),
    encryptionAuthTag: authTag.toString('base64'),
    encryptionAlgorithm: DIGITAL_CERTIFICATE_ALGORITHM,
    encryptionKeyAlgorithm: 'pbkdf2-sha256',
    encryptionIterations: DIGITAL_CERTIFICATE_ITERATIONS,
  };
}

function decryptBinaryPayload(record, secret) {
  const salt = Buffer.from((record.encryptionSalt || '').toString(), 'base64');
  const iv = Buffer.from((record.encryptionIv || '').toString(), 'base64');
  const authTag = Buffer.from(
    (record.encryptionAuthTag || '').toString(),
    'base64'
  );
  const encrypted = Buffer.from(
    (record.encryptedBase64 || '').toString(),
    'base64'
  );

  const key = crypto.pbkdf2Sync(
    secret,
    salt,
    Number(record.encryptionIterations) || DIGITAL_CERTIFICATE_ITERATIONS,
    DIGITAL_CERTIFICATE_KEY_LENGTH,
    PASSWORD_DIGEST
  );
  const decipher = crypto.createDecipheriv(
    DIGITAL_CERTIFICATE_ALGORITHM,
    key,
    iv
  );
  decipher.setAuthTag(authTag);
  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

function sanitizeDigitalCertificateRecord(record) {
  if (!record || typeof record !== 'object') {
    return null;
  }

  const sanitized = { ...record };
  [
    'encryptedBase64',
    'encryptionSalt',
    'encryptionIv',
    'encryptionAuthTag',
    'passwordHash',
    'passwordSalt',
    'passwordAlgorithm',
    'passwordVersion',
    'passwordIterations',
    'actualizadoEn',
  ].forEach((key) => delete sanitized[key]);
  return sanitized;
}

function validateStoredDigitalCertificate(record, certificatePassword) {
  const passwordHash = (record?.passwordHash || '').toString();
  const passwordSalt = (record?.passwordSalt || '').toString();

  if (!passwordHash || !passwordSalt) {
    return false;
  }

  return verifySecret({
    secret: certificatePassword,
    expectedHash: passwordHash,
    salt: passwordSalt,
    iterations: record.passwordIterations,
  });
}

async function signPdfBufferWithP12({
  pdfBuffer,
  certificateBuffer,
  certificatePassword,
  signerName,
  reason,
  location,
  contactInfo,
}) {
  const pdfDoc = await PDFDocument.load(pdfBuffer);
  pdflibAddPlaceholder({
    pdfDoc,
    reason: (reason || '').toString().trim() || 'Firma digital del documento.',
    contactInfo:
      (contactInfo || '').toString().trim() || 'soporte@intesud.local',
    name: (signerName || '').toString().trim() || 'Firmante del sistema',
    location: (location || '').toString().trim() || 'Sistema interno',
    subFilter: SUBFILTER_ETSI_CADES_DETACHED,
  });

  const pdfWithPlaceholder = Buffer.from(await pdfDoc.save());
  const signer = new P12Signer(certificateBuffer, {
    passphrase: certificatePassword,
  });
  const signPdf = new SignPdf();
  return signPdf.sign(pdfWithPlaceholder, signer);
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

exports.registerDigitalCertificate = functions.https.onRequest(
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
      const userDocId = (body.userDocId || '').toString().trim();
      const passwordActual = (body.passwordActual || '').toString().trim();
      const certificatePassword = (body.certificatePassword || '')
        .toString()
        .trim();
      const fileName = normalizeCertificateFileName(body.fileName);
      const mimeType = (body.mimeType || 'application/x-pkcs12')
        .toString()
        .trim();
      const certificateBuffer = decodeBase64Binary(body.certificateBase64);

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      if (!passwordActual) {
        res.status(400).json({
          message: 'Ingrese la clave actual de la cuenta.',
        });
        return;
      }

      if (!certificatePassword) {
        res.status(400).json({
          message: 'Ingrese la clave del certificado .p12.',
        });
        return;
      }

      if (!certificateBuffer.length) {
        res.status(400).json({
          message: 'El archivo .p12 enviado no es valido.',
        });
        return;
      }

      if (certificateBuffer.length > DIGITAL_CERTIFICATE_MAX_BYTES) {
        res.status(400).json({
          message: 'El certificado supera el tamano permitido de 512 KB.',
        });
        return;
      }

      const lowerName = fileName.toLowerCase();
      if (!lowerName.endsWith('.p12') && !lowerName.endsWith('.pfx')) {
        res.status(400).json({
          message: 'El certificado debe estar en formato .p12 o .pfx.',
        });
        return;
      }

      const user = await findUserByIdentity({ userDocId, correo });
      if (!user || !verifyUserPassword(user.data, passwordActual)) {
        res.status(400).json({
          message: 'La clave actual de la cuenta no es correcta.',
        });
        return;
      }

      let certificateMetadata;
      try {
        certificateMetadata = extractPkcs12Metadata(
          certificateBuffer,
          certificatePassword
        );
      } catch (error) {
        res.status(400).json({
          message:
            'No se pudo abrir el archivo .p12 con la clave ingresada. Verifica el certificado y su password.',
        });
        return;
      }

      const encryptedPayload = encryptBinaryPayload(
        certificateBuffer,
        certificatePassword
      );
      const passwordPayload = createPasswordPayload(certificatePassword);

      const certificadoDigitalP12 = {
        estado: 'activo',
        provider: 'p12_local',
        fileName,
        mimeType,
        ...encryptedPayload,
        ...passwordPayload,
        subject: certificateMetadata.subject,
        issuer: certificateMetadata.issuer,
        serialNumber: certificateMetadata.serialNumber,
        fingerprintSha256: certificateMetadata.fingerprintSha256,
        validFrom: certificateMetadata.validFrom
          ? admin.firestore.Timestamp.fromDate(certificateMetadata.validFrom)
          : null,
        validTo: certificateMetadata.validTo
          ? admin.firestore.Timestamp.fromDate(certificateMetadata.validTo)
          : null,
        actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
      };

      await user.doc.ref.set(
        {
          certificadoDigitalP12,
          actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      res.status(200).json({
        message: 'Certificado digital .p12 registrado correctamente.',
        certificadoDigitalP12: sanitizeDigitalCertificateRecord(
          certificadoDigitalP12
        ),
      });
    } catch (error) {
      console.error('Register digital certificate failed:', error);
      res.status(500).json({
        message:
          'No se pudo registrar el certificado digital en este momento.',
      });
    }
  }
);

exports.deleteDigitalCertificate = functions.https.onRequest(async (req, res) => {
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
    const userDocId = (body.userDocId || '').toString().trim();
    const passwordActual = (body.passwordActual || '').toString().trim();

    if (!correo) {
      res.status(400).json({ message: 'Ingrese un correo valido.' });
      return;
    }

    if (!passwordActual) {
      res.status(400).json({
        message: 'Ingrese la clave actual de la cuenta.',
      });
      return;
    }

    const user = await findUserByIdentity({ userDocId, correo });
    if (!user || !verifyUserPassword(user.data, passwordActual)) {
      res.status(400).json({
        message: 'La clave actual de la cuenta no es correcta.',
      });
      return;
    }

    await user.doc.ref.set(
      {
        certificadoDigitalP12: admin.firestore.FieldValue.delete(),
        actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    res.status(200).json({
      message: 'Certificado digital eliminado correctamente.',
    });
  } catch (error) {
    console.error('Delete digital certificate failed:', error);
    res.status(500).json({
      message: 'No se pudo eliminar el certificado digital en este momento.',
    });
  }
});

exports.verifyDigitalCertificatePassword = functions.https.onRequest(
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
      const userDocId = (body.userDocId || '').toString().trim();
      const certificatePassword = (body.certificatePassword || '')
        .toString()
        .trim();

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      if (!certificatePassword) {
        res.status(400).json({
          message: 'Ingrese la clave del certificado .p12.',
        });
        return;
      }

      const user = await findUserByIdentity({ userDocId, correo });
      if (!user) {
        res.status(400).json({
          message: 'No se encontro el usuario solicitado.',
        });
        return;
      }

      const certificadoDigitalP12 = user.data.certificadoDigitalP12 || null;
      if (!certificadoDigitalP12) {
        res.status(400).json({
          message: 'No tienes un certificado digital .p12 registrado.',
        });
        return;
      }

      if (
        !validateStoredDigitalCertificate(
          certificadoDigitalP12,
          certificatePassword
        )
      ) {
        res.status(400).json({
          message: 'La clave del certificado .p12 no es correcta.',
        });
        return;
      }

      try {
        const certificateBuffer = decryptBinaryPayload(
          certificadoDigitalP12,
          certificatePassword
        );
        extractPkcs12Metadata(certificateBuffer, certificatePassword);
      } catch (error) {
        console.error('Digital certificate decrypt/parse failed:', error);
        res.status(400).json({
          message:
            'No se pudo validar el certificado .p12 con la clave ingresada.',
        });
        return;
      }

      res.status(200).json({
        message: 'Certificado digital validado correctamente.',
        certificadoDigitalP12: sanitizeDigitalCertificateRecord(
          certificadoDigitalP12
        ),
      });
    } catch (error) {
      console.error('Verify digital certificate password failed:', error);
      res.status(500).json({
        message:
          'No se pudo validar el certificado digital en este momento.',
      });
    }
  }
);

exports.signPdfWithDigitalCertificate = functions.https.onRequest(
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
      const userDocId = (body.userDocId || '').toString().trim();
      const certificatePassword = (body.certificatePassword || '')
        .toString()
        .trim();
      const pdfBuffer = decodeBase64Binary(body.pdfBase64);
      const signerName = (body.signerName || '').toString().trim();
      const reason = (body.reason || '').toString().trim();
      const location = (body.location || '').toString().trim();
      const contactInfo = (body.contactInfo || '').toString().trim();

      if (!correo) {
        res.status(400).json({ message: 'Ingrese un correo valido.' });
        return;
      }

      if (!certificatePassword) {
        res.status(400).json({
          message: 'Ingrese la clave del certificado .p12.',
        });
        return;
      }

      if (!pdfBuffer.length) {
        res.status(400).json({
          message: 'No se recibio un PDF valido para firmar.',
        });
        return;
      }

      const user = await findUserByIdentity({ userDocId, correo });
      if (!user) {
        res.status(400).json({
          message: 'No se encontro el usuario solicitado.',
        });
        return;
      }

      const certificadoDigitalP12 = user.data.certificadoDigitalP12 || null;
      if (!certificadoDigitalP12) {
        res.status(400).json({
          message: 'No tienes un certificado digital .p12 registrado.',
        });
        return;
      }

      if (
        !validateStoredDigitalCertificate(
          certificadoDigitalP12,
          certificatePassword
        )
      ) {
        res.status(400).json({
          message: 'La clave del certificado .p12 no es correcta.',
        });
        return;
      }

      const certificateBuffer = decryptBinaryPayload(
        certificadoDigitalP12,
        certificatePassword
      );

      let signedPdf;
      try {
        signedPdf = await signPdfBufferWithP12({
          pdfBuffer,
          certificateBuffer,
          certificatePassword,
          signerName:
            signerName ||
            (user.data.nombre || user.data.correo || 'Firmante del sistema'),
          reason,
          location,
          contactInfo: contactInfo || correo,
        });
      } catch (error) {
        console.error('PDF signing with digital certificate failed:', error);
        res.status(400).json({
          message:
            'No se pudo firmar el PDF con el certificado .p12 proporcionado.',
        });
        return;
      }

      res.status(200).json({
        message: 'PDF firmado digitalmente correctamente.',
        signedPdfBase64: Buffer.from(signedPdf).toString('base64'),
        certificadoDigitalP12: sanitizeDigitalCertificateRecord(
          certificadoDigitalP12
        ),
      });
    } catch (error) {
      console.error('Sign PDF with digital certificate failed:', error);
      res.status(500).json({
        message: 'No se pudo firmar digitalmente el PDF en este momento.',
      });
    }
  }
);
