// Серверная проверка живости (улучшение №1).
// Сервер НЕ доверяет заявлению клиента «живость пройдена»: он сам анализирует
// присланные кадры (ландмарки + эмоции face-api) и проверяет, что человек
// выполнил ИМЕННО запрошенное действие. Защита от фото/видео и патча приложения.

import { analyzeFrame } from './faceEmbed.js';

const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

// Eye Aspect Ratio по 6 точкам глаза (открыт ~0.3, закрыт ~0.1).
function eyeAspectRatio(pts) {
  const [p0, p1, p2, p3, p4, p5] = pts;
  const denom = 2 * dist(p0, p3);
  if (denom === 0) return 1;
  return (dist(p1, p5) + dist(p2, p4)) / denom;
}

// Средний EAR обоих глаз по 68 ландмаркам face-api (глаза: 36–41 и 42–47).
export function earFromLandmarks(lm) {
  if (!lm || lm.length < 48) return 1;
  const left = eyeAspectRatio([lm[36], lm[37], lm[38], lm[39], lm[40], lm[41]]);
  const right = eyeAspectRatio([lm[42], lm[43], lm[44], lm[45], lm[46], lm[47]]);
  return (left + right) / 2;
}

// Оценка поворота головы по горизонтали: 0.5 — анфас, <0.5 или >0.5 — поворот.
// Возвращает величину поворота [0..1] (|отклонение от анфаса| * 2).
export function turnMagnitude(lm) {
  if (!lm || lm.length < 46) return 0;
  const leftEyeOuter = lm[36];
  const rightEyeOuter = lm[45];
  const noseTip = lm[30];
  const span = rightEyeOuter[0] - leftEyeOuter[0];
  if (span === 0) return 0;
  const ratio = (noseTip[0] - leftEyeOuter[0]) / span;
  return Math.min(1, Math.abs(ratio - 0.5) * 2);
}

const OPEN_EAR = 0.24;
const CLOSED_EAR = 0.17;
const TURN_MIN = 0.35;
const SMILE_MIN = 0.7;

/// Проверяет живость по кадрам. frames — массив data-URL (1–3 кадра).
/// Возвращает { passed, score, reason }.
export async function verifyLiveness(challenge, frames) {
  if (!Array.isArray(frames) || frames.length === 0) {
    return { passed: false, score: 0, reason: 'нет кадров живости' };
  }
  const analyzed = [];
  for (const f of frames.slice(0, 3)) {
    const a = await analyzeFrame(f);
    if (a) analyzed.push(a);
  }
  if (analyzed.length === 0) return { passed: false, score: 0, reason: 'лицо на кадрах не найдено' };

  switch (challenge) {
    case 'blink': {
      const ears = analyzed.map((a) => earFromLandmarks(a.landmarks));
      const open = Math.max(...ears);
      const closed = Math.min(...ears);
      const passed = open > OPEN_EAR && closed < CLOSED_EAR;
      return { passed, score: passed ? Math.min(1, (open - closed) * 4) : 0,
        reason: passed ? null : 'моргание не подтверждено' };
    }
    case 'turn_left':
    case 'turn_right': {
      const turn = Math.max(...analyzed.map((a) => turnMagnitude(a.landmarks)));
      const passed = turn >= TURN_MIN;
      return { passed, score: passed ? Math.min(1, turn) : 0,
        reason: passed ? null : 'поворот головы не подтверждён' };
    }
    case 'smile': {
      const happy = Math.max(...analyzed.map((a) => a.expressions?.happy ?? 0));
      const passed = happy >= SMILE_MIN;
      return { passed, score: passed ? happy : 0,
        reason: passed ? null : 'улыбка не подтверждена' };
    }
    default:
      return { passed: false, score: 0, reason: 'неизвестное действие' };
  }
}
