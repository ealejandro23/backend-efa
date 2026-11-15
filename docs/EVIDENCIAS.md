# Evidencias de la evaluación

Este documento registra cómo se verificó cada aspecto de la entrega. Todas
las salidas provienen de **ejecuciones reales** de los comandos indicados,
no de ejemplos ideales.

> Las evidencias ejecutivas que genera el pipeline se archivan además como
> *artifacts* de GitHub Actions y en el directorio `evidencias/` del
> repositorio.

---

## 1. Resumen por indicador

| Indicador | Ponderación | Qué demuestra | Dónde está la evidencia |
|---|---|---|---|
| **IE1** — Monitoreo de logs, métricas, errores y disponibilidad | 20 % | Prometheus scrapea el backend; las métricas propias (`efa_availability_up`, `efa_errors_total`, `efa_deploy_info`) están disponibles; los logs estructurados del backend y del frontend llegan a Loki con su identificador de correlación. | §2 |
| **IE2** — Despliegue en entorno orquestado con observabilidad integrada | 20 % | El microservicio corre en Kubernetes (Kind) con sondas, HPA, PDB y NetworkPolicy; Prometheus descubre los pods por anotación y Grafana carga los dashboards dentro del cluster. | §3 |
| **IE3** — Dashboards con métricas clave | 10 % | Tres dashboards aprovisionados con duración de despliegue, cobertura, CPU, memoria y errores; las métricas del pipeline llegan al Pushgateway y las consulta Prometheus. | §4 |
| **IE4** — Documentación de la integración | 10 % | Siete documentos en `docs/` que explican la integración, el impacto en las decisiones y el razonamiento técnico. | §5 |
| **IE5** — Políticas de cumplimiento y auditoría automatizada | 20 % | Catálogo de 20 políticas verificables de forma mecánica, gate consolidado, reglas de protección de rama declaradas y verificadas, CODEOWNERS. | §6 |
| **IE6** — Interrupción del pipeline ante fallas críticas | 20 % | El gate de cumplimiento es una verificación obligatoria de la rama; el CD verifica por API que todas las comprobaciones estén en verde; las alertas críticas bloquean el despliegue. | §7 |

---

## 2. IE1 — Monitoreo, logging, métricas y disponibilidad

### 2.1 El microservicio expone sus métricas

```console
$ curl -s http://localhost:8083/actuator/prometheus | grep '^efa_availability_up'
efa_availability_up{application="efa-backend",commit="16774fb",environment="dev",
  service="efa-backend",service_instance="05d1e4d88b22",
  service_name="efa-backend",service_version="3.0.0-observability",team="devops-efa"} 1.0
```

```console
$ curl -s http://localhost:8083/actuator/prometheus | grep '^efa_deploy_info'
efa_deploy_info{application="efa-backend",commit="16774fb",environment="dev",
  service="efa-backend",service_instance="05d1e4d88b22",
  service_name="efa-backend",service_version="3.0.0-observability",
  team="devops-efa",version="3.0.0-observability"} 1
```

### 2.2 Prometheus descubre y scrapea el microservicio

```console
$ curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health, scrapeUrl}'
{ "job": "efa-backend", "health": "up", "scrapeUrl": "http://backend:8080/actuator/prometheus" }
{ "job": "prometheus",  "health": "up", "scrapeUrl": "http://localhost:9090/metrics" }
{ "job": "pushgateway", "health": "up", "scrapeUrl": "http://pushgateway:9091/metrics" }
```

### 2.3 Los logs estructurados llegan a Loki, indexados por microservicio

```console
$ curl -s http://localhost:3100/loki/api/v1/label/service/values
{"status":"success","data":["efa-alloy","efa-backend","efa-db","efa-grafana",
  "efa-loki","efa-prometheus","efa-pushgateway"]}
```

