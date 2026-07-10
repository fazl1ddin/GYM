import express from 'express';
import { writeFileSync, readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import crypto from 'node:crypto';
import { db, PHOTOS_DIR } from './db.js';
import {
  POLICY, hashPassword, verifyPassword, signSession, verifySession, randomNonce,
} from './security.js';
import { isValidEmbedding, bestSimilarity, bestDistance, euclideanDistance } from './face.js';
import { checkGeozone } from './geo.js';
import { scoreRisk } from './risk.js';
import { initFaceEmbed, isReady as faceReady, embedFromDataUrl } from './faceEmbed.js';
import { verifyLiveness } from './liveness.js';
import { currentCode, qrPayload, validateCode, parsePayload, newSecret } from './qr.js';
import {
  isLocked, lockRemainingSec, registerFail, registerSuccess,
  makeRateLimiter, securityHeaders,
} from './ratelimit.js';

const app = express();
app.set('trust proxy', true);
app.use(securityHeaders);
app.use(express.json({ limit: '16mb' }));

// -------- cookie helpers --------
function parseCookies(req) {
  const out = {};
  (req.headers.cookie || '').split(';').forEach((p) => {
    const i = p.indexOf('=');
    if (i > -1) out[p.slice(0, i).trim()] = decodeURIComponent(p.slice(i + 1).trim());
  });
  return out;
}
function setSession(res, employee) {
  const token = signSession({ id: employee.id, role: employee.role, exp: Date.now() + 7 * 864e5 });
  res.setHeader('Set-Cookie',
    `sess=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${7 * 86400}`);
}

// -------- auth middleware --------
function currentUser(req) {
  const { sess } = parseCookies(req);
  const payload = verifySession(sess);
  if (!payload) return null;
  const emp = db.prepare('SELECT * FROM employees WHERE id = ? AND active = 1').get(payload.id);
  return emp || null;
}
function requireAuth(req, res, next) {
  const u = currentUser(req);
  if (!u) return res.status(401).json({ error: 'Требуется вход' });
  req.user = u;
  next();
}
function requireAdmin(req, res, next) {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Только для администратора' });
  next();
}

// -------- photo storage --------
function savePhoto(dataUrl) {
  if (!dataUrl || typeof dataUrl !== 'string') return null;
  const m = dataUrl.match(/^data:image\/(\w+);base64,(.+)$/s);
  const b64 = m ? m[2] : dataUrl;
  const ext = m ? m[1].replace('jpeg', 'jpg') : 'jpg';
  const name = `${Date.now()}_${crypto.randomBytes(6).toString('hex')}.${ext}`;
  try {
    writeFileSync(join(PHOTOS_DIR, name), Buffer.from(b64, 'base64'));
    return name;
  } catch { return null; }
}

function publicEmployee(e) {
  return {
    id: e.id, name: e.name, login: e.login, role: e.role,
    workplaceId: e.workplace_id, active: !!e.active, enrolled: !!e.enrolled,
    deviceBound: !!e.device_id, createdAt: e.created_at,
  };
}

// ================= AUTH =================
const loginLimiter = makeRateLimiter({ windowMs: 60_000, max: 20 });
app.post('/api/login', loginLimiter, (req, res) => {
  const { login, password } = req.body || {};
  const ip = req.ip || 'unknown';
  const name = String(login || '').trim();

  // Блокировка перебора паролей (улучшение №5)
  if (isLocked(name, ip)) {
    return res.status(429).json({
      error: `Слишком много попыток. Повторите через ${Math.ceil(lockRemainingSec(name, ip) / 60)} мин.`,
    });
  }
  const emp = db.prepare('SELECT * FROM employees WHERE login = ?').get(name);
  if (!emp || !emp.active || !verifyPassword(String(password || ''), emp.pass_hash)) {
    registerFail(name, ip);
    return res.status(401).json({ error: 'Неверный логин или пароль' });
  }
  registerSuccess(name, ip);
  setSession(res, emp);
  res.json({ user: publicEmployee(emp) });
});

app.post('/api/logout', (req, res) => {
  res.setHeader('Set-Cookie', 'sess=; HttpOnly; Path=/; Max-Age=0');
  res.json({ ok: true });
});

app.get('/api/me', requireAuth, (req, res) => {
  res.json({ user: publicEmployee(req.user) });
});

app.get('/api/config', (req, res) => {
  res.json({
    faceMatchMinSimilarity: POLICY.faceMatchMinSimilarity,
    livenessMinScore: POLICY.livenessMinScore,
    challengeTtlMs: POLICY.challengeTtlMs,
    requireGeo: POLICY.requireGeo,
    requireLiveness: POLICY.requireLiveness,
    challenges: POLICY.challenges,
    serverSideEmbedding: POLICY.serverSideEmbedding,
    faceReady: POLICY.serverSideEmbedding ? faceReady() : true,
    serverTime: Date.now(),
  });
});

// ================= ENROLLMENT =================
app.post('/api/enroll', requireAuth, async (req, res) => {
  const { embedding, photo, deviceId } = req.body || {};

  // Дескриптор лица считает сервер из фото (не доверяем клиенту).
  let descriptor = null;
  if (POLICY.serverSideEmbedding) {
    if (!faceReady()) return res.status(503).json({ error: 'Модели распознавания ещё загружаются, повторите' });
    if (!photo) return res.status(400).json({ error: 'Нужно фото лица' });
    const r = await embedFromDataUrl(photo);
    if (!r) return res.status(400).json({ error: 'Лицо на фото не найдено, повторите' });
    descriptor = r.descriptor;
  } else {
    if (!isValidEmbedding(embedding)) return res.status(400).json({ error: 'Некорректный эмбеддинг лица' });
    descriptor = embedding;
  }

  // Детекция дублей: это лицо не должно быть уже привязано к другому сотруднику (№4)
  if (POLICY.serverSideEmbedding) {
    const others = db.prepare('SELECT descriptor FROM face_templates WHERE employee_id != ?').all(req.user.id);
    for (const o of others) {
      if (euclideanDistance(descriptor, JSON.parse(o.descriptor)) < POLICY.faceDupMaxDistance) {
        return res.status(409).json({ error: 'Это лицо уже зарегистрировано за другим сотрудником' });
      }
    }
  }

  const photoRef = savePhoto(photo);
  db.prepare('INSERT INTO face_templates (employee_id, descriptor, photo_ref) VALUES (?,?,?)')
    .run(req.user.id, JSON.stringify(descriptor), photoRef);
  // привязка устройства при регистрации лица
  if (POLICY.bindDevice && deviceId && !req.user.device_id) {
    db.prepare('UPDATE employees SET device_id = ? WHERE id = ?').run(String(deviceId), req.user.id);
  }
  db.prepare('UPDATE employees SET enrolled = 1 WHERE id = ?').run(req.user.id);
  res.json({ ok: true });
});

// ================= CHECK-IN =================
app.post('/api/checkin/challenge', requireAuth, (req, res) => {
  const type = req.body?.type === 'out' ? 'out' : 'in';
  if (!req.user.enrolled) return res.status(400).json({ error: 'Сначала зарегистрируйте лицо' });
  const nonce = randomNonce();
  const challenge = POLICY.challenges[crypto.randomInt(POLICY.challenges.length)];
  const now = Date.now();
  db.prepare(`INSERT INTO challenges (nonce, employee_id, challenge, kind, expires_at, created_at)
              VALUES (?,?,?,?,?,?)`)
    .run(nonce, req.user.id, challenge, type, now + POLICY.challengeTtlMs, now);
  const wp = req.user.workplace_id
    ? db.prepare('SELECT * FROM workplaces WHERE id = ?').get(req.user.workplace_id) : null;
  res.json({
    nonce, challenge, type,
    serverTime: now, expiresAt: now + POLICY.challengeTtlMs,
    workplace: wp ? {
      id: wp.id, name: wp.name, address: wp.address, lat: wp.lat, lng: wp.lng,
      radiusM: wp.radius_m, requireQr: !!wp.require_qr,
    } : null,
  });
});

app.post('/api/checkin', requireAuth, async (req, res) => {
  const { type, nonce, embedding, photo, liveness, livenessFrames, qr, geo, deviceId, clientFlags } = req.body || {};
  const now = Date.now();

  if (!req.user.enrolled) return res.status(400).json({ error: 'Сначала зарегистрируйте лицо' });
  if (POLICY.serverSideEmbedding) {
    if (!faceReady()) return res.status(503).json({ error: 'Модели распознавания ещё загружаются, повторите' });
    if (!photo) return res.status(400).json({ error: 'Нужно фото лица' });
  } else if (!isValidEmbedding(embedding)) {
    return res.status(400).json({ error: 'Некорректный эмбеддинг лица' });
  }

  // --- 1. Одноразовый nonce + анти-replay + серверное время (уровень 1) ---
  const ch = db.prepare('SELECT * FROM challenges WHERE nonce = ? AND employee_id = ?').get(nonce, req.user.id);
  if (!ch) return res.status(400).json({ error: 'Недействительная сессия отметки' });
  if (ch.used) return res.status(400).json({ error: 'Эта сессия уже использована' });
  if (now > ch.expires_at) return res.status(400).json({ error: 'Время сессии истекло, начните заново' });
  db.prepare('UPDATE challenges SET used = 1 WHERE nonce = ?').run(nonce); // consume
  if (ch.kind !== (type === 'out' ? 'out' : 'in')) return res.status(400).json({ error: 'Тип отметки не совпадает' });

  // --- 2. Живость: выполнено ИМЕННО выданное действие (уровень 1) ---
  // При серверной проверке сервер сам анализирует кадры (не доверяет клиенту).
  let livenessScore, livenessPassed, livenessReason = null;
  if (POLICY.serverSideLiveness) {
    const v = await verifyLiveness(ch.challenge, livenessFrames);
    livenessPassed = v.passed;
    livenessScore = v.score;
    livenessReason = v.reason;
  } else {
    livenessScore = Number(liveness?.score ?? 0);
    livenessPassed = liveness?.challenge === ch.challenge && liveness?.passed === true;
  }
  if (POLICY.requireLiveness && !livenessPassed) {
    // не то действие / подделка / запись → жёсткий отказ
    db.prepare(`INSERT INTO attendance
      (employee_id,type,server_time,liveness_score,liveness_challenge,risk_score,risk_flags,status,photo_ref,device_id)
      VALUES (?,?,?,?,?,?,?,?,?,?)`).run(
      req.user.id, ch.kind, now, livenessScore, ch.challenge, 100,
      JSON.stringify([`провал проверки живости${livenessReason ? ': ' + livenessReason : ''}`]),
      'rejected', savePhoto(photo), deviceId || null);
    return res.status(400).json({ error: `Проверка живости не пройдена${livenessReason ? ': ' + livenessReason : ''}. Повторите.` });
  }

  // --- 3. Сравнение лица на сервере (уровень 1/2) ---
  const templates = db.prepare('SELECT descriptor FROM face_templates WHERE employee_id = ?')
    .all(req.user.id).map((r) => JSON.parse(r.descriptor));

  let matched, faceWeak, faceMetric;
  if (POLICY.serverSideEmbedding) {
    // сервер сам считает вектор из фото — вектор клиента игнорируется
    const emb = await embedFromDataUrl(photo);
    if (!emb) return res.status(400).json({ error: 'Лицо на фото не найдено, повторите' });
    const distance = bestDistance(emb.descriptor, templates);
    matched = distance <= POLICY.faceMatchMaxDistance;
    faceWeak = matched && distance > POLICY.faceMatchMaxDistance - 0.08;
    faceMetric = Number(distance.toFixed(3));
  } else {
    const similarity = bestSimilarity(embedding, templates);
    matched = similarity >= POLICY.faceMatchMinSimilarity;
    faceWeak = matched && similarity < POLICY.faceMatchMinSimilarity + 0.08;
    faceMetric = Number(similarity.toFixed(3));
  }

  // --- 4. Привязка устройства (уровень 2) ---
  let deviceMismatch = false, deviceNew = false;
  if (POLICY.bindDevice && deviceId) {
    if (req.user.device_id && req.user.device_id !== deviceId) deviceMismatch = true;
    else if (!req.user.device_id) {
      deviceNew = true;
      db.prepare('UPDATE employees SET device_id = ? WHERE id = ?').run(String(deviceId), req.user.id);
    }
  }

  // --- 5. Геозона (уровень 3) ---
  const wp = req.user.workplace_id
    ? db.prepare('SELECT * FROM workplaces WHERE id = ?').get(req.user.workplace_id) : null;
  const geoCheck = geo ? checkGeozone(wp, geo.lat, geo.lng) : { inside: false, distance: null, reason: 'no_location' };

  // --- 5b. Динамический QR на проходной (уровень 3, улучшение №3) ---
  let qrOk = null, qrRequiredMissing = false;
  if (wp?.qr_secret) {
    const parsed = parsePayload(qr);
    qrOk = !!(parsed && parsed.workplaceId === wp.id && validateCode(wp.qr_secret, parsed.code, now));
    if (wp.require_qr && !qrOk) qrRequiredMissing = true;
  }

  // --- 6. Риск-скоринг (уровень 4) ---
  const risk = scoreRisk({
    geo: geoCheck, accuracy: geo?.accuracy, workplace: wp,
    faceMatched: matched, faceWeak,
    liveness: livenessScore, minLiveness: POLICY.livenessMinScore,
    deviceMismatch, deviceNew, clientFlags, qrRequiredMissing,
  });

  // --- Итоговый статус ---
  const inGeo = !POLICY.requireGeo || geoCheck.inside;
  const live = !POLICY.requireLiveness || (livenessPassed && livenessScore >= POLICY.livenessMinScore);
  const qrPass = !qrRequiredMissing;
  const ok = matched && live && inGeo && qrPass && risk.score <= POLICY.autoConfirmMaxRisk;
  const status = ok ? 'confirmed' : 'pending'; // спорные → очередь аномалий, не засчитываются автоматически

  const photoRef = savePhoto(photo);
  const info = db.prepare(`INSERT INTO attendance
    (employee_id,type,server_time,geo_lat,geo_lng,geo_accuracy,distance_m,workplace_id,
     match_distance,liveness_score,liveness_challenge,risk_score,risk_flags,status,photo_ref,device_id,qr_ok)
    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`).run(
    req.user.id, ch.kind, now, geo?.lat ?? null, geo?.lng ?? null, geo?.accuracy ?? null,
    geoCheck.distance ?? null, wp?.id ?? null, faceMetric, livenessScore, ch.challenge,
    risk.score, JSON.stringify(risk.flags), status, photoRef, deviceId || null, qrOk == null ? null : (qrOk ? 1 : 0));

  res.json({
    id: info.lastInsertRowid,
    type: ch.kind, status, serverTime: now,
    similarity: faceMetric, matched,
    liveness: livenessScore, inGeozone: geoCheck.inside,
    distanceM: geoCheck.distance != null ? Math.round(geoCheck.distance) : null,
    riskScore: risk.score, riskFlags: risk.flags,
    message: status === 'confirmed'
      ? (ch.kind === 'in' ? 'Приход отмечен' : 'Уход отмечен')
      : 'Отметка отправлена на проверку руководителю',
  });
});

// ================= EMPLOYEE HISTORY =================
function shiftStatus(employeeId) {
  const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
  const last = db.prepare(`SELECT * FROM attendance
    WHERE employee_id = ? AND status IN ('confirmed','pending')
    ORDER BY server_time DESC LIMIT 1`).get(employeeId);
  const onShift = last && last.type === 'in';
  return { onShift, since: onShift ? last.server_time : null };
}

app.get('/api/attendance/me', requireAuth, (req, res) => {
  const rows = db.prepare(`SELECT id,type,server_time,status,risk_score,risk_flags,distance_m
    FROM attendance WHERE employee_id = ? ORDER BY server_time DESC LIMIT 50`).all(req.user.id);
  res.json({
    status: shiftStatus(req.user.id),
    records: rows.map((r) => ({
      id: r.id, type: r.type, time: r.server_time, status: r.status,
      riskScore: r.risk_score, riskFlags: JSON.parse(r.risk_flags || '[]'),
      distanceM: r.distance_m,
    })),
  });
});

// ================= ADMIN =================
app.get('/api/admin/employees', requireAuth, requireAdmin, (req, res) => {
  const rows = db.prepare('SELECT * FROM employees ORDER BY role DESC, name').all();
  res.json({ employees: rows.map(publicEmployee) });
});

app.post('/api/admin/employees', requireAuth, requireAdmin, (req, res) => {
  const { name, login, password, role, workplaceId } = req.body || {};
  if (!name || !login || !password) return res.status(400).json({ error: 'Заполните имя, логин и пароль' });
  const exists = db.prepare('SELECT 1 FROM employees WHERE login = ?').get(String(login).trim());
  if (exists) return res.status(409).json({ error: 'Логин уже занят' });
  const info = db.prepare(`INSERT INTO employees (name,login,pass_hash,role,workplace_id)
    VALUES (?,?,?,?,?)`).run(
    String(name).trim(), String(login).trim(), hashPassword(String(password)),
    role === 'admin' ? 'admin' : 'employee', workplaceId || null);
  res.json({ employee: publicEmployee(db.prepare('SELECT * FROM employees WHERE id = ?').get(info.lastInsertRowid)) });
});

app.patch('/api/admin/employees/:id', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const emp = db.prepare('SELECT * FROM employees WHERE id = ?').get(id);
  if (!emp) return res.status(404).json({ error: 'Сотрудник не найден' });
  const { name, role, workplaceId, active, password, resetDevice, resetFace } = req.body || {};
  if (name != null) db.prepare('UPDATE employees SET name = ? WHERE id = ?').run(String(name).trim(), id);
  if (role != null) db.prepare('UPDATE employees SET role = ? WHERE id = ?').run(role === 'admin' ? 'admin' : 'employee', id);
  if (workplaceId !== undefined) db.prepare('UPDATE employees SET workplace_id = ? WHERE id = ?').run(workplaceId || null, id);
  if (active != null) db.prepare('UPDATE employees SET active = ? WHERE id = ?').run(active ? 1 : 0, id);
  if (password) db.prepare('UPDATE employees SET pass_hash = ? WHERE id = ?').run(hashPassword(String(password)), id);
  if (resetDevice) db.prepare('UPDATE employees SET device_id = NULL WHERE id = ?').run(id);
  if (resetFace) {
    db.prepare('DELETE FROM face_templates WHERE employee_id = ?').run(id);
    db.prepare('UPDATE employees SET enrolled = 0 WHERE id = ?').run(id);
  }
  res.json({ employee: publicEmployee(db.prepare('SELECT * FROM employees WHERE id = ?').get(id)) });
});

