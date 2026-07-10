// Расчёт табеля: пары приход→уход по дням, отработанные часы, опоздания,
// переработки (улучшение №6). Чистые функции — легко тестировать.

const two = (n) => String(n).padStart(2, '0');

// 'HH:MM' → минуты от полуночи
export function parseHm(hm) {
  const [h, m] = String(hm || '09:00').split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}

function localDateKey(ms) {
  const d = new Date(ms);
  return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`;
}
function minutesOfDay(ms) {
  const d = new Date(ms);
  return d.getHours() * 60 + d.getMinutes();
}

/// events: [{ employeeId, name, type:'in'|'out', time, workStartMin, normMin }]
/// (только зачтённые отметки). Возвращает строки табеля по сотруднику и дню.
export function computeTimesheet(events) {
  // группировка по сотруднику+дню
  const groups = new Map();
  for (const e of events) {
    const key = `${e.employeeId}|${localDateKey(e.time)}`;
    if (!groups.has(key)) groups.set(key, { emp: e, list: [] });
    groups.get(key).list.push(e);
  }

  const rows = [];
  for (const { emp, list } of groups.values()) {
    list.sort((a, b) => a.time - b.time);
    let workedMin = 0;
    let openIn = null;
    let firstIn = null, lastOut = null;
    for (const ev of list) {
      if (ev.type === 'in') {
        if (openIn == null) openIn = ev.time;
        if (firstIn == null) firstIn = ev.time;
      } else if (ev.type === 'out') {
        if (openIn != null) { workedMin += Math.round((ev.time - openIn) / 60000); openIn = null; }
        lastOut = ev.time;
      }
    }
    const workStartMin = emp.workStartMin ?? parseHm('09:00');
    const normMin = emp.normMin ?? 480;
    const lateMin = firstIn != null ? Math.max(0, minutesOfDay(firstIn) - workStartMin) : 0;
    const overtimeMin = Math.max(0, workedMin - normMin);
    rows.push({
      employeeId: emp.employeeId,
      name: emp.name,
      date: localDateKey((firstIn ?? list[0].time)),
      firstIn: firstIn ? `${two(new Date(firstIn).getHours())}:${two(new Date(firstIn).getMinutes())}` : '',
      lastOut: lastOut ? `${two(new Date(lastOut).getHours())}:${two(new Date(lastOut).getMinutes())}` : '',
      workedHours: +(workedMin / 60).toFixed(2),
      lateMin,
      overtimeHours: +(overtimeMin / 60).toFixed(2),
      openShift: openIn != null, // ушёл без отметки ухода
    });
  }
  rows.sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : a.name.localeCompare(b.name)));
  return rows;
}

function csvCell(v) {
  const s = String(v ?? '');
  return /[",;\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function timesheetToCsv(rows) {
  const header = ['Сотрудник', 'Дата', 'Приход', 'Уход', 'Отработано, ч', 'Опоздание, мин', 'Переработка, ч', 'Без ухода'];
  const lines = [header.join(';')];
  for (const r of rows) {
    lines.push([r.name, r.date, r.firstIn, r.lastOut, r.workedHours, r.lateMin, r.overtimeHours, r.openShift ? 'да' : '']
      .map(csvCell).join(';'));
  }
  return '﻿' + lines.join('\n'); // BOM — чтобы Excel открыл кириллицу
}
