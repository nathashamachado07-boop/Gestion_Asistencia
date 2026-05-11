const crypto = require('crypto');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const ITERATIONS = 60000;
const KEY_LENGTH = 32;
const DIGEST = 'sha256';
const MAX_BATCH_SIZE = 400;

function createPasswordPayload(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.pbkdf2Sync(
    password,
    salt,
    ITERATIONS,
    KEY_LENGTH,
    DIGEST,
  );

  return {
    passwordHash: hash.toString('base64'),
    passwordSalt: salt.toString('base64'),
    passwordAlgorithm: 'pbkdf2-sha256',
    passwordVersion: 1,
    passwordIterations: ITERATIONS,
  };
}

async function main() {
  const snapshot = await db.collection('usuarios').get();

  let migrated = 0;
  let skipped = 0;
  let batch = db.batch();
  let batchSize = 0;

  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    const plainPassword =
      typeof data.password === 'string' ? data.password.trim() : '';
    const alreadyHasHash =
      typeof data.passwordHash === 'string' && data.passwordHash.trim() !== '';

    if (!plainPassword || alreadyHasHash) {
      skipped += 1;
      continue;
    }

    batch.update(doc.ref, {
      ...createPasswordPayload(plainPassword),
      password: admin.firestore.FieldValue.delete(),
      actualizadoEn: admin.firestore.FieldValue.serverTimestamp(),
    });
    migrated += 1;
    batchSize += 1;

    if (batchSize >= MAX_BATCH_SIZE) {
      await batch.commit();
      batch = db.batch();
      batchSize = 0;
    }
  }

  if (batchSize > 0) {
    await batch.commit();
  }

  console.log(
    JSON.stringify({
      migrated,
      skipped,
      total: snapshot.size,
    }),
  );
}

main().catch((error) => {
  console.error('Password migration failed:', error);
  process.exitCode = 1;
});