app.delete('/api/admin/employees/:id', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  if (id === req.user.id) return res.status(400).json({ error: 'Нельзя удалить самого себя' });
  db.prepare('DELETE FROM employees WHERE id = ?').run(id);
  res.json({ ok: true });
});

// ---- workplaces ----
app.get('/api/admin/workplaces', requireAuth, requireAdmin, (req, res) => {
  const rows = db.prepare('SELECT * FROM workplaces ORDER BY name').all();
  res.json({ workplaces: rows.map((w) => ({
    id: w.id, name: w.name, address: w.address, lat: w.lat, lng: w.lng,
    radiusM: w.radius_m, requireQr: !!w.require_qr, hasQr: !!w.qr_secret })) });
});
app.post('/api/admin/workplaces', requireAuth, requireAdmin, (req, res) => {
  const { name, address, lat, lng, radiusM, requireQr } = req.body || {};
  if (!name) return res.status(400).json({ error: 'Укажите название' });
  const info = db.prepare('INSERT INTO workplaces (name,address,lat,lng,radius_m,qr_secret,require_qr) VALUES (?,?,?,?,?,?,?)')
    .run(String(name).trim(), address || null, lat ?? null, lng ?? null, radiusM || 150, newSecret(), requireQr ? 1 : 0);
  res.json({ id: info.lastInsertRowid });
});
// Текущий QR-код терминала для показа на экране рабочего места (улучшение №3).
app.get('/api/admin/workplaces/:id/qr', requireAuth, requireAdmin, (req, res) => {
  const w = db.prepare('SELECT * FROM workplaces WHERE id = ?').get(Number(req.params.id));
  if (!w) return res.status(404).json({ error: 'Не найдено' });
  if (!w.qr_secret) db.prepare('UPDATE workplaces SET qr_secret = ? WHERE id = ?').run(newSecret(), w.id);
  const secret = db.prepare('SELECT qr_secret FROM workplaces WHERE id = ?').get(w.id).qr_secret;
  const { secondsLeft } = currentCode(secret);
  res.json({ payload: qrPayload(w.id, secret), secondsLeft, windowMs: 30000 });
});
app.patch('/api/admin/workplaces/:id', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const { name, address, lat, lng, radiusM } = req.body || {};
  const w = db.prepare('SELECT * FROM workplaces WHERE id = ?').get(id);
  if (!w) return res.status(404).json({ error: 'Не найдено' });
  const { requireQr } = req.body || {};
  db.prepare('UPDATE workplaces SET name=?,address=?,lat=?,lng=?,radius_m=?,require_qr=? WHERE id=?').run(
    name ?? w.name, address ?? w.address, lat ?? w.lat, lng ?? w.lng, radiusM ?? w.radius_m,
    requireQr == null ? w.require_qr : (requireQr ? 1 : 0), id);
  res.json({ ok: true });
});
app.delete('/api/admin/workplaces/:id', requireAuth, requireAdmin, (req, res) => {
  db.prepare('DELETE FROM workplaces WHERE id = ?').run(Number(req.params.id));
  res.json({ ok: true });
});

