import { DatabaseSync } from 'node:sqlite';
import { mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
export const ROOT = join(__dirname, '..');
// Папку данных можно переопределить (напр. для изолированных тестов).
export const DATA_DIR = process.env.FACECLOCK_DATA_DIR || join(ROOT, 'data');
export const PHOTOS_DIR = join(DATA_DIR, 'photos');

mkdirSync(PHOTOS_DIR, { recursive: true });

export const db = new DatabaseSync(join(DATA_DIR, 'faceclock.db'));
db.exec('PRAGMA journal_mode = WAL;');
db.exec('PRAGMA foreign_keys = ON;');

db.exec(`
CREATE TABLE IF NOT EXISTS employees (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  login       TEXT NOT NULL UNIQUE,
  pass_hash   TEXT NOT NULL,
  role        TEXT NOT NULL DEFAULT 'employee',   -- 'employee' | 'admin'
  workplace_id INTEGER REFERENCES workplaces(id) ON DELETE SET NULL,
  active      INTEGER NOT NULL DEFAULT 1,
  device_id   TEXT,                                -- привязка устройства
  enrolled    INTEGER NOT NULL DEFAULT 0,          -- зарегистрировано ли лицо
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS workplaces (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  address     TEXT,
  lat         REAL,
  lng         REAL,
  radius_m    INTEGER NOT NULL DEFAULT 150,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS face_templates (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  descriptor  TEXT NOT NULL,                       -- JSON: массив 128 чисел
  photo_ref   TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS challenges (
  nonce       TEXT PRIMARY KEY,
  employee_id INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  challenge   TEXT NOT NULL,                       -- 'blink' | 'turn_left' | 'turn_right' | 'smile'
  kind        TEXT NOT NULL,                       -- 'in' | 'out'
  expires_at  INTEGER NOT NULL,                    -- epoch ms (серверное время)
  used        INTEGER NOT NULL DEFAULT 0,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS attendance (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id   INTEGER NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  type          TEXT NOT NULL,                     -- 'in' | 'out'
  server_time   INTEGER NOT NULL,                  -- epoch ms, время сервера
  geo_lat       REAL,
  geo_lng       REAL,
  geo_accuracy  REAL,
  distance_m    REAL,                              -- расстояние до рабочего места
  workplace_id  INTEGER REFERENCES workplaces(id) ON DELETE SET NULL,
  match_distance REAL,                             -- евклидово расстояние дескрипторов
  liveness_score REAL,
  liveness_challenge TEXT,
  risk_score    INTEGER NOT NULL DEFAULT 0,
  risk_flags    TEXT,                              -- JSON массив причин
  status        TEXT NOT NULL,                     -- 'confirmed' | 'pending' | 'rejected'
  photo_ref     TEXT,
  device_id     TEXT,
  decided_by    INTEGER REFERENCES employees(id) ON DELETE SET NULL,
  decision_comment TEXT,
  decided_at    INTEGER
);

CREATE INDEX IF NOT EXISTS idx_att_emp ON attendance(employee_id, server_time);
CREATE INDEX IF NOT EXISTS idx_att_status ON attendance(status);
`);

// --- идемпотентные миграции для уже существующих БД ---
function addColumn(table, def) {
  try { db.exec(`ALTER TABLE ${table} ADD COLUMN ${def}`); } catch { /* уже есть */ }
}
addColumn('workplaces', 'qr_secret TEXT');    // секрет для динамического QR (улучшение №3)
addColumn('workplaces', 'require_qr INTEGER NOT NULL DEFAULT 0'); // требовать QR на этом месте
addColumn('attendance', 'qr_ok INTEGER');     // прошёл ли QR-код при отметке