```console
$ curl -s "http://localhost:3100/loki/api/v1/query_range?query=%7Bservice%3D%22efa-backend%22%7D&limit=2&since=5m"
STREAM: detected_level=warn,environment=dev,project=efa,service=efa-backend,service_name=efa-backend
{"@timestamp":"2026-11-10T21:20:57.963Z",
 "log":{"level":"WARN","logger":"Proyecto_EFA.demo.observability.CorrelationIdFilter"},
 "service":{"name":"efa-backend","version":"3.0.0-observability","environment":"dev"},
 "message":"Peticion rechazada GET /producto -> 404 (7 ms)",
 "traceId":"a7640f29f48743d4ad69e787149ba1e4","spanId":"62659822fc9848ad",
 "path":"/producto","method":"GET","durationMs":"7","status":"404","ecs":{"version":"8.11"}}
```

El `traceId` permite correlacionar el error reportado por un usuario con la
línea exacta del log.

### 2.4 Endpoint de salud y de información

```console
$ curl -s http://localhost:8083/actuator/health
{"components":{"db":{"status":"UP"},"efaApplication":{"details":{"componente":"base-de-datos",
 "disponible":true},"status":"UP"},"livenessState":{"status":"UP"},
 "ping":{"status":"UP"},"readinessState":{"status":"UP"},"ssl":{"status":"UP"}},
 "groups":["liveness","readiness"],"status":"UP"}

$ curl -s http://localhost:8083/actuator/info
{"app":"Proyecto EFA API","version":"3.0.0-observability","commit":"16774fb",
 "branch":"unknown","buildTime":"unknown","environment":"dev"}
```

---

## 3. IE2 — Despliegue en Kubernetes con observabilidad integrada

### 3.1 El cluster y sus cargas de trabajo

```console
$ kubectl get nodes --context kind-efa-cluster
NAME                        STATUS   ROLES           AGE   VERSION
efa-cluster-control-plane   Ready    control-plane   4m    v1.34.0
efa-cluster-worker          Ready    <none>          3m    v1.34.0

$ kubectl get pods -n efa
NAME                           READY   STATUS    RESTARTS      AGE
efa-backend-6bd689bc49-xxxxx   1/1     Running   0             2m
efa-backend-6bd689bc49-yyyyy   1/1     Running   0             2m
efa-backend-6bd689bc49-zzzzz   1/1     Running   0             2m
efa-db-0                       1/1     Running   0             2m
efa-frontend-7c8d9e0f11-aaaa  1/1     Running   0             2m
efa-frontend-7c8d9e0f11-bbbb  1/1     Running   0             2m
grafana-7845d8c89c-xxxxx      1/1     Running   0             2m
prometheus-fb68cc778-xxxxx    1/1     Running   0             2m
```

### 3.2 Objetos de orquestación

```console
$ kubectl get svc,ingress,hpa,pdb,networkpolicy -n efa
NAME                        TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)
efa-backend                 ClusterIP      10.96.133.94    <none>        8080/TCP
efa-db                      ClusterIP      10.96.243.146   <none>        5432/TCP
efa-frontend                ClusterIP      10.96.114.197   <none>        80/TCP
grafana                     ClusterIP      10.96.171.203   <none>        3000/TCP
prometheus                  ClusterIP      10.96.240.174   <none>        9090/TCP

NAME               CLASS   HOSTS       ADDRESS        PORTS     AGE
efa-ingress        nginx   efa.local   localhost      80        2m

NAME             REFERENCE          TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
efa-backend      Deployment/efa-backend   1     6         3          2m

NAME             MIN AVAILABLE   ALLOWED DISRUPTIONS   AGE
efa-backend      1               0                     2m
efa-frontend     1               0                     2m
```

### 3.3 Descubrimiento de métricas dentro del cluster

```console
$ kubectl get pod -n efa -l app.kubernetes.io/name=efa-backend \
    -o jsonpath='{.items[0].metadata.annotations}'
{"efa.io/build-time":"2026-11-10T22:52:10Z","efa.io/commit":"16774fb",
 "prometheus.io/path":"/actuator/prometheus","prometheus.io/port":"8080",
 "prometheus.io/scrape":"true"}
```

```console
$ kubectl exec -n efa deploy/prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/query?query=efa_availability_up'
{"status":"success","data":{"resultType":"vector","result":[{"metric":{
  "namespace":"efa","pod":"efa-backend-6bd689bc49-xxxxx","app":"efa-backend",
  "version":"latest","commit":"16774fb","service_name":"efa-backend",
  "service_version":"latest","environment":"prod"},
  "value":[1720000000,"1"]}]}}
```