// ---- attendance log + anomalies ----
function attendanceRow(r) {
  const emp = db.prepare('SELECT name FROM employees WHERE id = ?').get(r.employee_id);
  return {
    id: r.id, employeeId: r.employee_id, employeeName: emp?.name || '—',
    type: r.type, time: r.server_time, status: r.status,
    similarity: r.match_distance, liveness: r.liveness_score,
    distanceM: r.distance_m, riskScore: r.risk_score,
    riskFlags: JSON.parse(r.risk_flags || '[]'), photoRef: r.photo_ref,
    decisionComment: r.decision_comment,
  };
}
app.get('/api/admin/attendance', requireAuth, requireAdmin, (req, res) => {
  const { status } = req.query;
  const rows = status
    ? db.prepare('SELECT * FROM attendance WHERE status = ? ORDER BY server_time DESC LIMIT 200').all(String(status))
    : db.prepare('SELECT * FROM attendance ORDER BY server_time DESC LIMIT 200').all();
  res.json({ records: rows.map(attendanceRow) });
});
app.get('/api/admin/anomalies', requireAuth, requireAdmin, (req, res) => {
  const rows = db.prepare("SELECT * FROM attendance WHERE status = 'pending' ORDER BY risk_score DESC, server_time DESC").all();
  res.json({ records: rows.map(attendanceRow) });
});
app.post('/api/admin/attendance/:id/decision', requireAuth, requireAdmin, (req, res) => {
  const id = Number(req.params.id);
  const { decision, comment } = req.body || {};
  const status = decision === 'confirm' ? 'confirmed' : decision === 'reject' ? 'rejected' : null;
  if (!status) return res.status(400).json({ error: 'decision: confirm|reject' });
  db.prepare('UPDATE attendance SET status=?, decided_by=?, decision_comment=?, decided_at=? WHERE id=?')
    .run(status, req.user.id, comment || null, Date.now(), id);
  res.json({ ok: true });
});
app.get('/api/admin/photo/:ref', requireAuth, requireAdmin, (req, res) => {
  const ref = req.params.ref.replace(/[^\w.\-]/g, '');
  const p = join(PHOTOS_DIR, ref);
  if (!existsSync(p)) return res.status(404).end();
  res.setHeader('Content-Type', 'image/jpeg');
  res.send(readFileSync(p));
});
app.get('/api/admin/stats', requireAuth, requireAdmin, (req, res) => {
  const startOfDay = new Date(); startOfDay.setHours(0, 0, 0, 0);
  res.json({
    employees: db.prepare("SELECT COUNT(*) c FROM employees WHERE role='employee'").get().c,
    onShift: db.prepare(`SELECT COUNT(*) c FROM (
      SELECT a.employee_id, a.type FROM attendance a
      JOIN (SELECT employee_id, MAX(server_time) mt FROM attendance WHERE status IN ('confirmed','pending') GROUP BY employee_id) l
      ON a.employee_id=l.employee_id AND a.server_time=l.mt WHERE a.type='in')`).get().c,
    pending: db.prepare("SELECT COUNT(*) c FROM attendance WHERE status='pending'").get().c,
    todayEvents: db.prepare('SELECT COUNT(*) c FROM attendance WHERE server_time >= ?').get(startOfDay.getTime()).c,
  });
});

app.get('/', (req, res) => res.json({ app: 'FaceClock API', status: 'ok' }));

const PORT = process.env.PORT || 3000;
// Прогреваем модели распознавания заранее (если включён серверный эмбеддинг).
if (POLICY.serverSideEmbedding) initFaceEmbed();
app.listen(PORT, () => console.log(`FaceClock API на http://localhost:${PORT}`));
