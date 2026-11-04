# --- build ---
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
RUN npx ng build --configuration production

# --- run ---
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist/chat-frontend /usr/share/nginx/html
COPY docker-entrypoint.sh /docker-entrypoint.d/40-config.sh
RUN sed -i 's/\r$//' /docker-entrypoint.d/40-config.sh \
    && chmod +x /docker-entrypoint.d/40-config.sh
ENV API_URL=http://localhost:8080/api
EXPOSE 80
