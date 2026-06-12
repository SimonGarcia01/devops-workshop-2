# ---- BUILD STAGE ----
FROM gradle:8.7-jdk21 AS build

WORKDIR /app

COPY . .

RUN gradle :services:circleguard-form-service:build -x test

# ---- RUN STAGE ----
FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /app/services/circleguard-form-service/build/libs/*.jar app.jar

EXPOSE 8086

ENTRYPOINT ["java", "-jar", "app.jar"]
