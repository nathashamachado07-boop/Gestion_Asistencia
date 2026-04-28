const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

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
