# Миграция на PostgreSQL

Сейчас backend использует встроенный **SQLite** (`node:sqlite`, синхронный API).
Для ~100 сотрудников этого достаточно с большим запасом. PostgreSQL стоит
подключать, когда появляется: несколько экземпляров сервера, высокая нагрузка,
требования к репликации/резервированию уровня БД, отчётность на больших объёмах.

## Что потребуется
1. **Драйвер и пул.** Добавить `pg`, создать пул соединений.
2. **Асинхронные запросы.** Заменить синхронные вызовы `db.prepare(...).get/all/run`
   на `await pool.query(...)`. Все обработчики маршрутов сделать `async`
   (большинство уже async). Плейсхолдеры SQLite `?` → `$1, $2, …`.
3. **Схема.** Перенести таблицы из `server/db.js` в SQL-миграции. Отличия типов:
   - `INTEGER PRIMARY KEY AUTOINCREMENT` → `BIGSERIAL PRIMARY KEY`
   - `datetime('now')` → `now()`
   - epoch-ms поля (`server_time`, …) оставить как `BIGINT`.
4. **Слой данных.** Вынести SQL в модуль-репозиторий (`server/repo/*.js`), чтобы
   маршруты не знали о конкретной БД. Это же упростит юнит-тесты.
5. **Миграции.** Инструмент вроде `node-pg-migrate` или простые `.sql` в `migrations/`.

## Инфраструктура (docker-compose)
Добавьте сервис Postgres к `docker-compose.yml`:

```yaml
  db:
    image: postgres:16
    environment:
      POSTGRES_DB: faceclock
      POSTGRES_USER: faceclock
      POSTGRES_PASSWORD: change-me
    volumes:
      - pgdata:/var/lib/postgresql/data
    restart: unless-stopped

volumes:
  pgdata:
```
И передавайте `DATABASE_URL=postgres://faceclock:change-me@db:5432/faceclock`
сервису `api`.

## Резервные копии Postgres
Вместо `npm run backup` (SQLite) использовать `pg_dump`:
```
pg_dump "$DATABASE_URL" | gzip > backups/faceclock_$(date +%F_%H%M).sql.gz
```
по cron/systemd-timer, с той же политикой хранения N последних.

## Оценка
Порт — механический, но затрагивает ~50 запросов в `server/index.js`. Рекомендую
делать отдельным этапом с прогоном полного набора тестов (`npm run test:all`)
после каждого блока. Готов выполнить по запросу.
