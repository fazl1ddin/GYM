// Сквозной тест API FaceClock. Поднимает сервер на отдельном порту,
// прогоняет весь поток (сотрудник + админ + защита) и печатает результат.
// Запуск: npm test
import { spawn } from 'node:child_process';
import { rmSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const PORT = process.env.TEST_PORT || 3099;
const BASE = `http://localhost:${PORT}`;

// изолированная временная БД — прогон детерминирован и не трогает данные
const TEST_DATA = mkdtempSync(join(tmpdir(), 'faceclock-test-'));
process.env.FACECLOCK_DATA_DIR = TEST_DATA;
process.env.PORT = String(PORT);

function sh(cmd, args) {
  return new Promise((res, rej) => {
    const p = spawn(cmd, args, { cwd: ROOT, stdio: 'inherit' });
    p.on('exit', (code) => (code === 0 ? res() : rej(new Error(`${cmd} exit ${code}`))));
  });
}

async function waitUp(ms = 8000) {
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    try { const r = await fetch(BASE + '/'); if (r.ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 200));
  }
  throw new Error('сервер не поднялся');
}

let cookie = '';
async function call(path, { method = 'GET', body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const sc = res.headers.get('set-cookie');
  if (sc) cookie = sc.split(';')[0];
  let data; try { data = await res.json(); } catch { data = null; }
  return { status: res.status, data };
}
const vec = (seed) => Array.from({ length: 128 }, (_, i) => Math.sin(seed + i * 0.1));

let passed = 0, failed = 0;
function ok(name, cond, extra = '') {
  console.log(`${cond ? '✅' : '❌'} ${name}${extra ? '  ' + extra : ''}`);
  cond ? passed++ : failed++;
}

// подготовка окружения
await sh('npm', ['run', 'seed']);

// логический тест использует клиентские векторы (без ML) — детерминирован и быстр
const server = spawn('node', ['--experimental-sqlite', 'server/index.js'], {
  cwd: ROOT, env: { ...process.env, PORT: String(PORT), FACECLOCK_SERVER_EMBED: 'off' }, stdio: 'ignore',
});
try {
  await waitUp();

  // ---- сотрудник ----
  let r = await call('/api/login', { method: 'POST', body: { login: 'aziz', password: 'aziz123' } });
  ok('логин сотрудника', r.status === 200 && r.data.user.role === 'employee');

  const myFace = vec(1);
  r = await call('/api/enroll', { method: 'POST', body: { embedding: myFace, deviceId: 'dev-1' } });
  ok('регистрация лица', r.status === 200);

  const office = { lat: 41.311081, lng: 69.240562, accuracy: 20 };
  async function checkin({ type, face, liveOk = true, geo = office, device = 'dev-1' }) {
    const c = await call('/api/checkin/challenge', { method: 'POST', body: { type } });
    return call('/api/checkin', { method: 'POST', body: {
      type, nonce: c.data.nonce, embedding: face,
      liveness: { challenge: liveOk ? c.data.challenge : 'wrong', passed: liveOk, score: liveOk ? 0.95 : 0.1 },
      geo, deviceId: device,
    } });
  }

  r = await checkin({ type: 'in', face: myFace });
  ok('приход (всё ок) → confirmed', r.data.status === 'confirmed', `sim=${r.data.similarity}`);
  r = await checkin({ type: 'out', face: vec(99) });
  ok('чужое лицо → pending', r.data.status === 'pending', `sim=${r.data.similarity}`);
  r = await checkin({ type: 'out', face: myFace, liveOk: false });
  ok('провал живости → отклонено', r.status === 400);
  r = await checkin({ type: 'out', face: myFace, geo: { lat: 41.5, lng: 69.5, accuracy: 20 } });
  ok('вне геозоны → pending', r.data.status === 'pending', `dist=${r.data.distanceM}м`);
  r = await checkin({ type: 'out', face: myFace, device: 'other-phone' });
  ok('другое устройство → pending', r.data.status === 'pending');

  const c = await call('/api/checkin/challenge', { method: 'POST', body: { type: 'in' } });
  const body = { type: 'in', nonce: c.data.nonce, embedding: myFace,
    liveness: { challenge: c.data.challenge, passed: true, score: 0.95 }, geo: office, deviceId: 'dev-1' };
  await call('/api/checkin', { method: 'POST', body });
  r = await call('/api/checkin', { method: 'POST', body });
  ok('повторный nonce (replay) → 400', r.status === 400);

  r = await call('/api/attendance/me');
  ok('история сотрудника', r.status === 200);

  // ---- админ ----
  r = await call('/api/login', { method: 'POST', body: { login: 'admin', password: 'admin123' } });
  ok('логин админа', r.status === 200 && r.data.user.role === 'admin');
  r = await call('/api/admin/employees');
  ok('список сотрудников', r.status === 200);
  r = await call('/api/admin/employees', { method: 'POST', body: { name: 'Тест', login: 'test' + Date.now(), password: 'x12345', role: 'employee' } });
  ok('создать сотрудника', r.status === 200);
  const id = r.data.employee.id;
  r = await call(`/api/admin/employees/${id}`, { method: 'PATCH', body: { active: false } });
  ok('деактивировать', r.status === 200 && r.data.employee.active === false);
  r = await call(`/api/admin/employees/${id}`, { method: 'DELETE' });
  ok('удалить', r.status === 200);
  r = await call('/api/admin/anomalies');
  ok('очередь аномалий', r.status === 200);
  r = await call('/api/admin/stats');
  ok('статистика', r.status === 200);

  await call('/api/login', { method: 'POST', body: { login: 'aziz', password: 'aziz123' } });
  r = await call('/api/admin/employees');
  ok('сотрудник НЕ имеет доступа к админке', r.status === 403);

  console.log(`\n${failed === 0 ? '✅' : '❌'} Пройдено ${passed}, провалено ${failed}`);
} finally {
  server.kill('SIGKILL');
  try { rmSync(TEST_DATA, { recursive: true, force: true }); } catch {}
}
process.exit(failed === 0 ? 0 : 1);
