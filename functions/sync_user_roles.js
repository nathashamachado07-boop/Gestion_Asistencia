const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

const matrizId = 'matriz';
const sedeNorteId = 'princesa_gales_norte';
const sedeCentroId = 'princesa_gales_centro';
const sedeCreSerId = 'instituto_cre_ser';

const allSedeIds = [
  matrizId,
  sedeNorteId,
  sedeCentroId,
  sedeCreSerId,
];

const primaryReviewerEmail = 'nathashamachado07@gmail.com';
const finalReviewerEmails = new Set([
  'oscar@sudamericano.edu.ec',
  'yadira@sudamericano.edu.ec',
]);

function normalize(value) {
  return (value || '').toString().trim().toLowerCase();
}

function resolveSedeId(data) {
  const sedeId = normalize(data.sedeId);
  if (sedeId) {
    return sedeId;
  }
  const sede = normalize(data.sede);
  if (sede.includes('norte')) return sedeNorteId;
  if (sede.includes('centro')) return sedeCentroId;
  if (sede.includes('cre ser')) return sedeCreSerId;
  return matrizId;
}

async function main() {
  const snapshot = await db.collection('usuarios').get();
  const batch = db.batch();

  let total = 0;
  let changed = 0;

  for (const doc of snapshot.docs) {
    total += 1;
    const data = doc.data() || {};
    const correo = normalize(data.correo);
    const rolActual = normalize(data.rol);
    const sedeId = resolveSedeId(data);
    const update = {};

    if (correo === primaryReviewerEmail) {
      if (data.rol !== 'Admin') {
        update.rol = 'Admin';
      }
      update.allowedSedeIds = allSedeIds;
      update.matrizFlowRole = 'primary';
    } else if (finalReviewerEmails.has(correo)) {
      if (data.rol !== 'RRHH') {
        update.rol = 'RRHH';
      }
      update.allowedSedeIds = [matrizId];
      update.matrizFlowRole = 'final';
    } else if (rolActual === 'administrativo' || rolActual === 'personal administrativo') {
      if (data.rol !== 'Personal administrativo') {
        update.rol = 'Personal administrativo';
      }
    } else if (rolActual === 'rrhh') {
      update.allowedSedeIds = [sedeId];
    }

    if (Object.keys(update).length > 0) {
      batch.set(doc.ref, update, { merge: true });
      changed += 1;
      console.log(`Actualizar ${doc.id}:`, update);
    }
  }

  if (changed === 0) {
    console.log(`Sin cambios. Revisados ${total} usuarios.`);
    return;
  }

  await batch.commit();
  console.log(`Listo. Revisados ${total} usuarios, actualizados ${changed}.`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error al sincronizar roles:', error);
    process.exit(1);
  });
