// Тест серверного распознавания лица (улучшение №2).
// Проверяет: сервер сам считает эмбеддинг из фото, различает людей, отвергает
// кадр без лица; и весь HTTP-путь регистрации/отметки на реальных снимках.
// Запуск: npm run test:face
import { createRequire } from 'node:module';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { initFaceEmbed, embedFromDataUrl } from './faceEmbed.js';
import { euclideanDistance } from './face.js';
import { earFromLandmarks, turnMagnitude, verifyLiveness } from './liveness.js';

const require = createRequire(import.meta.url);
const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const demo = join(require.resolve('@vladmandic/face-api/package.json'), '..', 'demo');
const dataUrl = (f) => `data:image/jpeg;base64,${readFileSync(join(demo, f)).toString('base64')}`;

let passed = 0, failed = 0;
const ok = (n, c, e = '') => { console.log(`${c ? '✅' : '❌'} ${n}${e ? '  ' + e : ''}`); c ? passed++ : failed++; };

console.log('Загрузка моделей…');
await initFaceEmbed();

// ---------- модульные проверки ----------
const A = await embedFromDataUrl(dataUrl('sample1.jpg'));
ok('лицо найдено, дескриптор 128-мерный', A && A.descriptor.length === 128);

const A2 = await embedFromDataUrl(dataUrl('sample1.jpg'));
ok('то же фото → дистанция ≈ 0 (совпадение)', euclideanDistance(A.descriptor, A2.descriptor) < 0.01,
  `d=${euclideanDistance(A.descriptor, A2.descriptor).toFixed(4)}`);

let maxD = 0, farImg = null;
for (const f of ['sample2.jpg', 'sample3.jpg', 'sample4.jpg', 'sample5.jpg', 'sample6.jpg']) {
  const r = await embedFromDataUrl(dataUrl(f));
  if (r) { const d = euclideanDistance(A.descriptor, r.descriptor); if (d > maxD) { maxD = d; farImg = f; } }
}
ok('другой человек → дистанция выше порога (различает людей)', maxD > 0.55, `maxDist=${maxD.toFixed(3)} (${farImg})`);

// изображение без лица
const tf = require('@tensorflow/tfjs-node');
const blankBuf = await tf.node.encodeJpeg(tf.zeros([160, 160, 3], 'int32'));
const blankUrl = `data:image/jpeg;base64,${Buffer.from(blankBuf).toString('base64')}`;
const none = await embedFromDataUrl(blankUrl);
ok('кадр без лица → лицо не найдено (null)', none === null);

// ---------- проверка живости: юнит-функции (улучшение №1) ----------
function makeLm() { return Array.from({ length: 68 }, () => [0, 0]); }
const openEye = makeLm();
// левый глаз 36–41, правый 42–47 — «открытые» (большая вертикаль)
[[36, 0, 0], [39, 10, 0], [37, 3, -3], [38, 7, -3], [41, 3, 3], [40, 7, 3],
 [42, 0, 0], [45, 10, 0], [43, 3, -3], [44, 7, -3], [47, 3, 3], [46, 7, 3]]
  .forEach(([i, x, y]) => (openEye[i] = [x, y]));
const closedEye = makeLm();
[[36, 0, 0], [39, 10, 0], [37, 3, -0.5], [38, 7, -0.5], [41, 3, 0.5], [40, 7, 0.5],
 [42, 0, 0], [45, 10, 0], [43, 3, -0.5], [44, 7, -0.5], [47, 3, 0.5], [46, 7, 0.5]]
  .forEach(([i, x, y]) => (closedEye[i] = [x, y]));
ok('EAR: открытые глаза > закрытых', earFromLandmarks(openEye) > 0.3 && earFromLandmarks(closedEye) < 0.17,
  `open=${earFromLandmarks(openEye).toFixed(2)} closed=${earFromLandmarks(closedEye).toFixed(2)}`);

const frontal = makeLm(); frontal[36] = [0, 0]; frontal[45] = [10, 0]; frontal[30] = [5, 0];
const turned = makeLm(); turned[36] = [0, 0]; turned[45] = [10, 0]; turned[30] = [1, 0];
ok('поворот: анфас ≈ 0, поворот велик', turnMagnitude(frontal) < 0.15 && turnMagnitude(turned) > 0.5,
  `front=${turnMagnitude(frontal).toFixed(2)} turned=${turnMagnitude(turned).toFixed(2)}`);

const noFrames = await verifyLiveness('smile', []);
ok('живость без кадров → не пройдена', noFrames.passed === false);
const smileNoFace = await verifyLiveness('smile', [blankUrl]);
ok('живость по пустому кадру → не пройдена', smileNoFace.passed === false);

