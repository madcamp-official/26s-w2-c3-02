FROM node:20-alpine

WORKDIR /app

COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev

COPY server/src ./server/src
COPY web ./web

ENV PORT=8080
ENV PUBLIC_DIR=/app/web

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -qO- http://localhost:8080/healthz || exit 1

CMD ["node", "server/src/index.js"]
