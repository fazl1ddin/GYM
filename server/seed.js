import { db } from './db.js';
import { hashPassword } from './security.js';
import { newSecret } from './qr.js';

function upsertEmployee({ name, login, password, role, workplaceId }) {
  const ex = db.prepare('SELECT id FROM employees WHERE login = ?').get(login);
  if (ex) { console.log(`= уже есть: ${login}`); return ex.id; }
  const info = db.prepare(`INSERT INTO employees (name,login,pass_hash,role,workplace_id)
    VALUES (?,?,?,?,?)`).run(name, login, hashPassword(password), role, workplaceId || null);
  console.log(`+ создан ${role}: ${login} / ${password}`);
  return info.lastInsertRowid;
}

// Рабочие места
let wpId = db.prepare('SELECT id FROM workplaces LIMIT 1').get()?.id;
if (!wpId) {
  const info = db.prepare('INSERT INTO workplaces (name,address,lat,lng,radius_m,qr_secret) VALUES (?,?,?,?,?,?)')
    .run('Главный офис', 'г. Ташкент, ул. Амира Темура 1', 41.311081, 69.240562, 150, newSecret());
  wpId = info.lastInsertRowid;
  db.prepare('INSERT INTO workplaces (name,address,lat,lng,radius_m,qr_secret) VALUES (?,?,?,?,?,?)')
    .run('Склад №1', 'г. Ташкент, Сергелийский р-н', 41.230000, 69.230000, 200, newSecret());
  console.log('+ созданы рабочие места');
}

upsertEmployee({ name: 'Администратор', login: 'admin', password: 'admin123', role: 'admin', workplaceId: wpId });
upsertEmployee({ name: 'Азиз Рахимов', login: 'aziz', password: 'aziz123', role: 'employee', workplaceId: wpId });

console.log('\nГотово. Войдите как admin / admin123 (администратор) или aziz / aziz123 (сотрудник).');
