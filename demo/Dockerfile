# =============================================================================
# Dockerfile - Backend del Proyecto EFA para Render
#
# Variante de una sola etapa sobre la imagen oficial de Temurin, pensada
# para el despliegue en Render (que compila el repositorio completo).
#
# Comparte con el Dockerfile principal las mismas garantias de seguridad:
#   - Ejecucion como usuario sin privilegios.
#   - HEALTHCHECK sobre el endpoint de salud.
#   - Imagen base fijada a una version concreta.
# =============================================================================
FROM eclipse-temurin:21-jre

LABEL org.opencontainers.image.title="efa-backend-render" \
      org.opencontainers.image.description="Microservicio backend del Proyecto EFA (despliegue en Render)" \
      org.opencontainers.image.source="https://github.com/ealejandro23/backend-efa"

WORKDIR /app

# --- Paquetes necesarios -----------------------------------------------------
# curl: lo usa el HEALTHCHECK para consultar /actuator/health.
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && rm -rf /var/lib/apt/lists/*

# --- Usuario sin privilegios -------------------------------------------------
RUN groupadd -g 101 efa \
 && useradd -u 100 -g efa -M -s /usr/sbin/nologin efa \
 && chown -R efa:efa /app

# Copiar el jar generado.
# En Render, el JAR se compila en una fase previa ("mvn clean package") y
# queda en target/. Esta imagen solo se ocupa de ejecutarlo.
COPY target/*.jar app.jar
RUN chown efa:efa /app/app.jar

# Render asigna el puerto en la variable de entorno PORT
ENV PORT=8080

EXPOSE 8080

# --- Sonda de salud ----------------------------------------------------------
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl --fail --silent http://localhost:${PORT}/actuator/health || exit 1

USER efa

ENTRYPOINT ["sh", "-c", "java -jar app.jar --server.port=$PORT"]
