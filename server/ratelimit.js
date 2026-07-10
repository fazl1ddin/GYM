// Защита от перебора паролей и злоупотреблений (улучшение №5).
// Хранилище в памяти — для прототипа достаточно; в продакшене вынести в Redis.

const LOGIN_MAX_FAILS = 5;         // попыток до блокировки
const LOGIN_LOCK_MS = 15 * 60_000; // блокировка на 15 минут
const loginFails = new Map();      // ключ (login|ip) → { count, until }

function key(login, ip) {
  return `${String(login).toLowerCase()}|${ip}`;
}

export function isLocked(login, ip, now = Date.now()) {
  const e = loginFails.get(key(login, ip));
  if (!e) return false;
  if (e.until && now < e.until) return true;
  if (e.until && now >= e.until) { loginFails.delete(key(login, ip)); return false; }
  return false;
}

export function lockRemainingSec(login, ip, now = Date.now()) {
  const e = loginFails.get(key(login, ip));
  return e?.until ? Math.max(0, Math.ceil((e.until - now) / 1000)) : 0;
}

export function registerFail(login, ip, now = Date.now()) {
  const k = key(login, ip);
  const e = loginFails.get(k) || { count: 0, until: 0 };
  e.count += 1;
  if (e.count >= LOGIN_MAX_FAILS) e.until = now + LOGIN_LOCK_MS;
  loginFails.set(k, e);
}

export function registerSuccess(login, ip) {
  loginFails.delete(key(login, ip));
}

// Простой лимитер запросов по IP (скользящее окно).
export function makeRateLimiter({ windowMs = 60_000, max = 60 } = {}) {
  const hits = new Map(); // ip → number[] (времена)
  return (req, res, next) => {
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    const now = Date.now();
    const arr = (hits.get(ip) || []).filter((t) => now - t < windowMs);
    arr.push(now);
    hits.set(ip, arr);
    if (arr.length > max) return res.status(429).json({ error: 'Слишком много запросов, попробуйте позже' });
    next();
  };
}

// Базовые security-заголовки (лёгкий аналог helmet).
export function securityHeaders(req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('X-Frame-Options', 'DENY');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('X-XSS-Protection', '0');
  next();
}
