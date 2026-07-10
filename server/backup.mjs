// Резервное копирование БД (улучшение №11).
// Делает целостный снапшот SQLite (VACUUM INTO), хранит N последних копий.
// Запуск: npm run backup   ·   по расписанию: cron / systemd-timer (см. README).
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, readdirSync, statSync, unlinkSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = join(__dirname, '..');
const DATA_DIR = process.env.FACECLOCK_DATA_DIR || join(ROOT, 'data');
const DB = join(DATA_DIR, 'faceclock.db');
const BACKUP_DIR = process.env.FACECLOCK_BACKUP_DIR || join(ROOT, 'backups');
const KEEP = Number(process.env.FACECLOCK_BACKUP_KEEP || 14);

if (!existsSync(DB)) {
  console.error('БД не найдена:', DB, '— сначала запустите сервер/seed.');
  process.exit(1);
}
mkdirSync(BACKUP_DIR, { recursive: true });

// имя со штампом времени (без Date.now в рантайме — берём из процесса запуска)
const now = new Date();
const p = (n) => String(n).padStart(2, '0');
const stamp = `${now.getFullYear()}${p(now.getMonth() + 1)}${p(now.getDate())}_${p(now.getHours())}${p(now.getMinutes())}${p(now.getSeconds())}`;
const target = join(BACKUP_DIR, `faceclock_${stamp}.db`);

const db = new DatabaseSync(DB);
db.exec(`VACUUM INTO '${target.replace(/'/g, "''")}'`); // целостный снапшот
db.close();
console.log('Снапшот создан:', target);

// retention — оставляем KEEP последних
const files = readdirSync(BACKUP_DIR)
  .filter((f) => f.startsWith('faceclock_') && f.endsWith('.db'))
  .map((f) => ({ f, t: statSync(join(BACKUP_DIR, f)).mtimeMs }))
  .sort((a, b) => b.t - a.t);
for (const { f } of files.slice(KEEP)) {
  unlinkSync(join(BACKUP_DIR, f));
  console.log('Удалён старый бэкап:', f);
}
console.log(`Готово. Хранится копий: ${Math.min(files.length, KEEP)} (лимит ${KEEP}).`);
