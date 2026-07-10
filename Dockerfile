# Backend FaceClock (Node + face-api/TensorFlow).
FROM node:22-bookworm

WORKDIR /app

# зависимости отдельно — лучше кешируется
COPY package*.json ./
RUN npm ci --omit=dev

# исходники сервера (модели распознавания приходят внутри node_modules/face-api)
COPY server ./server

ENV PORT=3000 \
    FACECLOCK_SERVER_EMBED=on \
    FACECLOCK_SERVER_LIVENESS=on

EXPOSE 3000
VOLUME ["/app/data"]

# healthcheck дергает корневой эндпоинт
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||3000)+'/').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["npm", "start"]
