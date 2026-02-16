# Build stage: compile TypeScript
FROM node:24-alpine3.23 AS build
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm ci
COPY src/ src/
COPY tsconfig.json ./
RUN npx tsc

# Production stage: run compiled JavaScript
FROM node:24-alpine3.23
WORKDIR /usr/src/app
RUN apk --no-cache add curl
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /usr/src/app/dist/ dist/
COPY default_python_home/ default_python_home/
RUN mkdir -p pyodide_cache
EXPOSE 8080
ENV NODE_ENV=production
ENV ENV_RUN_AS=docker
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
  CMD curl -m 10 -f http://localhost:8080/health || kill 1
ENTRYPOINT ["node", "dist/index.js"]
