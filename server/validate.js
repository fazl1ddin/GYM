// Лёгкая валидация тел запросов (улучшение №13) — без внешних зависимостей.

/// Проверяет body по правилам. rules: { field: { type, required, min, max, enum } }
/// Возвращает { ok, error }.
export function checkBody(body, rules) {
  const b = body || {};
  for (const [field, r] of Object.entries(rules)) {
    const v = b[field];
    const present = v !== undefined && v !== null && v !== '';
    if (r.required && !present) return { ok: false, error: `Поле «${field}» обязательно` };
    if (!present) continue;
    if (r.type === 'string') {
      if (typeof v !== 'string') return { ok: false, error: `«${field}» должно быть строкой` };
      if (r.min && v.trim().length < r.min) return { ok: false, error: `«${field}»: минимум ${r.min} символов` };
      if (r.max && v.length > r.max) return { ok: false, error: `«${field}»: максимум ${r.max} символов` };
    }
    if (r.type === 'number') {
      const n = Number(v);
      if (!Number.isFinite(n)) return { ok: false, error: `«${field}» должно быть числом` };
      if (r.min != null && n < r.min) return { ok: false, error: `«${field}»: не меньше ${r.min}` };
      if (r.max != null && n > r.max) return { ok: false, error: `«${field}»: не больше ${r.max}` };
    }
    if (r.enum && !r.enum.includes(v)) return { ok: false, error: `«${field}»: недопустимое значение` };
  }
  return { ok: true };
}

/// Express-middleware из правил.
export function validate(rules) {
  return (req, res, next) => {
    const { ok, error } = checkBody(req.body, rules);
    if (!ok) return res.status(400).json({ error });
    next();
  };
}
