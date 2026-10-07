ARG NODE_VERSION=24.12.0-alpine
ARG NGINX_VERSION=alpine3.22

FROM node:${NODE_VERSION} AS builder

ARG VITE_API_URL
ENV VITE_API_URL=${VITE_API_URL}

WORKDIR /app

COPY package.json package-lock.json ./
COPY frontend/package.json ./frontend/

RUN --mount=type=cache,target=/root/.npm,sharing=locked npm ci --workspace=frontend

COPY frontend/  ./frontend/

RUN npm run build --workspace=frontend


FROM nginxinc/nginx-unprivileged:${NGINX_VERSION} AS production


COPY frontend/nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx --from=builder /app/frontend/dist/ /usr/share/nginx/html/
USER nginx
EXPOSE 8080

ENTRYPOINT ["nginx", "-c", "/etc/nginx/nginx.conf","-g", "daemon off;"]




