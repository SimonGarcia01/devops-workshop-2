FROM gradle:8.7-jdk21 AS build

WORKDIR /app

# Copy EVERYTHING (root project)
COPY . .

# Build ONLY auth service
RUN gradle :services:circleguard-auth-service:build -x test

# ---- RUN IMAGE ----
FROM eclipse-temurin:21-jdk-jammy

WORKDIR /app

COPY --from=build /app/services/circleguard-auth-service/build/libs/*.jar app.jar

EXPOSE 8180

ENTRYPOINT ["java", "-jar", "app.jar"]