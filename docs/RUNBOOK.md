# Runbook de operación

Procedimientos concretos para responder a las señales que emite el stack de
observabilidad. Cada sección parte de una alerta concreta e indica qué
mirar, qué significa y qué hacer.

> **Uso previsto:** este documento se consulta **durante** un incidente, no
> antes. Por eso los comandos están copiables tal cual y las decisiones
> están ordenadas por prioridad.

---

## Convenciones

```bash
# Contexto del cluster de evaluacion
export KUBECTL="kubectl --context kind-efa-cluster"

# Stack local (Docker Compose)
export PROMETHEUS_URL="http://localhost:9090"
export GRAFANA_URL="http://localhost:3000"
export LOKI_URL="http://localhost:3100"
export BACKEND_URL="http://localhost:8083"
```

Las credenciales de Grafana en el entorno de evaluación son
`admin` / `efa-observability`.

---

## efa-backend-caido

**Alerta:** `EfaBackendCaido` (crítica, P-OBS-003).
**Significado:** Prometheus no logra obtener métricas del backend durante más
de 2 minutos. O el servicio está caído, o el pathway entre Prometheus y el
pod está roto.

### 1. ¿El servicio responde?

```bash
$KUBECTL get pods -n efa -l app.kubernetes.io/name=efa-backend
$KUBECTL exec -n efa deploy/efa-backend -- \
  wget -qO- http://localhost:8080/actuator/health
```

### 2. Si el pod no está `Running`

```bash
$KUBECTL describe pod -n efa -l app.kubernetes.io/name=efa-backend | tail -30
$KUBECTL logs -n efa -l app.kubernetes.io/name=efa-backend --tail=100
```

Causas frecuentes:

| Síntoma en los logs | Causa probable | Acción |
|---|---|---|
| `Failed to obtain JDBC Connection` | PostgreSQL no está listo o la credencial es incorrecta. | Verificar el Secret y el estado del StatefulSet `efa-db`. |
| `UnsatisfiedLinkError` / `Connection refused` | El pod intenta arrancar antes que la base de datos. | El `startupProbe` debería cubrirlo; revisar su `initialDelaySeconds`. |
| `OutOfMemoryError` | Fuga de memoria; ver `efa-memoria-en-riesgo-de-oom`. | Reducir la carga o corregir la fuga antes de reiniciar. |

### 3. Si el pod está `Running` pero Prometheus no lo scrapea

```bash
$KUBECTL get pod -n efa -l app.kubernetes.io/name=efa-backend \
  -o jsonpath='{.items[0].metadata.annotations}'
```

Debe aparecer `prometheus.io/scrape: "true"`. Si falta, el manifiesto se
aplicó incompleto: reaplicar con `kubectl apply -k infra/k8s/overlays/prod`.

```bash
# Estado del descubrimiento en Prometheus
curl -s "${PROMETHEUS_URL}/api/v1/targets" | jq '.data.activeTargets[] | {job: .labels.job, health, lastError}'
```

### 4. Restablecer el servicio

```bash
$KUBECTL rollout restart deployment/efa-backend -n efa
$KUBECTL rollout status deployment/efa-backend -n efa --timeout=300s
```

> **Recordatorio del gate:** mientras la alerta esté activa, el pipeline de
> despliegue está bloqueado. Restablecer el servicio **no** es una
> excepción al gate: primero se corrige la causa.

---

## tasa-de-errores-5xx-alta

**Alerta:** `EfaTasaErrores5xxAlta` (crítica, P-OBS-004).
**Significado:** más de 0,1 errores 5xx por segundo durante 3 minutos.

### 1. Localizar el endpoint responsable

Dashboard **EFA - Errores, Logs y Alertas**, panel «Errores del servidor
(5xx) por endpoint». O directamente:

```promql
sum by (uri, status) (rate(http_server_requests_seconds_count{job=~"efa-backend.*", status=~"5.."}[5m])) * 60
```

### 2. Ver los logs de ese endpoint

```promql
# En Grafana > Explore > Loki
{service="efa-backend"} | json | path="uri"="<ENDPOINT>" | log.level="ERROR"
```

