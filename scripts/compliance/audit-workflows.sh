#!/usr/bin/env bash
# =============================================================================
# audit-workflows.sh - Politicas P-QA-004, P-CI-001, P-CI-002 y P-CI-003
#
# Verifica la integridad del pipeline CI/CD:
#   1. Las acciones de GitHub estan fijadas a una version concreta.
#   2. Ningun paso de seguridad o calidad declara continue-on-error.
#   3. El despliegue se gatena por el resultado del CI, no de forma
#      independiente.
#   4. El despliegue usa el SHA del commit verificado.
#   5. Existe una etapa explicita de auditoria de cumplimiento.
#
# Uso:
#   audit-workflows.sh [directorio_de_workflows]
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

TARGET_DIR="${1:-.github/workflows}"
FINDINGS=0

report() {
  echo "[BLOCKER] $1 | $2 | $3"
  FINDINGS=$((FINDINGS + 1))
}

echo "=== P-QA-004 / P-CI-001 / P-CI-002 / P-CI-003: Auditoria de los workflows ==="

WORKFLOWS=()
while IFS= read -r FILE; do
  WORKFLOWS+=("${FILE}")
done < <(find "${TARGET_DIR}" -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort)

if [[ "${#WORKFLOWS[@]}" -eq 0 ]]; then
  echo "P-CI-001 FALLIDA: no se encontraron workflows en ${TARGET_DIR}"
  exit 1
fi

# --- 1. Acciones fijadas a una version (P-QA-004) ---------------------------
for WORKFLOW in "${WORKFLOWS[@]}"; do
  while IFS= read -r MATCH; do
    # Se quita el numero de linea que antepone grep -n, para que el
    # segundo campo sea realmente la accion.
    LINE="${MATCH#*:}"
    ACTION="$(awk '{print $2}' <<< "${LINE}")"
    # Se admiten tags con digito (v4, v5, v4.2.1 o 0.29.0, que es como
    # etiqueta la propia accion de Trivy) o un SHA de 40 caracteres.
    if ! grep -qE '@(v?[0-9]+([.][0-9]+)*|[0-9a-f]{40})$' <<< "${LINE}"; then
      report "P-QA-004" "${WORKFLOW}" "accion sin version fija: ${ACTION}"
    fi
  done < <(grep -nE '^\s*uses:\s*\S+' "${WORKFLOW}" || true)
done

# --- 2. Etapas de seguridad y calidad tolerantes a fallos (P-CI-003) --------
# Se identifican los pasos que ejecutan controles y se comprueba que no
# declaren continue-on-error: true.
CONTROL_MARKERS='sonar|snyk|trivy|audit|compliance|policy|test|verify|coverage|gate|scan'

for WORKFLOW in "${WORKFLOWS[@]}"; do
  while IFS='|' read -r STEP_LINE STEP_NAME; do
    [[ -z "${STEP_NAME}" ]] && continue
    if grep -qiE "${CONTROL_MARKERS}" <<< "${STEP_NAME}"; then
      report "P-CI-003" "${WORKFLOW}" "el paso '${STEP_NAME}' declara continue-on-error: true (linea ${STEP_LINE})"
    fi
  done < <(awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
      name = $0
      sub(/^.*name:[[:space:]]*/, "", name)
    }
    /continue-on-error:[[:space:]]*true/ {
      printf "%d|%s\n", NR, name
    }
  ' "${WORKFLOW}")
done

# --- 3. El despliegue depende del resultado del CI (P-CI-001) ---------------
DEPLOY_WORKFLOWS=()
for WORKFLOW in "${WORKFLOWS[@]}"; do
  if grep -qiE 'deploy|despliegue' <<< "$(head -n 5 "${WORKFLOW}")"; then
    DEPLOY_WORKFLOWS+=("${WORKFLOW}")
  fi
done

if [[ "${#DEPLOY_WORKFLOWS[@]}" -eq 0 ]]; then
  report "P-CI-001" "${TARGET_DIR}" "no se encontro ningun workflow de despliegue"
fi

for WORKFLOW in "${DEPLOY_WORKFLOWS[@]}"; do
  HAS_GATE=0
  if grep -qE 'workflow_run|needs:|github.event.workflow_run.conclusion' "${WORKFLOW}"; then
    HAS_GATE=1
  fi
  if [[ "${HAS_GATE}" -eq 0 ]]; then
    report "P-CI-001" "${WORKFLOW}" "el workflow de despliegue no depende del resultado del CI"
  fi
done

# --- 4. Trazabilidad del commit desplegado (P-CI-002) ----------------------
for WORKFLOW in "${DEPLOY_WORKFLOWS[@]}"; do
  if grep -qE 'ref:\s*(main|master|develop)\s*$' "${WORKFLOW}"; then
    report "P-CI-002" "${WORKFLOW}" "el despliegue usa una referencia de rama en vez del SHA verificado"
  fi
  if ! grep -qE 'head_sha|github\.sha|GITHUB_SHA' "${WORKFLOW}"; then
    report "P-CI-002" "${WORKFLOW}" "el despliegue no referencia el SHA del commit verificado"
  fi
done

# --- 5. Existe la etapa de auditoria de cumplimiento (P-CI-001) -------------
COMPLIANCE_FOUND=0
for WORKFLOW in "${WORKFLOWS[@]}"; do
  if grep -qiE 'compliance|cumplimiento|run-all\.sh' "${WORKFLOW}"; then
    COMPLIANCE_FOUND=1
  fi
done
if [[ "${COMPLIANCE_FOUND}" -eq 0 ]]; then
  report "P-CI-001" "${TARGET_DIR}" "ningun workflow ejecuta la auditoria de cumplimiento"
fi

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-QA-004/P-CI-001/P-CI-002/P-CI-003 FALLIDAS: ${FINDINGS} hallazgo(s). El pipeline se detiene."
  exit 1
fi

echo "P-QA-004/P-CI-001/P-CI-002/P-CI-003 APROBADAS: el pipeline mantiene sus controles."
exit 0
