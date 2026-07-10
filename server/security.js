import crypto from 'node:crypto';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { DATA_DIR } from './db.js';

// --- Секрет для подписи сессий (генерируется один раз и хранится в data/) ---
const secretPath = join(DATA_DIR, 'secret.key');
let SECRET;
if (existsSync(secretPath)) {
  SECRET = readFileSync(secretPath);
} else {
  SECRET = crypto.randomBytes(32);
  writeFileSync(secretPath, SECRET, { mode: 0o600 });
}

// --- Политика защиты (раздел 6 ТЗ, уровень «максимум») ---
export const POLICY = {
  // Серверный эмбеддинг: сервер сам считает вектор лица из фото (не доверяет
  // вектору от клиента). Отключается через FACECLOCK_SERVER_EMBED=off.
  serverSideEmbedding: process.env.FACECLOCK_SERVER_EMBED !== 'off',
  faceMatchMaxDistance: 0.55,  // евклидово расстояние дескрипторов: меньше — совпадение
  faceMatchMinSimilarity: 0.6, // косинусное сходство (запасной клиентский путь)
  livenessMinScore: 0.6,       // минимальный балл живости
  challengeTtlMs: 60_000,      // время жизни liveness-челленджа
  requireGeo: true,            // обязательна геозона
  requireLiveness: true,       // обязательна проверка живости
  bindDevice: true,            // привязка устройства
  autoConfirmMaxRisk: 30,      // risk-score выше → ручная проверка (очередь аномалий)
  challenges: ['blink', 'turn_left', 'turn_right', 'smile'],
};

// --- Пароли: scrypt с солью ---
export function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const dk = crypto.scryptSync(password, salt, 32);
  return `scrypt$${salt.toString('hex')}$${dk.toString('hex')}`;
}

export function verifyPassword(password, stored) {
  try {
    const [scheme, saltHex, hashHex] = stored.split('$');
    if (scheme !== 'scrypt') return false;
    const dk = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), 32);
    return crypto.timingSafeEqual(dk, Buffer.from(hashHex, 'hex'));
  } catch {
    return false;
  }
}

// --- Сессии: подписанный токен в httpOnly-cookie ---
export function signSession(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  const sig = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return `${body}.${sig}`;
}

export function verifySession(token) {
  if (!token || !token.includes('.')) return null;
  const [body, sig] = token.split('.');
  const expected = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (sig.length !== expected.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(expected))) return null;
  try {
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
    if (payload.exp && Date.now() > payload.exp) return null;
    return payload;
  } catch {
    return null;
  }
}

export function randomNonce() {
  return crypto.randomBytes(18).toString('base64url');
}
