#!/bin/bash
# FaceClock — установка зависимостей для веб-сессий Claude Code.
# Ставит Node-зависимости backend (server/). Flutter-часть (app/) здесь не
# собирается: Flutter SDK в веб-окружении отсутствует, сборка мобильного
# клиента выполняется локально (см. app/README.md).
set -euo pipefail

cd "$CLAUDE_PROJECT_DIR"

# Node backend
if [ -f package.json ]; then
  echo "FaceClock: устанавливаю зависимости backend (npm install)…"
  npm install --no-audit --no-fund
fi

echo "FaceClock: окружение готово. Backend: npm start · тесты: npm test"
