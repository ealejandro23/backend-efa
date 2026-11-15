# =============================================================================
# Guion de obtencion de evidencias - Proyecto EFA
#
# Ejecuta este script para regenerar el directorio evidencias/ con las
# salidas reales del entorno de observabilidad y del cluster de Kubernetes.
#
# Uso:
#   bash scripts/evidencias/colectar.sh
#
# El resultado queda en evidencias/ y es el material que respalda
# docs/EVIDENCIAS.md.
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
EVIDENCIAS="${ROOT_DIR}/evidencias"
CONTEXTO="${KUBE_CONTEXT:-kind-efa-cluster}"

mkdir -p "${EVIDENCIAS}/k8s"

log() { echo "==> $*"; }

# -----------------------------------------------------------------------------
# 1. Stack local (Docker Compose)
# -----------------------------------------------------------------------------
log "Estado de los contenedores del stack de observabilidad"
docker compose -f "${ROOT_DIR}/infra/monitoring/docker-compose.monitoring.yml" ps \
  > "${EVIDENCIAS}/docker-compose-estado.txt" 2>&1 || true

log "Salud del microservicio"
curl --silent --show-error http://localhost:8083/actuator/health \
  > "${EVIDENCIAS}/backend-health.json" 2>/dev/null || echo "servicio no accesible" \
  > "${EVIDENCIAS}/backend-health.json"

log "Metricas del microservicio (muestra)"
curl --silent http://localhost:8083/actuator/prometheus 2>/dev/null \
  | grep -E '^efa_|^http_server_requests_seconds_count' \
  | head -n 40 > "${EVIDENCIAS}/metricas-microservicio.txt" || true

log "Objetivos descubiertos por Prometheus"
curl --silent http://localhost:9090/api/v1/targets 2>/dev/null \
  | tr ',' '\n' | grep -E '"job"|"health"|"scrapeUrl"' \
  > "${EVIDENCIAS}/prometheus-targets.txt" || true

log "Dashboards cargados en Grafana"
curl --silent --user "${GRAFANA_ADMIN_USER:-admin}:${GRAFANA_ADMIN_PASSWORD:-efa-observability}" \
  "http://localhost:3000/api/search?type=dash-db" 2>/dev/null \
  | tr '{' '\n' | grep -oE '"title":"[^"]+"' \
  > "${EVIDENCIAS}/grafana-dashboards.txt" || true

log "Series etiquetadas por servicio en Loki"
curl --silent http://localhost:3100/loki/api/v1/label/service/values 2>/dev/null \
  > "${EVIDENCIAS}/loki-servicios.json" || true

log "Ejemplo de log estructurado del backend"
curl --silent --get "http://localhost:3100/loki/api/v1/query_range" \
  --data-urlencode 'query={service="efa-backend"} | json' \
  --data-urlencode "limit=3" --data-urlencode "since=1h" 2>/dev/null \
  > "${EVIDENCIAS}/loki-log-backend.json" || true

log "Metricas del pipeline publicadas en el Pushgateway"
curl --silent --get http://localhost:9090/api/v1/query \
  --data-urlencode 'query=efa_ci_test_coverage_ratio or efa_ci_deployment_duration_seconds or efa_ci_deployments_total' 2>/dev/null \
  > "${EVIDENCIAS}/metricas-pipeline.json" || true

# -----------------------------------------------------------------------------
# 2. Cluster de Kubernetes
# -----------------------------------------------------------------------------
if kubectl cluster-info --context "${CONTEXTO}" >/dev/null 2>&1; then
  log "Pods del namespace efa"
  kubectl get pods -n efa -o wide --context "${CONTEXTO}" \
    > "${EVIDENCIAS}/k8s/pods.txt" 2>&1 || true

  log "Servicios, Ingress, HPA y PDB"
  { kubectl get svc -n efa --context "${CONTEXTO}"
    kubectl get ingress -n efa --context "${CONTEXTO}"
    kubectl get hpa,pdb -n efa --context "${CONTEXTO}"
    kubectl get networkpolicy -n efa --context "${CONTEXTO}"; } \
    > "${EVIDENCIAS}/k8s/recursos.txt" 2>&1 || true

  log "Anotaciones de descubrimiento de Prometheus"
  kubectl get pods -n efa -l app.kubernetes.io/name=efa-backend \
    -o jsonpath='{.items[0].metadata.annotations}' --context "${CONTEXTO}" \
    > "${EVIDENCIAS}/k8s/anotaciones-observabilidad.json" 2>&1 || true

  log "Metadatos del despliegue (version y commit en ejecucion)"
  kubectl get deployment efa-backend -n efa \
    -o jsonpath='{.spec.template.metadata.annotations}' --context "${CONTEXTO}" \
    > "${EVIDENCIAS}/k8s/metadatos-despliegue.json" 2>&1 || true

  log "Objetivos descubiertos por el Prometheus del cluster"
  kubectl exec -n efa deploy/prometheus -- \
    wget -qO- 'http://localhost:9090/api/v1/targets' \
    > "${EVIDENCIAS}/k8s/prometheus-targets.json" 2>/dev/null || true

  log "Metricas del microservicio leidas desde dentro del cluster"
  kubectl exec -n efa deploy/efa-backend -- \
    wget -qO- http://localhost:8080/actuator/prometheus \
    | grep -E '^efa_' > "${EVIDENCIAS}/k8s/metricas-desde-pod.txt" 2>/dev/null || true
else
  log "No hay cluster_kind disponible; se omite la evidencia de Kubernetes."
fi

# -----------------------------------------------------------------------------
# 3. Gate de cumplimiento
# -----------------------------------------------------------------------------
log "Salida del gate de cumplimiento"
( cd "${ROOT_DIR}" && bash scripts/compliance/run-all.sh --continuar ) \
  > "${EVIDENCIAS}/gate-cumplimiento.txt" 2>&1 || true

echo ""
echo "Evidencias generadas en: ${EVIDENCIAS}"
ls -la "${EVIDENCIAS}"
