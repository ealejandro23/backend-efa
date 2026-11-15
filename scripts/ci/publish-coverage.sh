#!/usr/bin/env bash
# =============================================================================
# publish-coverage.sh - Publica la cobertura de pruebas medida por JaCoCo
#
# Lee el reporte XML de JaCoCo, calcula la cobertura de lineas y la publica
# en el Pushgateway como efa_ci_test_coverage_ratio.
#
# Uso:
#   publish-coverage.sh [ruta_al_jacoco.xml] [umbral_minimo]
#
# Variables de entorno:
#   PUSHGATEWAY_URL  URL del Pushgateway
#   JACOCO_REPORT    Ruta alternativa al reporte XML
#   COVERAGE_MIN     Umbral minimo de cobertura (0.0 - 1.0). Si la cobertura
#                    queda por debajo, el script termina con codigo 1 y el
#                    pipeline se detiene (politica P-QA-002).
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

REPORT_FILE="${1:-${JACOCO_REPORT:-demo/target/site/jacoco/jacoco.xml}}"
COVERAGE_MIN="${2:-${COVERAGE_MIN:-0.60}}"

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "!! No se encontro el reporte de JaCoCo en: ${REPORT_FILE}" >&2
  echo "   Ejecutar 'mvn clean verify' antes de publicar la cobertura." >&2
  exit 1
fi

# Extrae los contadores agregados del reporte.
read -r COVERED_MISSED <<<"$(sed -n 's/.*<counter type="LINE" missed="\([0-9]*\)" covered="\([0-9]*\)".*/\1 \2/p' "${REPORT_FILE}" | tail -n 1)"

if [[ -z "${COVERED_MISSED:-}" || -z "${COVERED_MISSED// /}" ]]; then
  echo "!! No se pudieron leer los contadores de lineas del reporte JaCoCo." >&2
  exit 1
fi

MISSED="${COVERED_MISSED%% *}"
COVERED="${COVERED_MISSED##* }"
TOTAL=$((MISSED + COVERED))

if [[ "${TOTAL}" -eq 0 ]]; then
  echo "!! El reporte de JaCoCo no contiene lineas instrumentadas." >&2
  exit 1
fi

# La cobertura se expresa como proporcion (0..1) para que Grafana la muestre
# directamente como porcentaje.
COVERAGE="$(awk -v c="${COVERED}" -v t="${TOTAL}" 'BEGIN { printf "%.6f", c / t }')"
COVERAGE_PCT="$(awk -v c="${COVERED}" -v t="${TOTAL}" 'BEGIN { printf "%.2f", (c / t) * 100 }')"

echo ">> Cobertura de lineas: ${COVERAGE_PCT}% (${COVERED}/${TOTAL} lineas cubiertas)"

bash "${SCRIPT_DIR}/publish-metrics.sh" \
  efa_ci_test_coverage_ratio "${COVERAGE}" \
  "branch=${GITHUB_REF_NAME:-unknown}" \
  "commit=${GITHUB_SHA:-unknown}" \
  "threshold=${COVERAGE_MIN}" || true

# --- Gate de cobertura (P-QA-002) -------------------------------------------
if awk -v c="${COVERAGE}" -v m="${COVERAGE_MIN}" 'BEGIN { exit !(c < m) }'; then
  echo "!! FALLA P-QA-002: la cobertura (${COVERAGE_PCT}%) es inferior al minimo exigido (${COVERAGE_MIN}%)." >&2
  echo "   El pipeline se detiene y no se realiza el despliegue." >&2
  exit 1
fi

echo ">> Gate P-QA-002 superado: cobertura >= ${COVERAGE_PCT}%"
