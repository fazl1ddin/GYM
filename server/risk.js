// Скоринг риска отметки (раздел 6 ТЗ, уровень 4).
// Чем выше балл — тем подозрительнее. Выше порога → ручная проверка (аномалия).

export function scoreRisk(ctx) {
  const flags = [];
  let score = 0;

  // Вне геозоны / нет геолокации
  if (ctx.geo?.reason === 'no_location') { score += 40; flags.push('нет геолокации'); }
  else if (ctx.geo && !ctx.geo.inside) {
    score += 40;
    flags.push(`вне геозоны (${Math.round(ctx.geo.distance)} м)`);
  } else if (ctx.geo?.distance != null && ctx.geo.distance > ctx.workplace?.radius_m * 0.8) {
    score += 10; flags.push('у границы геозоны');
  }

  // Низкая точность GPS — возможна подмена
  if (ctx.accuracy != null && ctx.accuracy > 100) { score += 10; flags.push('низкая точность GPS'); }

  // Совпадение лица (matched — прошло порог, weak — у границы порога)
  if (ctx.faceMatched === false) { score += 50; flags.push('лицо не совпало'); }
  else if (ctx.faceWeak) { score += 15; flags.push('слабое совпадение лица'); }

  // Низкая живость
  if (ctx.liveness != null && ctx.liveness < ctx.minLiveness) {
    score += 30; flags.push('низкий балл живости');
  }

  // Чужое/новое устройство
  if (ctx.deviceMismatch) { score += 35; flags.push('другое устройство'); }
  if (ctx.deviceNew) { score += 10; flags.push('новое устройство'); }

  // Root/эмулятор/mock (флаг от клиента, дополнительно проверяется)
  if (ctx.clientFlags?.mockLocation) { score += 50; flags.push('подмена геопозиции'); }
  if (ctx.clientFlags?.rooted) { score += 20; flags.push('root/jailbreak'); }
  if (ctx.clientFlags?.emulator) { score += 20; flags.push('эмулятор'); }

  return { score: Math.min(score, 100), flags };
}
