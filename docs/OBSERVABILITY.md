# Observabilidad del microservicio EFA

Este documento describe cómo el proyecto EFA instrumenta su microservicio
para poder **observar** su comportamiento y **detectar anomalías** en el
entorno de desarrollo simulado, y cómo esa información se convierte en
decisiones técnicas concretas.

> **Indicador de logro cubierto:** IL3.1 / IE1 (monitoreo y logging),
> IL3.2 / IE3 (métricas clave y dashboards).

---

## 1. Arquitectura de la observabilidad

```
                        +---------------------------------------------+
                        |              Grafana  :3000                |
                        |  dashboards + alertas + exploracion de logs |
                        +----+---------------------+----------------+
                             |                     |
              Prometheus    |                     |   Loki
        (metricas, 15 s)    |                     |   (logs indexados)
                             v                     v
                    +----------------+     +-----------------+
                    |  Prometheus    |     |      Loki       |
                    |    :9090       |     |     :3100        |
                    |  TSDB + reglas |     |  indice por     |
                    |  de alerta     |     |  etiquetas      |
                    +--------+-------+     +--------+--------+
                             ^                     ^
                             | scrapea            | ingiere
              +--------------+--------------+      |
              |              |              |      |
     +--------v-------+ +----v-------+ +----v------+v----+
     |  efa-backend   | |  efa-      | |     Grafana      |
     | :8080          | |  frontend  | |      Alloy        |
     | /actuator/     | | :80        | |  (recolector)    |
     |  prometheus    | | /healthz   | |                   |
     | /actuator/     | | /nginx_    | +-------------------+
     |  health        | |  status    |
     +----------------+ +------------+

     +------------------+
     |  Pushgateway     |  <-- metricas del pipeline CI/CD
     |  :9091           |      (duracion, cobertura, estado)
     +------------------+
```

### Componentes y su función

| Componente | Función | Por qué se eligió |
|---|---|---|
| **Spring Boot Actuator + Micrometer** | Expone métricas del proceso y de la aplicación en formato Prometheus. | Es la vía estándar en el ecosistema Spring; no requiere un agente externo ni código de instrumentación para las métricas de HTTP y JVM. |
| **Prometheus** | Almacena las métricas, evalúa las reglas de alerta y expone los objetivos descubiertos. | Modelo de datos de series temporales con consultas rápidas y un lenguaje de alertas potente. |
| **Grafana** | Dashboards, exploración de logs y visualización de alertas. | Aprovisionamiento declarativo: los dashboards son archivos JSON versionados en el repositorio. |
| **Loki** | Almacena e indexa los logs por etiquetas. | Es la opción de la familia Grafana para logs; se integra con las mismas variables y el mismo origen de datos que las métricas. |
| **Grafana Alloy** | Recolecta los logs de los contenedores y de los pods y los envía a Loki. | Es el recolector soportado actualmente por Grafana (sustituye a Promtail). |
| **Pushgateway** | Recibe las métricas del pipeline CI/CD. | Las métricas de un job de CI nacen y mueren dentro de la ejecución: no existe un endpoint activo que se pueda scrapear. |
| **cAdvisor** | Métricas de CPU, memoria, red y disco de los contenedores. | Es la fuente estándar de uso de recursos, y la que alimenta las alertas de saturación. |

---

## 2. Instrumentación del microservicio

### 2.1 Métricas

Las métricas se dividen en tres familias.

**a) Métricas de framework** (automáticas, sin código propio)

Spring Boot y Micrometer exponen, entre otras:

| Métrica | Qué permite decidir |
|---|---|
| `http_server_requests_seconds_count` | Volumen de peticiones por código de estado. Detecta una regresión que aumenta los 5xx. |
| `http_server_requests_seconds_bucket` | Histograma de latencia; permite calcular p50, p90, p95 y p99. |
| `jvm_memory_used_bytes` | Consumo de memoria del proceso. |
| `jvm_gc_pause_seconds` | Pausas del recolector de basura. |
| `process_cpu_usage` | CPU consumida por el proceso. |

**b) Métricas de negocio** (definidas en el proyecto)

Definidas en `demo/src/main/java/Proyecto_EFA/demo/observability/ApplicationMetrics.java`:

| Métrica | Etiquetas | Significado |
|---|---|---|
| `efa_availability_up` | `service` | `1` si el servicio está operativo, `0` si no. Es la **disponibilidad real**, no solo el porcentaje de peticiones que el sistema alcanza a responder. |
| `efa_errors_total` | `tipo`, `endpoint` | Errores de aplicación clasificados por tipo (`http_5xx`, `http_429`) y por endpoint. Alimenta el panel «Errores registrados». |
| `efa_request_duration_seconds` | — | Duración de las peticiones de negocio, independiente de la instrumentación por defecto del contenedor. |
| `efa_deploy_info` | `version`, `commit`, `environment` | Metadatos del despliegue en ejecución. Permite confirmar, desde el panel, que la versión que corre es la esperada. |
| `efa_build_timestamp` | — | Momento de arranque del proceso. |
| `efa_business_operations_total` | `operacion` | Operaciones atendidas por la aplicación. |

**c) Etiquetas comunes**

Definidas en `application.properties` mediante `management.metrics.tags`:

```
service.name=efa-backend
service.instance=${HOSTNAME}
service.version=${APP_VERSION}
environment=${ENVIRONMENT}
team=devops-efa
commit=${GIT_COMMIT}
```

Estas etiquetas son las que permiten que Prometheus y Grafana distingan entre
entornos y entre versiones **sin cambiar una sola consulta**.

### 2.2 Logs

El logging estructurado es la parte de la observabilidad que responde
«¿por qué pasó?» cuando las métricas ya respondieron «¿qué pasó?».

**Formato.** El perfil `prod` (el que usan Docker Compose y Kubernetes)
activa el formato **ECS** nativo de Spring Boot:

```properties
logging.structured.format.console=ecs
logging.structured.ecs.service.name=${SERVICE_NAME:efa-backend}
logging.structured.ecs.service.version=${APP_VERSION:dev}
```

En los entornos de desarrollo se mantiene el formato de texto, que es más
legible para el desarrollador.

**Correlación de peticiones.** `CorrelationIdFilter` genera un identificador
único por petición (o reutiliza el que envía el cliente en la cabecera
`X-Correlation-Id`), lo escribe en el MDC —y por lo tanto en todas las líneas
de log de esa petición— y lo devuelve en la respuesta:

```json
{
  "@timestamp": "2026-11-10T21:20:57.963Z",
  "log": { "level": "WARN", "logger": "Proyecto_EFA.demo.observability.CorrelationIdFilter" },
  "service": { "name": "efa-backend", "version": "3.0.0-observability", "environment": "dev" },
  "message": "Peticion rechazada GET /producto -> 404 (7 ms)",
  "traceId": "a7640f29f48743d4ad69e787149ba1e4",
  "path": "/producto", "method": "GET", "durationMs": "7", "status": "404"
}
```

Esto resuelve el problema habitual de «el usuario reporta un error»: el
identificador de correlación permite encontrar exactamente la línea de log
que corresponde a esa petición, sin tener que buscar por fecha y hora.

**El frontend también es observable.** El access log de nginx se emite en
JSON con el mismo esquema (`nginx.conf`), de modo que los errores del
frontend se consultan en Loki con los mismos filtros que los del backend:

```json
{"@timestamp":"...","service":"efa-frontend","request_method":"GET",
 "request_uri":"/api/productos","status":404,"request_time":"0.012",
 "http_x_correlation_id":"a7640f29f48743d4ad69e787149ba1e4"}
```

### 2.3 Trazabilidad del despliegue

Cada despliegue publica sus metadatos en tres lugares distintos, de modo que
se pueda responder «¿qué versión está corriendo?» desde cualquiera de ellos:

| Ubicación | Contenido |
|---|---|
| `/actuator/info` | Versión, commit, rama, fecha de compilación y entorno. |
| Etiquetas de las métricas | `service.version` y `commit` en todas las series. |
| Campo `service` de cada log | Nombre y versión del servicio en cada línea. |
| Anotación del pod | `efa.io/commit`, `efa.io/branch`, `efa.io/build-time`. |

---

## 3. Configuración de la recolección

### 3.1 Prometheus

`infra/monitoring/prometheus/prometheus.yml` define los objetivos:

- **Job `efa-backend`**: en Docker Compose, el destino es `backend:8080`.
- **Job `efa-backend-k8s`**: en Kubernetes, usa `kubernetes_sd_configs` con
  el rol `pod` y **solo recolecta los pods que declaran**
  `prometheus.io/scrape: "true"`. El descubrimiento es declarativo: no hay
  una lista de destinos que mantener a mano.

El relabeling convierte los metadatos del pod en etiquetas útiles
(`namespace`, `pod`, `app`, `version`).

### 3.2 Loki

`infra/monitoring/loki/loki-config.yml` define la retención (30 días) y los
límites de cardinalidad. Los logs se indexan por etiquetas, nunca por
contenido: el identificador de correlación viaja **dentro** del documento
JSON como campo indexable, no como etiqueta, para no multiplicar el número
de series.

