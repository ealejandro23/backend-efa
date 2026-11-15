#!/usr/bin/env bash
# =============================================================================
# audit-coverage.sh - Politica P-QA-002
#
# Verifica que la cobertura de lineas medida por JaCoCo alcance el umbral
# minimo exigido (60% por defecto).
#
# Uso:
#   audit-coverage.sh [ruta_jacoco.xml] [umbral]
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

REPORT_FILE="${1:-${JACOCO_REPORT:-demo/target/site/jacoco/jacoco.xml}}"
THRESHOLD="${2:-${COVERAGE_MIN:-0.60}}"

echo "=== P-QA-002: Gate de cobertura de pruebas ==="

if [[ ! -f "${REPORT_FILE}" ]]; then
  echo "[BLOCKER] P-QA-002 | ${REPORT_FILE} | no existe el reporte de cobertura de JaCoCo"
  echo "P-QA-002 FALLIDA: el pipeline se detiene."
  exit 1
fi

read -r MISSED COVERED <<< "$(sed -n 's/.*<counter type="LINE" missed="\([0-9]*\)" covered="\([0-9]*\)".*/\1 \2/p' "${REPORT_FILE}" | tail -n 1)"

MISSED="${MISSED:-0}"
COVERED="${COVERED:-0}"
TOTAL=$((MISSED + COVERED))

if [[ "${TOTAL}" -eq 0 ]]; then
  echo "[BLOCKER] P-QA-002 | ${REPORT_FILE} | el reporte no contiene lineas instrumentadas"
  echo "P-QA-002 FALLIDA: el pipeline se detiene."
  exit 1
fi

COVERAGE="$(awk -v c="${COVERED}" -v t="${TOTAL}" 'BEGIN { printf "%.6f", c / t }')"
COVERAGE_PCT="$(awk -v c="${COVERED}" -v t="${TOTAL}" 'BEGIN { printf "%.2f", (c / t) * 100 }')"
THRESHOLD_PCT="$(awk -v t="${THRESHOLD}" 'BEGIN { printf "%.2f", t * 100 }')"

echo "  Cobertura de lineas: ${COVERAGE_PCT}% (${COVERED} cubiertas de ${TOTAL})"
echo "  Umbral exigido     : ${THRESHOLD_PCT}%"

if awk -v c="${COVERAGE}" -v t="${THRESHOLD}" 'BEGIN { exit !(c < t) }'; then
  echo "[BLOCKER] P-QA-002 | cobertura | ${COVERAGE_PCT}% es inferior al umbral ${THRESHOLD_PCT}%"
  echo "P-QA-002 FALLIDA: el pipeline se detiene y no se realiza el despliegue."
  exit 1
fi

echo "P-QA-002 APROBADA: la cobertura cumple el umbral."
exit 0
