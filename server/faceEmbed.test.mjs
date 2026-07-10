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
const none = await embedFromDataUrl(`data:image/jpeg;base64,${Buffer.from(blankBuf).toString('base64')}`);
ok('кадр без лица → лицо не найдено (null)', none === null);

// ---------- HTTP-путь (реальный сервер, серверный эмбеддинг включён) ----------
const PORT = 3097;
const BASE = `http://localhost:${PORT}`;
const TEST_DATA = mkdtempSync(join(tmpdir(), 'faceclock-face-'));
const env = { ...process.env, PORT: String(PORT), FACECLOCK_DATA_DIR: TEST_DATA };

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

  console.log(`\n${failed === 0 ? '✅' : '❌'} Пройдено ${passed}, провалено ${failed}`);
} finally {
  server.kill('SIGKILL');
  try { rmSync(TEST_DATA, { recursive: true, force: true }); } catch {}
}
process.exit(failed === 0 ? 0 : 1);