### 3.3 Alloy

`infra/monitoring/alloy/alloy-config.docker.alloy` (entorno local) y
`infra/monitoring/alloy/alloy-config.kubernetes.alloy` (cluster) descubren
los logs, los filtran por contenedor y los etiquetan con `service`,
`project` y `environment`.

> **Nota técnica:** la sintaxis de Alloy usa comentarios con `//`, no con
> `#`. Los archivos `.alloy` no son YAML.

---

## 4. Dashboards

Los dashboards están en `infra/monitoring/grafana/dashboards/` y se
aprovisionan automáticamente (`infra/monitoring/grafana/provisioning/`).

| Dashboard | UID | Para qué sirve |
|---|---|---|
| **EFA - Panorama General del Microservicio** | `efa-overview` | Disponibilidad, tasa de error, latencia por percentil, CPU, memoria, errores por endpoint y duración de las respuestas. Es el tablero de referencia: con este se decide si hay una anomalía. |
| **EFA - Pipeline CI/CD, Cobertura y Despliegue** | `efa-cicd` | Duración del despliegue, cobertura de pruebas, resultado del build, Quality Gate, duración por etapa, vulnerabilidades detectadas y estado de cada política de cumplimiento. |
| **EFA - Errores, Logs y Alertas** | `efa-errors-logs` | Errores por endpoint, tabla de errores de aplicación, logs del backend y del frontend en Loki, y estado de las alertas. Es el tablero de diagnóstico de incidentes. |

### Métricas clave exigidas por la pauta

| Métrica clave | Dónde aparece | Métrica de Prometheus |
|---|---|---|
| **Tiempo de despliegue** | Dashboard CI/CD | `efa_ci_deployment_duration_seconds` (y `efa_ci_stage_duration_seconds` por etapa) |
| **Cobertura de pruebas** | Dashboard CI/CD | `efa_ci_test_coverage_ratio` |
| **Uso de CPU** | Dashboard Panorama | `container_cpu_usage_seconds_total` |
| **Uso de memoria** | Dashboard Panorama | `container_memory_working_set_bytes` |
| **Errores registrados** | Dashboard Panorama y Errores | `efa_errors_total` y `http_server_requests_seconds_count{status="5.."}` |
| **Disponibilidad** | Dashboard Panorama | `efa_availability_up` |

---

## 5. Alertas

Las reglas están en `infra/monitoring/prometheus/rules/efa-alerts.yml` y
reproducidas en el cluster como `PrometheusRule`
(`infra/k8s/base/08-servicemonitor.yaml`).

| Alerta | Severidad | Condición | Decisión que habilita |
|---|---|---|---|
| `EfaBackendCaido` | crítica | Prometheus no logra scrapear el backend durante 2 min | Bloquear el despliegue (P-OBS-003). |
| `EfaTasaErrores5xxAlta` | crítica | > 0,1 errores 5xx/s durante 3 min | Bloquear el despliegue (P-OBS-004). |
| `EfaMemoriaEnRiesgoDeOOM` | crítica | Memoria al 95 % del límite durante 5 min | Bloquear el despliegue (P-OBS-005). |
| `EfaDespliegueFallido` | crítica | El último despliegue falló | Registrar la incidencia (P-CI-002). |
| `EfaDisponibilidadBajoSLO` | advertencia | Disponibilidad < 99 % durante 5 min | Investigar la dependencia afectada. |
| `EfaLatenciaP95Alta` | advertencia | p95 > 1,5 s durante 5 min | Revisar consultas a la base de datos. |
| `EfaCpuSaturada` | advertencia | CPU > 85 % del límite durante 10 min | Ajustar el HPA o los límites. |
| `EfaMemoriaSaturada` | advertencia | Memoria > 85 % del límite | Corregir una fuga antes de que escale a crítica. |
| `EfaCoberturaBajoUmbral` | advertencia | Cobertura < 60 % | Reforzar las pruebas de la zona afectada. |
| `EfaTiempoDespliegueExcesivo` | advertencia | Despliegue > 10 min | Optimizar la etapa lenta. |

Las tres alertas críticas llevan la etiqueta `cumplimiento` con el
identificador de la política asociada. Esa etiqueta es la que consulta el
gate de cumplimiento (`scripts/compliance/audit-alerts.sh`) para bloquear
el despliegue de forma automática.

---

## 6. Cómo la observabilidad produce decisiones

Esta es la parte central del indicador: la observabilidad no es un adorno,
es la fuente de decisiones técnicas.

