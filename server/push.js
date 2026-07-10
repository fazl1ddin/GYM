// Push-напоминания (улучшение №7): «вы не отметили приход/уход».
// Логика «кому напомнить» — чистая функция (тестируется). Отправка — через FCM,
// если задан FCM_SERVER_KEY; иначе пишет в лог (режим разработки).

/// Кто нуждается в напоминании прямо сейчас.
/// emps: [{ id, workStartMin, normMin, todayIn, onShift }]
/// nowMin — минуты от полуночи. Возвращает [{ id, kind:'checkin'|'checkout' }].
export function whoNeedsReminder(emps, nowMin, graceMin = 15) {
  const out = [];
  for (const e of emps) {
    const start = e.workStartMin ?? 540;
    const end = start + (e.normMin ?? 480);
    if (!e.todayIn && nowMin > start + graceMin && nowMin < end) {
      out.push({ id: e.id, kind: 'checkin' });
    } else if (e.onShift && nowMin > end + graceMin) {
      out.push({ id: e.id, kind: 'checkout' });
    }
  }
  return out;
}

export const reminderText = (kind) => kind === 'checkin'
  ? { title: 'Не забыли отметиться?', body: 'Смена началась, а прихода нет. Отметьте приход.' }
  : { title: 'Отметьте уход', body: 'Смена закончилась. Не забудьте отметить уход.' };

/// Отправка одного push. Возвращает true при успехе (или в dev-логе).
export async function sendPush(token, { title, body }) {
  if (!token) return false;
  const key = process.env.FCM_SERVER_KEY;
  if (!key) {
    console.log(`[push:dev] → ${token.slice(0, 10)}… «${title}: ${body}»`);
    return true;
  }
  try {
    const res = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: { Authorization: `key=${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ to: token, notification: { title, body } }),
    });
    return res.ok;
  } catch {
    return false;
  }
}
