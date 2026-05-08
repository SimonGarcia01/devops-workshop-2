# ---- BUILD STAGE ----
FROM gradle:8.7-jdk21 AS build

WORKDIR /app

COPY . .

RUN gradle :services:circleguard-gateway-service:build -x test

# ---- RUN STAGE ----
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /app/services/circleguard-gateway-service/build/libs/*.jar app.jar

EXPOSE 8087

ENTRYPOINT ["java", "-jar", "app.jar"]