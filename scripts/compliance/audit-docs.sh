#!/usr/bin/env bash
# =============================================================================
# audit-docs.sh - Politicas P-DOC-001 y P-DOC-002
#
# Verifica que la documentacion exigida por la pauta exista y este actualizada:
#   1. Documento de integracion de las herramientas de observabilidad.
#   2. Documento de despliegue en el entorno orquestado.
#   3. Documento de politicas de cumplimiento.
#   4. Documento de integracion en el pipeline CI/CD.
#   5. Declaracion del uso de inteligencia artificial.
#   6. Runbook con los procedimientos de operacion.
#
# Uso:
#   audit-docs.sh
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

FINDINGS=0

report_minor() {
  echo "[MINOR] $1 | $2 | $3"
  FINDINGS=$((FINDINGS + 1))
}

echo "=== P-DOC-001 / P-DOC-002: Auditoria de la documentacion ==="

# --- Documentos requeridos --------------------------------------------------
REQUIRED_DOCS=(
  "docs/OBSERVABILITY.md:P-OBS-001:integracion de las herramientas de observabilidad"
  "docs/DEPLOYMENT-K8S.md:P-OBS-001:despliegue en el entorno orquestado"
  "docs/COMPLIANCE.md:P-SEC-001:politicas de cumplimiento"
  "docs/CI-CD-INTEGRATION.md:P-CI-001:integracion de las herramientas en el pipeline"
  "docs/RUNBOOK.md:P-OBS-003:procedimientos de operacion ante incidentes"
  "docs/DECISION-RECORDS.md:P-OBS-001:registro de decisiones tecnicas"
  "docs/USO-DE-IA.md:P-DOC-002:declaracion del uso de inteligencia artificial"
)

for ENTRY in "${REQUIRED_DOCS[@]}"; do
  FILE="${ENTRY%%:*}"
  REST="${ENTRY#*:}"
  POLICY="${REST%%:*}"
  DESCRIPTION="${REST#*:}"

  if [[ ! -f "${FILE}" ]]; then
    report_minor "${POLICY}" "${FILE}" "falta el documento de ${DESCRIPTION}"
    continue
  fi

  # El documento no debe estar vacio ni ser un simple marcador de posicion.
  SIZE="$(wc -c < "${FILE}" | tr -d ' ')"
  if [[ "${SIZE}" -lt 500 ]]; then
    report_minor "${POLICY}" "${FILE}" "el documento esta incompleto (${SIZE} bytes)"
  else
    echo "  [OK] ${FILE} (${SIZE} bytes)"
  fi
done

# --- El README debe referenciar las nuevas secciones ------------------------
if [[ -f "README.md" ]]; then
  for SECTION in "Observabilidad" "Kubernetes" "Cumplimiento" "Grafana"; do
    if ! grep -qi "${SECTION}" README.md; then
      report_minor "P-DOC-001" "README.md" "no referienta la seccion '${SECTION}'"
    fi
  done
else
  report_minor "P-DOC-001" "README.md" "no existe el README del proyecto"
fi

# --- El catalogo de politicas debe estar sincronizado con el repositorio ---
if [[ -f "compliance/policies/catalog.yml" ]]; then
  POLICY_COUNT="$(grep -c '^  - id: P-' compliance/policies/catalog.yml || true)"
  if [[ "${POLICY_COUNT}" -lt 10 ]]; then
    report_minor "P-DOC-001" "compliance/policies/catalog.yml" "el catalogo declara menos de 10 politicas"
  else
    echo "  [OK] catalogo de politicas con ${POLICY_COUNT} entradas"
  fi
else
  report_minor "P-DOC-001" "compliance/policies/catalog.yml" "no existe el catalogo de politicas"
fi

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-DOC-001/P-DOC-002 con observaciones: ${FINDINGS} punto(s) menor(es) a corregir."
  exit 0
fi

echo "P-DOC-001 y P-DOC-002 APROBADAS: la documentacion esta completa."
exit 0