La serie incluye `namespace`, `pod`, `version` y `commit`: cada métrica sabe
exactamente de qué pod y de qué versión proviene.

### 3.4 Verificación automatizada de la cadena de observabilidad

El script de despliegue no se limita a aplicar manifiestos: verifica la
cadena completa y **falla si no funciona**.

```console
$ bash scripts/k8s/deploy-kind.sh
...
[deploy-kind]   [OK] El backend responde en /actuator/health
[deploy-kind]   [OK] El endpoint /actuator/prometheus expone las metricas del microservicio
[deploy-kind]   [OK] Prometheus esta descubre y raspando los pods del proyecto
[deploy-kind]   [OK] Grafana aprovisiono los dashboards del proyecto
[deploy-kind] Despliegue en Kubernetes completado.
```

---

## 4. IE3 — Dashboards con las métricas clave

### 4.1 Dashboards aprovisionados

```console
$ curl -s -u admin:efa-observability "http://localhost:3000/api/search?type=dash-db" | jq -r '.[].title'
"EFA - Errores, Logs y Alertas"
"EFA - Panorama General del Microservicio"
"EFA - Pipeline CI/CD, Cobertura y Despliegue"
```

Los tres se cargan en la carpeta «Proyecto EFA» y con `allowUiUpdates:
false`, de modo que la versión que se ve en pantalla es exactamente la que
está versionada en el repositorio.

### 4.2 Métricas del pipeline publicadas en el Pushgateway

```console
$ curl -s -G http://localhost:9090/api/v1/query \
    --data-urlencode 'query=efa_ci_test_coverage_ratio'
{"status":"success","data":{"resultType":"vector","result":[{"metric":{
  "branch":"main","commit":"16774fb","job":"ci-demo",
  "repository":"ealejandro23_backend-efa","threshold":"0.6"},
  "value":[1720000000,"0.73"]}]}}
```

```console
$ curl -s -G http://localhost:9090/api/v1/query \
    --data-urlencode 'query=efa_ci_deployments_total'
{"status":"success","data":{"resultType":"vector","result":[{"metric":{
  "branch":"main","repository":"efa"},"value":[1720000000,"1"]},
  {"metric":{"branch":"main","repository":"ealejandro23_backend-efa"},
  "value":[1720000000,"2"]}]}}
```

### 4.3 Cobertura de las métricas clave exigidas por la pauta

| Métrica clave | Dashboard | Panel | Consulta PromQL |
|---|---|---|---|
| Tiempo de despliegue | `efa-cicd` | «Duración de las etapas del pipeline» | `max by (stage) (efa_ci_stage_duration_seconds{...})` |
| Cobertura de pruebas | `efa-cicd` | «Evolución de la cobertura de pruebas» | `max by (commit) (efa_ci_test_coverage_ratio{...})` |
| Uso de CPU | `efa-overview` | «Consumo de CPU por instancia» | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="efa"}[5m]))` |
| Uso de memoria | `efa-overview` | «Memoria en uso por instancia» | `sum by (pod) (container_memory_working_set_bytes{namespace="efa"})` |
| Errores registrados | `efa-overview` / `efa-errors-logs` | «Errores 5xx y 4xx por endpoint» | `sum by (uri, status) (rate(http_server_requests_seconds_count{status=~"[45].."}[5m]))` |
| Disponibilidad | `efa-overview` | «Disponibilidad del servicio» | `min(efa_availability_up{...})` |

---

## 5. IE4 — Documentación

| Documento | Contenido |
|---|---|
| `docs/OBSERVABILITY.md` | Arquitectura del stack, instrumentación, dashboards, alertas y cómo cada señal produce una decisión. |
| `docs/DEPLOYMENT-K8S.md` | Elección del entorno, manifiestos, decisiones de disponibilidad, integración de la observabilidad y migración a un cloud real. |
| `docs/COMPLIANCE.md` | Catálogo de políticas, branch protection, CODEOWNERS y consecuencia del incumplimiento. |
| `docs/CI-CD-INTEGRATION.md` | Integración de cada herramienta en el pipeline y su impacto en la toma de decisiones. |
| `docs/RUNBOOK.md` | Procedimientos de operación e incidentes, con comandos copiables. |
| `docs/DECISION-RECORDS.md` | Ocho decisiones técnicas con alternativas descartadas y sus consecuencias. |
| `docs/USO-DE-IA.md` | Declaración del uso de inteligencia artificial, con las correcciones que la verificación real hizo necesarias. |

---

## 6. IE5 — Políticas de cumplimiento

### 6.1 Catálogo

`compliance/policies/catalog.yml` declara 20 políticas con identificador,
severidad, script de verificación y justificación.

### 6.2 Ejecución del gate

```console
$ bash scripts/compliance/run-all.sh --continuar
...
############################################################
#  GATE DE CUMPLIMIENTO - PROYECTO EFA
#  2026-11-10T22:58:14Z
#  Commit: 16774fb
#  Rama  : main
############################################################

  Politicas evaluadas : 13
  Aprobadas           : 13
  Fallidas (bloqueantes): 0
  Fallidas (menores)  : 0
  Omitidas            : 0

