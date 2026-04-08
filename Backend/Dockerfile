FROM node:22-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8080

COPY package.json ./
COPY package-lock.json ./
RUN npm ci --omit=dev

COPY schema.sql ./
COPY schema.postgres.sql ./
COPY src ./src
COPY scripts ./scripts

EXPOSE 8080

CMD ["node", "src/server.mjs"]
