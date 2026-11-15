# =============================================================================
# Levanta el stack completo de observabilidad del Proyecto EFA.
#
# Uso (PowerShell / bash):
#   ./scripts/local/obs-up.sh
#
# Requisitos: Docker y Docker Compose v2.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONITORING_COMPOSE="${ROOT_DIR}/infra/monitoring/docker-compose.monitoring.yml"

cd "${ROOT_DIR}"

echo "==> Levantando el stack de observabilidad (Prometheus, Grafana, Loki, Alloy, Pushgateway)"
docker compose -f "${MONITORING_COMPOSE}" up -d

echo "==> Esperando a que los servicios queden saludables..."
docker compose -f "${MONITORING_COMPOSE}" ps

echo
echo "Stack de observabilidad desplegado."
echo "  Prometheus : http://localhost:9090"
echo "  Grafana    : http://localhost:3000  (admin / efa-observability)"
echo "  Loki       : http://localhost:3100"
echo "  Alloy      : http://localhost:12345"
echo "  Pushgateway: http://localhost:9091"
