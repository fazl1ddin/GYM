// Динамический QR на проходной (улучшение №3).
// На рабочем месте стоит экран-терминал, показывающий QR-код, который меняется
// каждые N секунд. Код = HMAC(секрет_места, окно_времени) — предсказать нельзя.
// Сотрудник сканирует свежий код при отметке → доказывает, что физически на месте.

import crypto from 'node:crypto';

export const QR_WINDOW_MS = 30_000; // код живёт 30 секунд

function codeForWindow(secret, windowIndex) {
  return crypto.createHmac('sha256', secret)
    .update(String(windowIndex))
    .digest('base64url')
    .slice(0, 10);
}

// Текущий код терминала для показа на экране места.
export function currentCode(secret, now = Date.now()) {
  const w = Math.floor(now / QR_WINDOW_MS);
  return { code: codeForWindow(secret, w), secondsLeft: Math.ceil((QR_WINDOW_MS - (now % QR_WINDOW_MS)) / 1000) };
}

// Полезная нагрузка QR: код + id места (сотрудник сканирует это).
export function qrPayload(workplaceId, secret, now = Date.now()) {
  return `FCLK:${workplaceId}:${currentCode(secret, now).code}`;
}

// Проверка присланного кода: принимаем текущее и предыдущее окно (учёт задержки).
export function validateCode(secret, code, now = Date.now()) {
  if (!code) return false;
  const w = Math.floor(now / QR_WINDOW_MS);
  return code === codeForWindow(secret, w) || code === codeForWindow(secret, w - 1);
}

// Разбор payload из QR: 'FCLK:<workplaceId>:<code>' → { workplaceId, code }.
export function parsePayload(payload) {
  const m = typeof payload === 'string' && payload.match(/^FCLK:(\d+):([A-Za-z0-9_-]{6,16})$/);
  return m ? { workplaceId: Number(m[1]), code: m[2] } : null;
}

export function newSecret() {
  return crypto.randomBytes(24).toString('hex');
}