### 3. ¿Es una regresión del último despliegue?

```bash
# Comparar la tasa de error antes y despues del despliegue
curl -s -G "${PROMETHEUS_URL}/api/v1/query" \
  --data-urlencode 'query=sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m]))' \
  --data-urlencode "start=$(date -u -d '2 hours ago' +%s)" \
  --data-urlencode "end=$(date -u +%s)" \
  --data-urlencode 'step=300'
```

Si el error empezó justo en la marca del despliegue, **revertir**:

```bash
$KUBECTL rollout undo deployment/efa-backend -n efa
```

### 4. ¿Es una dependencia?

Si todos los endpoints fallan a la vez, el problema está fuera del
microservicio (base de datos, Cloudinary). Revisar el panel de latencia: si
la latencia subió antes de que subieran los errores, la dependencia es el
origen.

---

## efa-backend-caido (memoria)

**Alerta:** `EfaMemoriaEnRiesgoDeOOM` (crítica, P-OBS-005).
**Significado:** el contenedor usa más del 95 % de su límite de memoria.

### Diagnóstico

```promql
sum by (pod) (container_memory_working_set_bytes{namespace="efa", container!=""})
/
sum by (pod) (kube_pod_container_resource_limits{namespace="efa", resource="memory"})
```

### Acción inmediata

```bash
# Ampliar el limite temporalmente (el HPA ajusta CPU, no memoria)
$KUBECTL patch deployment efa-backend -n efa --type=json \
  -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"1536Mi"}]'
```

### Acción de fondo

Revisar el crecimiento histórico de `jvm_memory_used_bytes` y
`jvm_gc_pause_seconds` en el dashboard general. Un crecimiento monótono sin
GC eficiente indica una fuga; un crecimiento que sube y baja con los picos
de tráfico indica que el límite es simplemente bajo.

---

## consumo-de-cpu-elevado

**Alerta:** `EfaCpuSaturada` (advertencia).

### Ver si el HPA está respondiendo

```bash
$KUBECTL get hpa efa-backend -n efa
```

Si `TARGETS` no llega al máximo y la CPU sigue alta, el `HorizontalPodAutoscaler`
no está scaleando. Causa habitual: el contenedor no declara `requests` de
CPU (sin `requests`, el HPA no puede calcular el porcentaje de uso).

### Si la CPU es alta pero el servicio responde bien

Puede ser carga legítima. El HPA ya sube réplicas hasta `maxReplicas: 6`.
Si el máximo no alcanza, aumentar `maxReplicas` o el `LimitRange` del
namespace.

---

## latencia-p95-alta

**Alerta:** `EfaLatenciaP95Alta` (advertencia): p95 > 1,5 s.

### 1. ¿A qué endpoint?

```promql
histogram_quantile(0.95, sum by (le, uri) (rate(http_server_requests_seconds_bucket{job=~"efa-backend.*"}[5m])))
```

### 2. ¿Es la base de datos?

```promql
# Consultas lentas, si el driver expone la métrica
sum by (uri) (rate(jdbc_connections_acquire_seconds_sum[5m]))
```

También se puede consultar directamente en PostgreSQL:

```bash
$KUBECTL exec -n efa statefulset/efa-db -- \
  psql -U efa_user -d efa -c \
  "SELECT pid, state, wait_event_type, wait_event, left(query, 80)
   FROM pg_stat_activity WHERE datname='efa';"
```

`wait_event_type = 'Lock'` indica contención: una transacción larga está
bloqueando a otras.

### 3. ¿Son consultas N+1?

Revisar el log con `spring.jpa.show-sql` activado temporalmente en el
entorno de evaluación, o activar el análisis de consultas de Hibernate.

---

## despliegue-fallido

**Alerta:** `EfaDespliegueFallido` (crítica, P-CI-002).

### 1. Ver la ejecución

```bash
gh run list --workflow "Build, push y deploy backend (AWS EC2 + ECR)" --limit 5
gh run view <run-id> --log-failed
```

### 2. ¿Falló el gate?

Si el job `gate` falló, el commit **no pasó** alguna verificación
obligatoria. El motivo está en el log del job:

