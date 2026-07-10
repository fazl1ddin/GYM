// Юнит-тесты чистых функций (улучшение №13). Без сервера и БД — быстро.
// Запуск: npm run test:unit
import { haversineMeters, checkGeozone } from './geo.js';
import { cosineSimilarity, euclideanDistance, isValidEmbedding } from './face.js';
import { scoreRisk } from './risk.js';
import { parseHm, computeTimesheet } from './timesheet.js';
import { checkBody } from './validate.js';
import { currentCode, validateCode, parsePayload } from './qr.js';
import { earFromLandmarks, turnMagnitude } from './liveness.js';

let passed = 0, failed = 0;
const ok = (n, c, e = '') => { console.log(`${c ? '✅' : '❌'} ${n}${e ? '  ' + e : ''}`); c ? passed++ : failed++; };
const near = (a, b, eps = 0.02) => Math.abs(a - b) < eps;

// --- geo ---
ok('гаверсинус: 0 м для одной точки', haversineMeters(41.31, 69.24, 41.31, 69.24) === 0);
const d = haversineMeters(41.311081, 69.240562, 41.312081, 69.240562); // ~111 м на 0.001° широты
ok('гаверсинус: ~111 м на 0.001° широты', d > 100 && d < 125, `${d.toFixed(1)} м`);
ok('геозона: внутри радиуса', checkGeozone({ lat: 41.31, lng: 69.24, radius_m: 150 }, 41.3105, 69.24).inside);
ok('геозона: снаружи радиуса', !checkGeozone({ lat: 41.31, lng: 69.24, radius_m: 50 }, 41.32, 69.25).inside);
ok('геозона: нет координат места', checkGeozone({ lat: null, lng: null, radius_m: 100 }, 41.3, 69.2).inside === false);

// --- face ---
ok('косинус: идентичные = 1', near(cosineSimilarity([1, 0, 0], [1, 0, 0]), 1));
ok('косинус: ортогональные = 0', near(cosineSimilarity([1, 0], [0, 1]), 0));
ok('евклид: одинаковые = 0', euclideanDistance([1, 2, 3], [1, 2, 3]) === 0);
ok('евклид: (0,0)-(3,4) = 5', euclideanDistance([0, 0], [3, 4]) === 5);
ok('эмбеддинг: валиден (128 чисел)', isValidEmbedding(Array(128).fill(0.1)));
ok('эмбеддинг: невалиден (короткий)', !isValidEmbedding([1, 2, 3]));
ok('эмбеддинг: невалиден (NaN)', !isValidEmbedding(Array(128).fill(NaN)));

// --- risk ---
let r = scoreRisk({ geo: { inside: true, distance: 10 }, workplace: { radius_m: 150 }, faceMatched: true, liveness: 0.9, minLiveness: 0.6 });
ok('риск: всё ок → 0', r.score === 0, JSON.stringify(r.flags));
r = scoreRisk({ geo: { inside: false, distance: 500 }, workplace: { radius_m: 150 }, faceMatched: true, liveness: 0.9, minLiveness: 0.6 });
ok('риск: вне геозоны → повышен', r.score >= 40 && r.flags.some((f) => f.includes('геозон')));
r = scoreRisk({ geo: { inside: true }, faceMatched: false, liveness: 0.9, minLiveness: 0.6 });
ok('риск: лицо не совпало → +50', r.score >= 50 && r.flags.some((f) => f.includes('совпал')));
r = scoreRisk({ geo: { inside: true }, faceMatched: true, deviceMismatch: true, liveness: 0.9, minLiveness: 0.6 });
ok('риск: другое устройство → pending-порог', r.score >= 35);

// --- timesheet ---
ok('parseHm 09:30 → 570', parseHm('09:30') === 570);
const day = new Date(2026, 0, 15).getTime();
const at = (h, m) => day + (h * 60 + m) * 60000;
const ts = computeTimesheet([
  { employeeId: 1, name: 'A', type: 'in', time: at(9, 15), workStartMin: 540, normMin: 480 },
  { employeeId: 1, name: 'A', type: 'out', time: at(13, 0), workStartMin: 540, normMin: 480 },
  { employeeId: 1, name: 'A', type: 'in', time: at(14, 0), workStartMin: 540, normMin: 480 },
  { employeeId: 1, name: 'A', type: 'out', time: at(18, 0), workStartMin: 540, normMin: 480 },
]);
ok('табель: две сессии = 7.75 ч', near(ts[0].workedHours, 7.75, 0.01), `${ts[0].workedHours}`);
ok('табель: опоздание 15 мин', ts[0].lateMin === 15);

// --- validate ---
ok('валидация: обязательное поле', checkBody({}, { name: { type: 'string', required: true } }).ok === false);
ok('валидация: короткий пароль', checkBody({ p: '123' }, { p: { type: 'string', min: 6 } }).ok === false);
ok('валидация: enum', checkBody({ role: 'x' }, { role: { type: 'string', enum: ['a', 'b'] } }).ok === false);
ok('валидация: ок', checkBody({ name: 'Иван' }, { name: { type: 'string', required: true, min: 2 } }).ok === true);

// --- qr ---
const secret = 'abc123secret';
const { code } = currentCode(secret, 1_000_000_000);
ok('qr: код валиден в своём окне', validateCode(secret, code, 1_000_000_000));
ok('qr: payload парсится', parsePayload('FCLK:5:AbCdEf1234')?.workplaceId === 5);
ok('qr: мусор не парсится', parsePayload('hello') === null);

// --- liveness helpers ---
const lm = Array.from({ length: 68 }, () => [0, 0]);
[[36, 0, 0], [39, 10, 0], [37, 3, -3], [38, 7, -3], [41, 3, 3], [40, 7, 3],
 [42, 0, 0], [45, 10, 0], [43, 3, -3], [44, 7, -3], [47, 3, 3], [46, 7, 3]]
  .forEach(([i, x, y]) => (lm[i] = [x, y]));
ok('liveness: EAR открытых глаз > 0.3', earFromLandmarks(lm) > 0.3);
const front = Array.from({ length: 68 }, () => [0, 0]);
front[36] = [0, 0]; front[45] = [10, 0]; front[30] = [5, 0];
ok('liveness: анфас поворот ≈ 0', turnMagnitude(front) < 0.15);

console.log(`\n${failed === 0 ? '✅' : '❌'} Юнит: пройдено ${passed}, провалено ${failed}`);
process.exit(failed === 0 ? 0 : 1);