| Señal observada | Decisión que se toma | Quién la ejecuta |
|---|---|---|
| `efa_ci_deployment_duration_seconds` crece entre despliegues | Se identifica la etapa lenta en `efa_ci_stage_duration_seconds` y se optimiza esa etapa concreta. | Equipo DevOps |
| `efa_ci_test_coverage_ratio` cae bajo 60 % | El gate `P-QA-002` detiene el despliegue. Se priorizan pruebas en el módulo con menor cobertura. | Pipeline |
| `efa_availability_up` pasa a 0 en una réplica | Se revisa la sonda de esa réplica; el HPA y el balanceador retiran el tráfico del pod caído. | Kubernetes + operador |
| `EfaLatenciaP95Alta` sube mientras el tráfico se mantiene | Se correlaciona con los logs de `CorrelationIdFilter`: si las peticiones que se lentifican apuntan al mismo endpoint, es la base de datos. | Equipo de desarrollo |
| `efa_errors_total{endpoint="..."}` crece | Se localiza el endpoint responsable sin revisar el total agregado, y se escribe una prueba de regresión. | Equipo de desarrollo |
| `EfaCpuSaturada` / `EfaMemoriaEnRiesgoDeOOM` | Se ajusta el HPA o se corrige la fuga antes del siguiente despliegue. | Equipo DevOps |
| `efa_deploy_info{commit=...}` no coincide con el esperado | Se detiene el despliegue: el cluster no está ejecutando la versión revisada. | Pipeline |

El **runbook** `docs/RUNBOOK.md` traduce cada una de estas señales en un
procedimiento concreto, con los comandos exactos que hay que ejecutar.

---

## 7. Puesta en marcha del entorno de desarrollo simulado

### 7.1 Stack completo (aplicación + observabilidad)

```bash
# 1. Variables de entorno mínimas
export ECR_REGISTRY=efa-local
export ECR_REPOSITORY=backend
export IMAGE_TAG=latest
export POSTGRES_PASSWORD="$(openssl rand -hex 24)"

# 2. Construir la imagen del backend
docker build -t efa-local/backend:latest .

# 3. Levantar la aplicación
docker compose -p efa up -d

# 4. Levantar el stack de observabilidad
docker compose -f infra/monitoring/docker-compose.monitoring.yml up -d
```

### 7.2 Verificación

```bash
# Salud del microservicio
curl -s http://localhost:8083/actuator/health

# Métricas en formato Prometheus
curl -s http://localhost:8083/actuator/prometheus | grep '^efa_'

# Objetivos activos de Prometheus
curl -s http://localhost:9090/api/v1/targets

# Logs estructurados del backend en Loki
curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bservice%3D%22efa-backend%22%7D&limit=5&since=15m"

# Dashboards cargados en Grafana
curl -s -u admin:efa-observability "http://localhost:3000/api/search?type=dash-db"
```

### 7.3 Puertos

| Servicio | Puerto |
|---|---|
| Backend (API) | 8083 |
| PostgreSQL | 5433 |
| Prometheus | 9090 |
| Pushgateway | 9091 |
| Grafana | 3000 (admin / efa-observability) |
| Loki | 3100 |
| Alloy | 12345 |
| cAdvisor | 8088 |

---

## 8. Trazabilidad de la configuración

| Archivo | Contenido |
|---|---|
| `infra/monitoring/prometheus/prometheus.yml` | Objetivos de scrape y relabeling. |
| `infra/monitoring/prometheus/rules/efa-alerts.yml` | Reglas de alerta. |
| `infra/monitoring/loki/loki-config.yml` | Retención, límites de cardinalidad y compactación. |
| `infra/monitoring/alloy/alloy-config.docker.alloy` | Recolección de logs en Docker Compose. |
| `infra/monitoring/alloy/alloy-config.kubernetes.alloy` | Recolección de logs en Kubernetes (DaemonSet). |
| `infra/monitoring/grafana/provisioning/` | Datasources y proveedor de dashboards. |
| `infra/monitoring/grafana/dashboards/` | Los tres dashboards (JSON versionado). |
| `infra/k8s/observability/prometheus.yml` | Configuración de Prometheus dentro del cluster. |
| `demo/src/main/java/Proyecto_EFA/demo/observability/` | Instrumentación en el código. |
| `demo/src/main/resources/application.properties` | Configuración de Actuator, Micrometer y logging. |
| `demo/src/main/resources/application-prod.properties` | Perfil de producción: ECS, cierre ordenado, Swagger desactivado. |