```bash
gh run view <run-id> --job <gate-job-id> --log | grep -A5 "FALLA"
```

### 3. ¿Falló el despliegue?

Revisar los logs de `docker compose` y el endpoint de salud. La causa más
frecuente en el entorno de evaluación es que la imagen no está disponible
en el runner: verificar el paso «Descargar imagen Docker para entorno
simulado».

### 4. Reintentar

```bash
gh run rerun <run-id> --failed
```

Reintentar un despliegue que falló por una causa **determinista** vuelve a
fallar. Si la causa fue de entorno (un runner con problemas de red), el
reintento tiene sentido.

---

## El gate de cumplimiento bloqueó el despliegue

**Síntoma:** el job «Compliance — Gate de cumplimiento» está en rojo.

### 1. Ver qué política falló

```bash
gh run view <run-id> --log | grep -A10 "RESUMEN DEL GATE"
```

El resumen indica `Politicas fallidas: P-SEC-001 P-QA-002`.

### 2. Reproducir en local

```bash
bash scripts/compliance/run-all.sh --continuar
```

### 3. Corregir y reintentar

La corrección depende de la política:

| Política | Corrección típica |
|---|---|
| `P-SEC-001` | Mover el secreto a GitHub Secrets y referenciarlo con `${...}`. |
| `P-SEC-002` | Añadir `USER` no root al Dockerfile y el `securityContext` al manifiesto. |
| `P-QA-002` | Añadir pruebas hasta superar el umbral. |
| `P-OBS-001/002` | Añadir las anotaciones `prometheus.io/*` o el endpoint de métricas. |
| `P-CI-001/003` | Revisar el orden de los jobs y quitar `continue-on-error: true`. |

---

## Un usuario reporta un error

### 1. Obtener el identificador de correlación

El frontend lo propaga en la cabecera `X-Correlation-Id` y el backend lo
devuelve en la respuesta. Si el usuario no lo tiene, se puede localizar por
hora y ruta.

### 2. Buscar en Loki

```promql
{service="efa-backend"} | json | traceId="<ID>"
```

También funciona desde la línea de comandos:

```bash
curl -s -G "${LOKI_URL}/loki/api/v1/query_range" \
  --data-urlencode 'query={service="efa-backend"} | json | traceId="<ID>"' \
  --data-urlencode 'limit=50' \
  --data-urlencode 'since=24h' | jq -r '.data.result[].values[][1]'
```

### 3. Correlacionar con las métricas

Con el `traceId` confirmado, comparar con `http_server_requests_seconds`
para saber si el error fue puntual o sistemático.

---

## Procedimientos de operación habituales

### Reiniciar un componente

```bash
$KUBECTL rollout restart deployment/efa-backend -n efa
$KUBECTL rollout status deployment/efa-backend -n efa
```

### Escalar manualmente

```bash
$KUBECTL scale deployment/efa-backend -n efa --replicas=4
```

### Deshacer un despliegue

```bash
$KUBECTL rollout history deployment/efa-backend -n efa
$KUBECTL rollout undo deployment/efa-backend -n efa
```

### Revisar el consumo por nodo

```bash
$KUBECTL top pods -n efa
$KUBECTL describe node | grep -A5 "Allocated resources"
```

### Descargar el reporte de cobertura de una ejecución

```bash
gh run download <run-id> --name jacoco-report
```

---

## Matriz de decisión rápida

| Señal | ¿Bloquea el despliegue? | Primer paso |
|---|---|---|
| Backend caído | **Sí** (P-OBS-003) | `kubectl get pods` y `kubectl logs`. |
| Errores 5xx | **Sí** (P-OBS-004) | Dashboard de errores por endpoint. |
| Memoria al 95 % | **Sí** (P-OBS-005) | Ampliar el límite y analizar la curva de memoria. |
| CPU al 85 % | No | Revisar el HPA. |
| Latencia p95 alta | No | Localizar el endpoint y correlacionar con la base de datos. |
| Cobertura bajo el umbral | **Sí** (P-QA-002) | Añadir pruebas; el pipeline ya se detuvo. |
| Alerta crítica de despliegue | Registra la incidencia | `gh run view`. |
