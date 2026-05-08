# ---- BUILD STAGE ----
FROM node:20-alpine AS build

WORKDIR /app

COPY mobile/package*.json ./

RUN npm install

COPY mobile/ .

RUN npm run build:web

# ---- RUN STAGE ----
FROM nginx:alpine

COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80