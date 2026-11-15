#!/usr/bin/env bash
# =============================================================================
# publish-deploy-metrics.sh - Publica las metricas de despliegue
#
# Se ejecuta al finalizar el job de despliegue. Publica:
#   efa_ci_deployment_duration_seconds : duracion total del despliegue
#   efa_ci_deployment_status           : 1 si fue exitoso, 0 si fallo
#   efa_ci_stage_duration_seconds      : duracion por etapa
#   efa_ci_deployments_total           : contador de despliegues ejecutados
#
# Uso:
#   publish-deploy-metrics.sh <duracion_segundos> <estado> [etiqueta=valor ...]
#     estado: success | failed
#
# Variables de entorno:
#   PUSHGATEWAY_URL        URL del Pushgateway
#   DEPLOY_STAGES_JSON     JSON con las etapas y su duracion, por ejemplo:
#                          '{"build": 62, "quality": 18, "deploy": 41}'
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DURATION="${1:-0}"
STATUS="${2:-failed}"
shift 2 || true

case "${STATUS}" in
  success) STATUS_VALUE=1 ;;
  failed)  STATUS_VALUE=0 ;;
  *)       echo "!! Estado no valido: ${STATUS} (use 'success' o 'failed')" >&2; exit 2 ;;
esac

EXTRA_LABELS=("$@")
LABEL_ARGS=("branch=${GITHUB_REF_NAME:-unknown}" "commit=${GITHUB_SHA:-unknown}" "status=${STATUS}")
if [[ ${#EXTRA_LABELS[@]} -gt 0 ]]; then
  LABEL_ARGS+=("${EXTRA_LABELS[@]}")
fi
# --- Metricas principales ----------------------------------------------------
bash "${SCRIPT_DIR}/publish-metrics.sh" efa_ci_deployment_duration_seconds "${DURATION}" "${LABEL_ARGS[@]}"
bash "${SCRIPT_DIR}/publish-metrics.sh" efa_ci_deployment_status "${STATUS_VALUE}" "${LABEL_ARGS[@]}"

# --- Contador de despliegues -------------------------------------------------
# El Pushgateway reemplaza el valor de la serie cada vez que se publica, por
# lo que un contador no puede simplemente "sumarse". La forma correcta es
# leer el valor actual, incrementarlo y volver a publicarlo.
#
# Nota: el Pushgateway solo permite leer el estado completo con GET /metrics
# (no con GET sobre un grupo concreto), por lo que se filtra la serie
# buscada dentro del resultado.
GROUP_REPOSITORY="${REPOSITORY:-${GITHUB_REPOSITORY:-local}}"
GROUP_REPOSITORY="${GROUP_REPOSITORY//\//_}"
DEPLOY_COUNTER_PATH="${PUSHGATEWAY_URL:-http://localhost:9091}/metrics/job/deployments/repository/${GROUP_REPOSITORY}"

CURRENT_VALUE="$(curl --silent --show-error "${PUSHGATEWAY_URL:-http://localhost:9091}/metrics" 2>/dev/null \
  | awk -v repo="${GROUP_REPOSITORY}" '/^efa_ci_deployments_total\{/ && index($0, "repository=\"" repo "\"") > 0 { print $NF }' \
  | tail -n 1)"
CURRENT_VALUE="${CURRENT_VALUE:-0}"
[[ "${CURRENT_VALUE}" =~ ^[0-9]+$ ]] || CURRENT_VALUE=0

NEW_VALUE=$((CURRENT_VALUE + 1))
# El formato de exposicion de Prometheus exige que cada linea termine en
# salto de linea; de lo contrario el Pushgateway rechaza el cuerpo.
# El cuerpo se escribe en un archivo temporal porque la sustitucion de
# comandos ($( ... )) elimina los saltos de linea finales.
COUNTER_FILE="$(mktemp)"
trap 'rm -f "${COUNTER_FILE}"' EXIT
printf 'efa_ci_deployments_total{repository="%s",branch="%s"} %s\n' \
  "${GROUP_REPOSITORY}" "${GITHUB_REF_NAME:-unknown}" "${NEW_VALUE}" > "${COUNTER_FILE}"

HTTP_CODE="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --data-binary "@${COUNTER_FILE}" \
  "${DEPLOY_COUNTER_PATH}")"

if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "202" ]]; then
  echo "!! No se pudo publicar el contador de despliegues (HTTP ${HTTP_CODE})" >&2
else
  echo ">> Contador de despliegues: ${NEW_VALUE} (total acumulado)"
fi

if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "202" ]]; then
  echo "!! No se pudo publicar el contador de despliegues (HTTP ${HTTP_CODE})" >&2
fi

# --- Duracion por etapa ------------------------------------------------------
if [[ -n "${DEPLOY_STAGES_JSON:-}" ]]; then
  # Se itera sobre las entradas del JSON sin depender de jq.
  while IFS=$'\t' read -r stage seconds; do
    [[ -z "${stage}" ]] && continue
    bash "${SCRIPT_DIR}/publish-metrics.sh" \
      efa_ci_stage_duration_seconds "${seconds}" \
      "${LABEL_ARGS[@]}" "stage=${stage}"
  done < <(printf '%s' "${DEPLOY_STAGES_JSON}" | tr ',' '\n' | sed 's/[{}"]//g' | awk -F: 'NF==2 {gsub(/ /,"",$1); gsub(/ /,"",$2); print $1 "\t" $2}')
fi

echo ">> Metricas de despliegue publicadas (duracion=${DURATION}s, estado=${STATUS})"
