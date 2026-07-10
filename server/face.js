// Сравнение эмбеддингов лица.
// Эмбеддинг — вектор фиксированной длины (например, 128 или 192 чисел),
// который вычисляется на устройстве по модели (напр. MobileFaceNet).
// Сервер не доверяет вердикту клиента, а сам сравнивает вектор с эталоном.

export function isValidEmbedding(v, expectedLen) {
  if (!Array.isArray(v) || v.length < 32) return false;
  if (expectedLen && v.length !== expectedLen) return false;
  return v.every((x) => typeof x === 'number' && Number.isFinite(x));
}

export function cosineSimilarity(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return -1;
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return -1;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

// Лучшее совпадение эталона среди нескольких сохранённых шаблонов сотрудника.
export function bestSimilarity(candidate, templates) {
  let best = -1;
  for (const t of templates) {
    const s = cosineSimilarity(candidate, t);
    if (s > best) best = s;
  }
  return best;
}
