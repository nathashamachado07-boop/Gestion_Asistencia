const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

const KNOWN_SEDES = new Set([
  'matriz',
  'princesa_gales_norte',
  'princesa_gales_centro',
  'instituto_cre_ser',
]);

const SAMPLE_LIMIT = 15;

function normalize(value) {
  return (value || '').toString().trim().toLowerCase();
}

function pushSample(list, value, limit = SAMPLE_LIMIT) {
  if (list.length < limit) {
    list.push(value);
  }
}

function increment(map, key) {
  map.set(key, (map.get(key) || 0) + 1);
}

function isTimestampLike(value) {
  return (
    value instanceof admin.firestore.Timestamp ||
    (value &&
      typeof value.toDate === 'function' &&
      typeof value.seconds === 'number')
  );
}

function isDateLike(value) {
  return value instanceof Date;
}

function parseDateLike(value) {
  if (isTimestampLike(value)) {
    return value.toDate();
  }
  if (isDateLike(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (!trimmed) return null;
    const parsed = new Date(trimmed);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

function describeDateIssue(value) {
  if (value === null || value === undefined) {
    return 'missing';
  }
  if (isTimestampLike(value)) {
    return null;
  }
  if (isDateLike(value)) {
    return null;
  }
  if (typeof value === 'string') {
    return parseDateLike(value) ? 'string_date_legacy' : 'invalid_string_date';
  }
  return `unsupported_${typeof value}`;
}

function describeYmdFieldIssue(value) {
  if (value === null || value === undefined) {
    return 'missing';
  }
  if (typeof value !== 'string') {
    return `unsupported_${typeof value}`;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return 'empty';
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    return 'invalid_format';
  }
  const parsed = new Date(`${trimmed}T00:00:00`);
  return Number.isNaN(parsed.getTime()) ? 'invalid_date' : null;
}

function validSedeId(value) {
  const sedeId = normalize(value);
  return sedeId && KNOWN_SEDES.has(sedeId);
}

function createCollectionReport(name) {
  return {
    collection: name,
    total: 0,
    counters: {},
    samples: {},
  };
}

function bump(report, key, sample) {
  report.counters[key] = (report.counters[key] || 0) + 1;
  if (sample !== undefined) {
    if (!report.samples[key]) {
      report.samples[key] = [];
    }
    pushSample(report.samples[key], sample);
  }
}

function summarizeDuplicates(counterMap, minCount = 2, limit = SAMPLE_LIMIT) {
  const out = [];
  for (const [key, count] of counterMap.entries()) {
    if (count >= minCount) {
      out.push({ key, count });
    }
  }
  out.sort((a, b) => b.count - a.count || a.key.localeCompare(b.key));
  return out.slice(0, limit);
}

function usuarioLegacyFlags(data) {
  const flags = [];
  if (!validSedeId(data.sedeId)) flags.push('missing_or_invalid_sedeId');
  if (!normalize(data.correo)) flags.push('missing_correo');
  if (!normalize(data.nombre)) flags.push('missing_nombre');
  if (!normalize(data.rol)) flags.push('missing_rol');
  if (normalize(data.password)) flags.push('legacy_plain_password');
  if (!normalize(data.passwordHash) || !normalize(data.passwordSalt)) {
    flags.push('missing_password_hash');
  }
  return flags;
}

async function diagnoseUsuarios() {
  const report = createCollectionReport('usuarios');
  const snapshot = await db.collection('usuarios').get();
  const duplicateEmails = new Map();

  for (const doc of snapshot.docs) {
    report.total += 1;
    const data = doc.data() || {};
    const correo = normalize(data.correo);

    if (correo) {
      increment(duplicateEmails, correo);
    }

    const flags = usuarioLegacyFlags(data);
    for (const flag of flags) {
      bump(report, flag, {
        id: doc.id,
        correo: correo || null,
        sedeId: data.sedeId || null,
        rol: data.rol || null,
      });
    }
  }

  report.duplicates = {
    correo: summarizeDuplicates(duplicateEmails),
  };
  return report;
}

async function diagnoseSolicitudes() {
  const report = createCollectionReport('solicitudes');
  const snapshot = await db.collection('solicitudes').get();
  const duplicateFormNumbers = new Map();
  const probableDuplicates = new Map();

  for (const doc of snapshot.docs) {
    report.total += 1;
    const data = doc.data() || {};
    const colaboradorCorreo = normalize(data.colaboradorCorreo);
    const colaborador = normalize(data.colaborador);
    const tipo = normalize(data.tipo);
    const sedeId = normalize(data.sedeId);

    if (!validSedeId(data.sedeId)) {
      bump(report, 'missing_or_invalid_sedeId', {
        id: doc.id,
        colaboradorCorreo: colaboradorCorreo || null,
        colaborador: data.colaborador || null,
      });
    }
    if (!colaboradorCorreo) {
      bump(report, 'missing_colaboradorCorreo', {
        id: doc.id,
        colaborador: data.colaborador || null,
        sedeId: data.sedeId || null,
      });
    }
    if (!colaboradorCorreo && colaborador) {
      bump(report, 'uses_name_as_identifier', {
        id: doc.id,
        colaborador: data.colaborador,
        sedeId: data.sedeId || null,
      });
    }

    for (const field of [
      'fechaInicio',
      'fechaFin',
      'fechaSolicitud',
      'fechaRetorno',
      'fechaPermiso',
    ]) {
      if (!(field in data)) continue;
      const issue = describeDateIssue(data[field]);
      if (issue) {
        bump(report, `${field}_${issue}`, {
          id: doc.id,
          value: data[field],
        });
      }
    }

    const numero = (data.numFormulario || '').toString().trim();
    if (numero) {
      increment(duplicateFormNumbers, `${sedeId}|${tipo}|${numero}`);
    }

    const probableKey = [
      colaboradorCorreo || colaborador,
      tipo,
      parseDateLike(data.fechaSolicitud)?.toISOString().slice(0, 10) || '',
      parseDateLike(data.fechaInicio)?.toISOString().slice(0, 10) || '',
      parseDateLike(data.fechaFin)?.toISOString().slice(0, 10) || '',
      normalize(data.motivo),
    ].join('|');
    if (probableKey.replace(/\|/g, '') !== '') {
      increment(probableDuplicates, probableKey);
    }
  }

  report.duplicates = {
    numFormularioPorSedeTipo: summarizeDuplicates(duplicateFormNumbers),
    probableSolicitudesDuplicadas: summarizeDuplicates(probableDuplicates),
  };
  return report;
}

async function diagnoseAsistencias() {
  const report = createCollectionReport('asistencias_realizadas');
  const snapshot = await db.collection('asistencias_realizadas').get();
  const probableDuplicates = new Map();

  for (const doc of snapshot.docs) {
    report.total += 1;
    const data = doc.data() || {};
    const correo = normalize(data.correo_usuario);
    const docente = normalize(data.docente);

    if (!validSedeId(data.sedeId)) {
      bump(report, 'missing_or_invalid_sedeId', {
        id: doc.id,
        correo_usuario: correo || null,
        docente: data.docente || null,
      });
    }
    if (!correo) {
      bump(report, 'missing_correo_usuario', {
        id: doc.id,
        docente: data.docente || null,
        tipo: data.tipo || null,
      });
    }
    if (!correo && docente) {
      bump(report, 'uses_name_as_identifier', {
        id: doc.id,
        docente: data.docente,
        tipo: data.tipo || null,
      });
    }

    const fechaIssue = describeDateIssue(data.fecha);
    if (fechaIssue) {
      bump(report, `fecha_${fechaIssue}`, {
        id: doc.id,
        value: data.fecha,
      });
    }

    const fecha = parseDateLike(data.fecha);
    const dateKey = fecha ? fecha.toISOString().slice(0, 10) : '';
    const probableKey = [
      correo || docente,
      dateKey,
      normalize(data.tipo),
      normalize(data.horario_ref),
      normalize(data.tipo_vinculacion),
      normalize(data.hora_marcada || data.hora),
    ].join('|');
    if (probableKey.replace(/\|/g, '') !== '') {
      increment(probableDuplicates, probableKey);
    }
  }

  report.duplicates = {
    probableMarcacionesDuplicadas: summarizeDuplicates(probableDuplicates),
  };
  return report;
}

async function diagnoseRegistrosAlmuerzo() {
  const report = createCollectionReport('registros_almuerzo');
  const snapshot = await db.collection('registros_almuerzo').get();
  const duplicatePerDay = new Map();

  for (const doc of snapshot.docs) {
    report.total += 1;
    const data = doc.data() || {};
    const correo = normalize(data.correo_usuario);
    const nombre = normalize(data.nombre_usuario);

    if (!validSedeId(data.sedeId)) {
      bump(report, 'missing_or_invalid_sedeId', {
        id: doc.id,
        correo_usuario: correo || null,
        nombre_usuario: data.nombre_usuario || null,
      });
    }
    if (!correo) {
      bump(report, 'missing_correo_usuario', {
        id: doc.id,
        nombre_usuario: data.nombre_usuario || null,
        fecha: data.fecha || null,
      });
    }
    if (!correo && nombre) {
      bump(report, 'uses_name_as_identifier', {
        id: doc.id,
        nombre_usuario: data.nombre_usuario,
        fecha: data.fecha || null,
      });
    }

    const fechaIssue = describeYmdFieldIssue(data.fecha);
    if (fechaIssue) {
      bump(report, `fecha_${fechaIssue}`, {
        id: doc.id,
        value: data.fecha,
      });
    }

    const timestampIssue = describeDateIssue(data.timestamp);
    if (timestampIssue) {
      bump(report, `timestamp_${timestampIssue}`, {
        id: doc.id,
        value: data.timestamp,
      });
    }

    const dayKey = `${correo || nameKey(nombre)}|${(data.fecha || '').toString().trim()}`;
    if (dayKey !== '|') {
      increment(duplicatePerDay, dayKey);
    }
  }

  report.duplicates = {
    porUsuarioFecha: summarizeDuplicates(duplicatePerDay),
  };
  return report;
}

function nameKey(value) {
  return normalize(value).replace(/\s+/g, '_');
}

async function main() {
  const startedAt = new Date().toISOString();
  const reports = await Promise.all([
    diagnoseUsuarios(),
    diagnoseSolicitudes(),
    diagnoseAsistencias(),
    diagnoseRegistrosAlmuerzo(),
  ]);

  const output = {
    generatedAt: startedAt,
    projectId: admin.app().options.projectId || null,
    readOnly: true,
    collections: reports,
    migrationNotes: {
      usuarios: [
        'Migrar password legacy solo cuando todos los usuarios tengan passwordHash y passwordSalt.',
        'Completar sedeId antes de endurecer reglas o queries por sede.',
      ],
      solicitudes: [
        'Completar colaboradorCorreo para evitar cruces por nombre.',
        'Normalizar fechas Timestamp/string antes de depender totalmente de Solicitud.fromMap.',
      ],
      asistencias_realizadas: [
        'Completar correo_usuario y sedeId en registros historicos.',
        'Conservar docente solo como campo visual y compatibilidad legacy.',
      ],
      registros_almuerzo: [
        'Completar correo_usuario, sedeId y timestamp en historicos.',
        'Revisar duplicados por usuario+fecha antes de consolidar o limpiar.',
      ],
    },
  };

  console.log(JSON.stringify(output, null, 2));
}

main().catch((error) => {
  console.error('Legacy data diagnosis failed:', error);
  process.exitCode = 1;
});