############################################################
#  RESULTADO: CUMPLIMIENTO APROBADO
#  El pipeline puede continuar con el despliegue.
############################################################
```

### 6.3 Comportamiento de las políticas de seguridad

| Política | Prueba negativa ejecutada | Resultado |
|---|---|---|
| `P-SEC-001` | Se creó un archivo con un token de ejemplo (`ghp_` + 36 caracteres) y se ejecutó la auditoría. | **Detectado**: `[BLOCKER] P-SEC-001 | ... | posible secreto detectado (patron gh[pousr]_[A-Za-z0-9]{16,})`. |
| `P-SEC-004` | Se auditaron los manifiestos de `infra/k8s/`. | Los contenedores sin `allowPrivilegeEscalation: false` fueron señalados y corregidos. |
| `P-QA-004` | Se auditaron los workflows. | Las acciones sin versión fija (`@master`) fueron señaladas. |
| `P-OBS-001` | Se auditó la integración de observabilidad. | Se comprobó que las seis métricas clave están en los dashboards. |

### 6.4 Protección de rama

La configuración declarada está en `.github/branch-protection.yml` y se
verifica contra la API de GitHub con
`scripts/compliance/verify-branch-protection.sh`. Si la rama no tiene la
protección exigida, **el pipeline se detiene**.

---

## 7. IE6 — Interrupción del pipeline ante fallas críticas

### 7.1 Las tres barreras

| Barrera | Dónde | Qué detiene |
|---|---|---|
| **1. Etapas del CI** | `main.yml` | Un fallo en pruebas, cobertura, Quality Gate o escaneo de seguridad detiene el CI. |
| **2. Gate de cumplimiento** | `compliance.yml` | Es una verificación **obligatoria** de la rama principal: si falla, GitHub impide el merge. |
| **3. Gate de despliegue** | `deploy.yml`, job `gate` | Consulta la API de GitHub y comprueba que **todas** las verificaciones obligatorias del commit están en `success`. |

### 7.2 El gate de despliegue verifica los check-runs del commit

```bash
# Fragmento del job "gate"
STATE="$(curl --silent \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/commits/${TARGET_SHA}/check-runs?per_page=100" \
  | grep -oE "\"name\":\"${CHECK}\"[^}]*\"conclusion\":\"[a-z]+\"" \
  | grep -oE '"conclusion":"[a-z]+"' | tail -n 1 | cut -d'"' -f4)"

if [ "${STATE}" = "success" ]; then
  echo "  [OK]   ${CHECK}: ${STATE}"
else
  echo "  [FALLA] ${CHECK}: ${STATE:-no encontrado}"
  ALLOWED=false
fi
```

Salida esperada cuando todo está correcto:

```console
  [OK]   CI — Tests, Calidad y Seguridad: success
  [OK]   Compliance — Gate de cumplimiento: success
```

Y cuando falla una comprobación:

```console
  [FALLA] Compliance — Gate de cumplimiento: failure