// ---------- HTTP-путь (реальный сервер, серверный эмбеддинг включён) ----------
const PORT = 3097;
const BASE = `http://localhost:${PORT}`;
const TEST_DATA = mkdtempSync(join(tmpdir(), 'faceclock-face-'));
// серверный эмбеддинг ВКЛючён (это цель теста), серверную живость выключаем —
// её юнит-функции проверены выше; здесь фокус на распознавании и дублях
const env = { ...process.env, PORT: String(PORT), FACECLOCK_DATA_DIR: TEST_DATA, FACECLOCK_SERVER_LIVENESS: 'off' };

await new Promise((res, rej) => {
  const p = spawn('node', ['--experimental-sqlite', 'server/seed.js'], { cwd: ROOT, env, stdio: 'ignore' });
  p.on('exit', (c) => (c === 0 ? res() : rej(new Error('seed failed'))));
});
const server = spawn('node', ['--experimental-sqlite', 'server/index.js'], { cwd: ROOT, env, stdio: 'ignore' });

let cookie = '';
async function call(path, { method = 'GET', body } = {}) {
  const res = await fetch(BASE + path, {
    method, headers: { 'Content-Type': 'application/json', ...(cookie ? { Cookie: cookie } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const sc = res.headers.get('set-cookie'); if (sc) cookie = sc.split(';')[0];
  let data; try { data = await res.json(); } catch { data = null; }
  return { status: res.status, data };
}

try {
  // ждём готовности моделей на сервере
  const t0 = Date.now();
  while (Date.now() - t0 < 20000) {
    try { const c = await (await fetch(BASE + '/api/config')).json(); if (c.faceReady) break; } catch {}
    await new Promise((r) => setTimeout(r, 300));
  }

  await call('/api/login', { method: 'POST', body: { login: 'aziz', password: 'aziz123' } });
  let r = await call('/api/enroll', { method: 'POST', body: { photo: dataUrl('sample1.jpg'), deviceId: 'dev-1' } });
  ok('регистрация лица по фото (сервер считает вектор)', r.status === 200);

  r = await call('/api/enroll', { method: 'POST', body: { photo: `data:image/jpeg;base64,${Buffer.from(blankBuf).toString('base64')}` } });
  ok('регистрация без лица на фото → 400', r.status === 400);

  const office = { lat: 41.311081, lng: 69.240562, accuracy: 20 };
  async function checkin(photo) {
    const c = await call('/api/checkin/challenge', { method: 'POST', body: { type: 'in' } });
    return call('/api/checkin', { method: 'POST', body: {
      type: 'in', nonce: c.data.nonce, photo,
      liveness: { challenge: c.data.challenge, passed: true, score: 0.95 },
      geo: office, deviceId: 'dev-1',
    } });
  }

  r = await checkin(dataUrl('sample1.jpg'));
  ok('отметка тем же лицом → confirmed', r.data.status === 'confirmed', `d=${r.data.similarity}`);

  r = await checkin(dataUrl(farImg));
  ok('отметка чужим лицом → pending (не засчитано)', r.data.status === 'pending', `d=${r.data.similarity} flags=${JSON.stringify(r.data.riskFlags)}`);

  // ---------- детекция дублей лица при регистрации (улучшение №4) ----------
  await call('/api/login', { method: 'POST', body: { login: 'admin', password: 'admin123' } });
  const created = await call('/api/admin/employees', { method: 'POST',
    body: { name: 'Двойник', login: 'dup' + Date.now(), password: 'dup12345', role: 'employee' } });
  const dupLogin = created.data.employee.login;
  // назначим пароль известный — уже задан при создании
  await call('/api/login', { method: 'POST', body: { login: dupLogin, password: 'dup12345' } });
  r = await call('/api/enroll', { method: 'POST', body: { photo: dataUrl('sample1.jpg'), deviceId: 'dev-2' } });
  ok('чужое уже зарегистрированное лицо → 409 (дубль)', r.status === 409, r.data?.error || '');

  // ---------- офлайн-отметка (улучшение №8) ----------
  await call('/api/login', { method: 'POST', body: { login: 'aziz', password: 'aziz123' } });
  r = await call('/api/checkin/offline', { method: 'POST', body: {
    type: 'in', photo: dataUrl('sample1.jpg'), geo: office, deviceId: 'dev-1',
    capturedAt: Date.now() - 3600_000 } });
  ok('офлайн-отметка → принята в очередь (pending, offline)', r.status === 200 && r.data.status === 'pending' && r.data.offline === true);

  console.log(`\n${failed === 0 ? '✅' : '❌'} Пройдено ${passed}, провалено ${failed}`);
} finally {
  server.kill('SIGKILL');
  try { rmSync(TEST_DATA, { recursive: true, force: true }); } catch {}
}
process.exit(failed === 0 ? 0 : 1);
