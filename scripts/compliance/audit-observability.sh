#!/usr/bin/env bash
# =============================================================================
# audit-observability.sh - Politicas P-OBS-001 y P-OBS-002
#
# Verifica que la observabilidad este integrada de forma automatica:
#   1. La aplicacion expone /actuator/prometheus y /actuator/health.
#   2. Los manifiestos de Kubernetes referencian esos endpoints en las sondas.
#   3. Los pods declaran las anotaciones de descubrimiento de Prometheus.
#   4. Existe una configuracion de Prometheus que recolecta el microservicio.
#   5. Existe al menos un dashboard que muestre las metricas clave.
#
# Uso:
#   audit-observability.sh
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

FINDINGS=0

report() {
  echo "[BLOCKER] $1 | $2 | $3"
  FINDINGS=$((FINDINGS + 1))
}

echo "=== P-OBS-001 / P-OBS-002: Auditoria de la integracion de observabilidad ==="

# --- 1. El codigo de la aplicacion expone las metricas ---------------------
# El endpoint /actuator/prometheus se habilita incluyendo "prometheus" en la
# lista blanca de endpoints de gestion del actuator.
if ! grep -qE '^management\.endpoints\.web\.exposure\.include=.*prometheus' \
    demo/src/main/resources/application.properties 2>/dev/null; then
  report "P-OBS-001" "application.properties" "no se expone el endpoint /actuator/prometheus del actuator"
fi

if ! grep -qE '^management\.endpoints\.web\.exposure\.include=.*health' \
    demo/src/main/resources/application.properties 2>/dev/null; then
  report "P-OBS-001" "application.properties" "no se expone el endpoint /actuator/health del actuator"
fi

if ! grep -qE '^management\.metrics\.tags\.service\.name=' \
    demo/src/main/resources/application.properties 2>/dev/null; then
  report "P-OBS-001" "application.properties" "no se declaran las etiquetas comunes de las metricas"
fi

# El registro de Prometheus es lo que habilita el endpoint.
if ! grep -q "micrometer-registry-prometheus" demo/pom.xml; then
  report "P-OBS-001" "demo/pom.xml" "falta la dependencia micrometer-registry-prometheus"
fi

# --- 2. Las sondas de Kubernetes usan los endpoints de salud ---------------
if ! grep -rq "actuator/health" infra/k8s/ 2>/dev/null; then
  report "P-OBS-001" "infra/k8s" "las sondas de Kubernetes no referencian /actuator/health"
fi

# --- 3. Anotaciones de descubrimiento de Prometheus ------------------------
PODS_WITH_SCRAPE="$(grep -rl 'prometheus.io/scrape' infra/k8s/base/ 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${PODS_WITH_SCRAPE}" -eq 0 ]]; then
  report "P-OBS-002" "infra/k8s" "ningun pod declara las anotaciones prometheus.io/scrape"
else
  echo "  [INFO] ${PODS_WITH_SCRAPE} manifiesto(s) con anotaciones de descubrimiento"
fi

if ! grep -rq 'prometheus.io/path' infra/k8s/base/ 2>/dev/null; then
  report "P-OBS-002" "infra/k8s" "falta la anotacion prometheus.io/path en los manifiestos"
fi

if ! grep -rq 'prometheus.io/port' infra/k8s/base/ 2>/dev/null; then
  report "P-OBS-002" "infra/k8s" "falta la anotacion prometheus.io/port en los manifiestos"
fi

# --- 4. Configuracion de Prometheus que recolecta el microservicio ---------
PROMETHEUS_CONFIGS=(
  "infra/monitoring/prometheus/prometheus.yml"
  "infra/k8s/observability/prometheus.yml"
)
FOUND_CONFIG=0
for CONFIG in "${PROMETHEUS_CONFIGS[@]}"; do
  if [[ -f "${CONFIG}" ]] && grep -q 'efa-backend' "${CONFIG}"; then
    FOUND_CONFIG=1
    echo "  [INFO] scrape configurado en ${CONFIG}"
  fi
done
if [[ "${FOUND_CONFIG}" -eq 0 ]]; then
  report "P-OBS-002" "infra/monitoring" "ninguna configuracion de Prometheus recolecta el microservicio"
fi

# --- 5. Dashboards con las metricas clave exigidas --------------------------
DASHBOARD_DIR="infra/monitoring/grafana/dashboards"
REQUIRED_METRICS=("http_server_requests_seconds" "container_cpu_usage_seconds_total" "container_memory_working_set_bytes" "efa_ci_deployment_duration_seconds" "efa_ci_test_coverage_ratio" "efa_errors_total")

if [[ ! -d "${DASHBOARD_DIR}" ]]; then
  report "P-OBS-001" "${DASHBOARD_DIR}" "no existe el directorio de dashboards"
else
  DASHBOARD_CONTENT="$(cat "${DASHBOARD_DIR}"/*.json 2>/dev/null || true)"
  for METRIC in "${REQUIRED_METRICS[@]}"; do
    if ! grep -q "${METRIC}" <<< "${DASHBOARD_CONTENT}"; then
      report "P-OBS-001" "${DASHBOARD_DIR}" "ningun dashboard muestra la metrica ${METRIC}"
    fi
  done
  DASHBOARD_COUNT="$(find "${DASHBOARD_DIR}" -name '*.json' | wc -l | tr -d ' ')"
  echo "  [INFO] ${DASHBOARD_COUNT} dashboard(s) verificados"
fi

# --- 6. El frontend tambien es observable ----------------------------------
if ! grep -rq 'nginx_status\|/healthz' infra/k8s/base/05-frontend.yaml 2>/dev/null; then
  report "P-OBS-001" "infra/k8s/base/05-frontend.yaml" "el frontend no expone sonda de salud ni estado de nginx"
fi

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-OBS-001/P-OBS-002 FALLIDAS: ${FINDINGS} hallazgo(s). El pipeline se detiene."
  exit 1
fi

echo "P-OBS-001 y P-OBS-002 APROBADAS: la observabilidad esta integrada de forma automatica."
exit 0
