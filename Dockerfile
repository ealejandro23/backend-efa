# Etapa 1: Compilacion con Maven y Java 21
FROM maven:3.9.9-eclipse-temurin-21 AS builder

WORKDIR /app

COPY demo/pom.xml .
COPY demo/src ./src

RUN mvn -B -ntp clean package -DskipTests

# Etapa 2: Ejecucion con Java 21 y Alpine
FROM eclipse-temurin:25-jre-alpine

WORKDIR /app

# Curl para el healthcheck de Docker Compose
RUN apk add --no-cache curl

COPY --from=builder /app/target/*.jar app.jar

EXPOSE 8080

ENTRYPOINT ["sh", "-c", "java -jar app.jar --server.port=${PORT:-8080}"]