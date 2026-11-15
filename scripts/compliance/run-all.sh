#!/usr/bin/env bash
# =============================================================================
# run-all.sh - Gate de cumplimiento del Proyecto EFA
#
# Ejecuta la totalidad de las auditorias de cumplimiento y consolida el
# resultado. Si alguna politica bloqueante (blocker o major) falla, el script
# termina con codigo distinto de cero y el pipeline se detiene ANTES del
# despliegue. Esta es la materializacion del indicador IE6.
#
# Uso:
#   run-all.sh [--solo <politica>] [--continuar]
#
#   --solo <politica>   Ejecuta solo las politicas indicadas (por ejemplo
#                       "P-SEC-001 P-QA-002").
#   --continuar          No se detiene ante el primer fallo: ejecuta todas
#                       las auditorias y reporta el resumen. Es el modo que
#                       usa el pipeline para presentar el informe completo.
#
# Variables de entorno:
#   PUSHGATEWAY_URL   URL del Pushgateway para publicar el resultado
#   PROMETHEUS_URL    URL de Prometheus para consultar las alertas activas
#   SKIP_ALERTS       Si vale "true", omite la auditoria de alertas
#   SKIP_BRANCH       Si vale "true", omite la verificacion de proteccion
#                     de rama (util cuando el token no tiene permisos)
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT_DIR}"

ONLY_POLICIES=""
CONTINUE_ON_ERROR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --solo)
      ONLY_POLICIES="$2"
      shift 2
      ;;
    --continuar)
      CONTINUE_ON_ERROR=1
      shift
      ;;
    *)
      echo "Opcion no reconocida: $1" >&2
      exit 2
      ;;
  esac
done

# --- Definicion de las auditorias -------------------------------------------
# Cada entrada: "POLITICA|SEVERIDAD|NOMBRE|SCRIPT"
AUDITS=(
  "P-SEC-001|blocker|Sin secretos hardcodeados|audit-secrets.sh"
  "P-SEC-002|blocker|Contenedores sin privilegios ni root|audit-dockerfile.sh"
  "P-SEC-004|blocker|Manifiestos Kubernetes con contexto de seguridad|audit-kubernetes.sh"
  "P-SEC-003|blocker|Dependencias sin vulnerabilidades criticas o altas|audit-dependencies.sh"
  "P-SEC-006|major|Proteccion de rama activa|verify-branch-protection.sh"
  "P-QA-002|blocker|Cobertura minima de pruebas|audit-coverage.sh"
  "P-QA-004|major|Acciones de GitHub fijadas a una version|audit-workflows.sh"
  "P-CI-001|blocker|El despliegue depende de las verificaciones en verde|audit-workflows.sh"
  "P-OBS-001|blocker|El microservicio expone metricas y sonda de salud|audit-observability.sh"
  "P-OBS-002|major|Descubrimiento automatico de metricas|audit-observability.sh"
  "P-OBS-003|blocker|Sin alertas criticas de disponibilidad|audit-alerts.sh"
  "P-DOC-001|minor|Documentacion actualizada|audit-docs.sh"
  "P-DOC-002|minor|Declaracion del uso de inteligencia artificial|audit-docs.sh"
)

echo "############################################################"
echo "#  GATE DE CUMPLIMIENTO - PROYECTO EFA"
echo "#  $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
echo "#  Commit: ${GITHUB_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')}"
echo "#  Rama  : ${GITHUB_REF_NAME:-$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'local')}"
echo "############################################################"
echo ""

PASSED=0
FAILED=0
SKIPPED=0
MINOR_FAILED=0
FAILED_POLICIES=()
MINOR_POLICIES=()

should_run() {
  local policy="$1"
  [[ -z "${ONLY_POLICIES}" ]] && return 0
  for candidate in ${ONLY_POLICIES}; do
    [[ "${policy}" == "${candidate}" ]] && return 0
  done
  return 1
}

