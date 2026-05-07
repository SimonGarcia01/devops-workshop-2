FROM gradle:8.7-jdk21 AS build

WORKDIR /app

COPY . .

RUN gradle :services:circleguard-identity-service:build -x test

FROM eclipse-temurin:21-jre

WORKDIR /app

COPY --from=build /app/services/circleguard-identity-service/build/libs/*.jar app.jar

EXPOSE 8083

ENTRYPOINT ["java", "-jar", "app.jar"]