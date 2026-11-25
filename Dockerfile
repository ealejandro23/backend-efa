# =============================================================================
# Dockerfile multietapa - Backend del Proyecto EFA
#
# Etapa 1: compilación con Maven y Java 21.
# Etapa de pruebas: ejecuta las pruebas unitarias dentro del contenedor.
# Etapa 2: imagen de ejecución mínima con la JRE de Temurin 21 sobre Alpine.
#
# La imagen final:
#   - No contiene el compilador ni las dependencias de construcción.
#   - Se ejecuta como un usuario sin privilegios (uid 100), no como root.
#   - Declara un HEALTHCHECK que consulta el endpoint de salud.
# =============================================================================

# --- Etapa 1: Compilacion ---------------------------------------------------
FROM maven:3.9-eclipse-temurin-26 AS builder

WORKDIR /app

# Se copian primero el pom y el codigo fuente para aproveitar la cache de
# Docker: mientras no cambien, la etapa no se reconstruye.
COPY demo/pom.xml .
COPY demo/src ./src

RUN mvn -B -ntp clean package -DskipTests

# --- Etapa de pruebas (solo con --target tester) ------------------------------
# Ejecuta las pruebas unitarias DENTRO del contenedor, con el mismo JDK y las
# mismas dependencias con que se compila la imagen. El pipeline la construye
# con:  docker build --target tester .
# Si una prueba falla, el build falla y el pipeline se detiene. Un
# "docker build" normal no pasa por esta etapa, porque la imagen final no
# depende de ella.
FROM builder AS tester
RUN mvn -B -ntp test

# --- Etapa 2: Ejecucion ------------------------------------------------------
FROM eclipse-temurin:21.0.13_9-jre-alpine-3.23

LABEL org.opencontainers.image.title="efa-backend" \
      org.opencontainers.image.description="Microservicio backend del Proyecto EFA (Spring Boot 4)" \
      org.opencontainers.image.source="https://github.com/ealejandro23/backend-efa"

WORKDIR /app

# --- Paquetes necesarios -----------------------------------------------------
# curl: lo usa el HEALTHCHECK para consultar /actuator/health.
# Se instalan antes de cambiar de usuario, porque requieren privilegios.
RUN apk add --no-cache curl

# --- Usuario sin privilegios -------------------------------------------------
# La aplicacion no necesita ser root. El uid y el gid coinciden con los
# declarados en los manifiestos de Kubernetes (runAsUser: 100,
# runAsGroup: 101), de modo que los ficheros montados por el pod mantienen
# los permisos esperados.
RUN addgroup -g 101 efa \
 && adduser -u 100 -G efa -D -H efa \
 && chown -R efa:efa /app

COPY --from=builder /app/target/*.jar app.jar
RUN chown efa:efa /app/app.jar

EXPOSE 8080

# --- Sonda de salud ----------------------------------------------------------
# El mismo endpoint que usan los healthchecks de Docker Compose y las sondas
# de Kubernetes.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl --fail --silent http://localhost:8080/actuator/health || exit 1

# La aplicacion se ejecuta sin privilegios.
USER efa

ENTRYPOINT ["sh", "-c", "java -jar app.jar --server.port=${PORT:-8080}"]