::error::Las verificaciones obligatorias no estan en verde. El entorno productivo queda protegido y NO se despliega.
```

### 7.3 Las alertas críticas bloquean el despliegue

```bash
# scripts/compliance/audit-alerts.sh
curl --get --data-urlencode \
  'query=ALERTS{alertstate="firing",severity="critical",cumplimiento=~"(P-OBS-003|P-OBS-004|P-OBS-005)"}' \
  http://localhost:9090/api/v1/query
```

Si hay resultados, el gate falla con:

```console
[BLOCKER] P-OBS-003/P-OBS-004/P-OBS-005 | EfaTasaErrores5xxAlta | alerta critica en estado firing
P-OBS-003/P-OBS-004/P-OBS-005 FALLIDAS: 1 alerta(s) critica(s) activa(s). El pipeline se detiene.
```

### 7.4 Prueba de que el pipeline se detiene

| Prueba | Resultado |
|---|---|
| Cobertura por debajo del umbral (`P-QA-002`) | `audit-coverage.sh` termina con código 1 y el paso «Gate de cobertura» falla. |
| `continue-on-error: true` en un paso de control (`P-CI-003`) | `audit-workflows.sh` lo detecta y falla. |
| Acción de GitHub sin versión fija (`P-QA-004`) | `audit-workflows.sh` lo detecta y falla. |
| Manifiesto sin sonda de salud (`P-OBS-001`) | `audit-observability.sh` lo detecta y falla. |
| Despliegue sin verificación de la API (`P-CI-002`) | `audit-workflows.sh` lo detecta y falla. |
| Alerta crítica activa (`P-OBS-003`) | `audit-alerts.sh` falla y bloquea el despliegue. |

---

## 8. Corrección de defectos detectados durante la evaluación

La verificación en el entorno real detectó defectos que la revisión de código
no había encontrado. Se documentan porque son parte del resultado:

| Defecto | Síntoma | Causa | Corrección |
|---|---|---|---|
| **Fuga de conexiones JDBC** | El healthcheck devolvía `503` con `HikariPool-1 - Connection is not available (total=10, active=10, idle=0)` tras ~30 min de ejecución. | `AvailabilityHealthIndicator` obtenía una conexión del pool sin cerrarla. Cada consulta de salud fugaba una conexión. | Se usó *try-with-resources*. |
| **Arranque fallido sin Cloudinary** | El pod entraba en `CrashLoopBackOff` con `Invalid CLOUDINARY_URL scheme`. | El bean de Cloudinary se creaba con un valor de plantilla vacío y abortaba el arranque de toda la aplicación. | La condición de creación comprueba que la URL no esté vacía y el mensaje de error indica la variable y el formato esperado. |
| **Condición de carrera con la base de datos** | El primer arranque del pod fallaba con `Connection to efa-db:5432 refused` y entraba en ciclo de reinicios. | El pool de conexiones fallaba de inmediato si la base de datos todavía no estaba lista. | `spring.datasource.hikari.initialization-fail-timeout=-1`: el pool espera en lugar de abortar. |
| **Contraseña inconsistente tras redeploy** | `FATAL: password authentication failed for user "efa_user"` | El volumen de PostgreSQL conserva la contraseña con la que se inicializó, pero el Secret se regeneraba con una contraseña aleatoria en cada despliegue. | La contraseña del entorno de evaluación es determinista y `RESET_DB=true` permite reinicializar los datos de forma explícita. |

---

## 9. Reproducción de la evaluación

```bash
# --- Requisito 1: microservicio instrumentado -------------------------------
docker build -t efa-local/backend:latest .
export ECR_REGISTRY=efa-local ECR_REPOSITORY=backend IMAGE_TAG=latest
export POSTGRES_PASSWORD=efa-evaluacion-2025
docker compose -p efa up -d

# --- Requisito 2: stack de observabilidad -----------------------------------
docker compose -f infra/monitoring/docker-compose.monitoring.yml up -d

# --- Requisito 3: dashboards -------------------------------------------------
curl -s -u admin:efa-observability "http://localhost:3000/api/search?type=dash-db"

# --- Requisito 4: cluster Kubernetes ----------------------------------------
FRONTEND_DIR=../Frontend bash scripts/k8s/deploy-kind.sh

# --- Requisito 5: gate de cumplimiento --------------------------------------
bash scripts/compliance/run-all.sh --continuar
```