for AUDIT in "${AUDITS[@]}"; do
  POLICY="$(cut -d'|' -f1 <<< "${AUDIT}")"
  SEVERITY="$(cut -d'|' -f2 <<< "${AUDIT}")"
  NAME="$(cut -d'|' -f3 <<< "${AUDIT}")"
  SCRIPT="$(cut -d'|' -f4 <<< "${AUDIT}")"

  if ! should_run "${POLICY}"; then
    echo "-- [SKIP] ${POLICY} ${NAME} (fuera del alcance solicitado)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # --- Omitir las auditorias que requieren infraestructura no disponible ----
  if [[ "${SCRIPT}" == "audit-alerts.sh" && "${SKIP_ALERTS:-false}" == "true" ]]; then
    echo "-- [SKIP] ${POLICY} ${NAME} (SKIP_ALERTS=true)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [[ "${SCRIPT}" == "verify-branch-protection.sh" && "${SKIP_BRANCH:-false}" == "true" ]]; then
    echo "-- [SKIP] ${POLICY} ${NAME} (SKIP_BRANCH=true)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "------------------------------------------------------------"
  echo ">> ${POLICY} [${SEVERITY}] ${NAME}"
  echo "------------------------------------------------------------"

  SCRIPT_PATH="${SCRIPT_DIR}/${SCRIPT}"
  if [[ ! -f "${SCRIPT_PATH}" ]]; then
    echo "!! No se encontro el script de auditoria: ${SCRIPT_PATH}"
    FAILED=$((FAILED + 1))
    FAILED_POLICIES+=("${POLICY}")
    continue
  fi

  bash "${SCRIPT_PATH}"
  RESULT=$?

  if [[ ${RESULT} -eq 0 ]]; then
    echo ">> ${POLICY}: APROBADA"
    PASSED=$((PASSED + 1))
  else
    # Las politicas de severidad "minor" se informan, pero no bloquean el
    # pipeline, por lo que no se cuentan como fallidas.
    if [[ "${SEVERITY}" == "minor" ]]; then
      echo ">> ${POLICY}: FALLIDA (severidad 'minor': se informa, el pipeline continua)"
      MINOR_FAILED=$((MINOR_FAILED + 1))
      MINOR_POLICIES+=("${POLICY}")
    else
      echo ">> ${POLICY}: FALLIDA (codigo ${RESULT})"
      FAILED=$((FAILED + 1))
      FAILED_POLICIES+=("${POLICY}")

      if [[ "${CONTINUE_ON_ERROR}" -eq 0 ]]; then
        echo ""
        echo "Politica bloqueante incumplida. El pipeline se detiene."
        break
      fi
    fi
  fi
  echo ""
done

# --- Resumen ----------------------------------------------------------------
echo "############################################################"
echo "#  RESUMEN DEL GATE DE CUMPLIMIENTO"
echo "############################################################"
echo "  Politicas evaluadas : $((PASSED + FAILED + MINOR_FAILED))"
echo "  Aprobadas           : ${PASSED}"
echo "  Fallidas (bloqueantes): ${FAILED}"
echo "  Fallidas (menores)  : ${MINOR_FAILED}"
echo "  Omitidas            : ${SKIPPED}"

if [[ ${#FAILED_POLICIES[@]} -gt 0 ]]; then
  echo "  Politicas fallidas  : ${FAILED_POLICIES[*]}"
fi
if [[ ${#MINOR_POLICIES[@]} -gt 0 ]]; then
  echo "  Politicas menores   : ${MINOR_POLICIES[*]}"
fi
echo ""

# --- Publicacion del resultado en el Pushgateway ---------------------------
# El resultado se publica como metricas para que el panel de Grafana muestre
# el estado de cada politica y se pueda correlacionar con la ejecucion del
# pipeline que fallo.
if [[ -n "${PUSHGATEWAY_URL:-}" ]]; then
  for POLICY in "${FAILED_POLICIES[@]}"; do
    bash "${SCRIPT_DIR}/../ci/publish-metrics.sh" efa_ci_compliance_policy_passed 0 \
      "policy=${POLICY}" "severity=blocker" \
      "branch=${GITHUB_REF_NAME:-local}" "commit=${GITHUB_SHA:-local}" >/dev/null 2>&1 || true
  done
  bash "${SCRIPT_DIR}/../ci/publish-metrics.sh" efa_ci_compliance_total \
    "$((PASSED + FAILED))" "branch=${GITHUB_REF_NAME:-local}" >/dev/null 2>&1 || true
fi

if [[ ${#FAILED_POLICIES[@]} -gt 0 ]]; then
  echo "############################################################"
  echo "#  RESULTADO: CUMPLIMIENTO RECHAZADO"
  echo "#  Politicas incumplidas: ${FAILED_POLICIES[*]}"
  echo "#  El despliegue NO se realiza. El entorno productivo queda"
  echo "#  protegido."
  echo "############################################################"
  exit 1
fi

echo "############################################################"
echo "#  RESULTADO: CUMPLIMIENTO APROBADO"
echo "#  El pipeline puede continuar con el despliegue."
echo "############################################################"
exit 0
