#!/usr/bin/env bash
# =============================================================================
# publish-metrics.sh - Publica metricas del pipeline en el Pushgateway
#
# Las metricas del pipeline (duracion del despliegue, cobertura de pruebas,
# resultado del build) no tienen un endpoint activo que Prometheus pueda
# scrapear, porque nacen y mueren dentro de una ejecucion del workflow. Por
# eso se usa el modelo "push" del Pushgateway.
#
# Uso:
#   publish-metrics.sh <nombre_metrica> <valor> [etiqueta=valor ...]
#
# Ejemplos:
#   publish-metrics.sh efa_ci_test_coverage_ratio 0.73 branch=main commit=abc123
#   publish-metrics.sh efa_ci_build_success 1 branch=main
#
# Variables de entorno:
#   PUSHGATEWAY_URL  URL del Pushgateway (por defecto http://localhost:9091)
#   JOB_NAME         Nombre del job, se agrega como etiqueta
#   REPOSITORY       Repositorio, se agrega como etiqueta
# =============================================================================
set -euo pipefail

PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://localhost:9091}"
JOB_NAME="${JOB_NAME:-${GITHUB_JOB:-desconocido}}"
REPOSITORY="${REPOSITORY:-${GITHUB_REPOSITORY:-local}}"

METRIC_NAME="${1:-}"
METRIC_VALUE="${2:-}"
shift 2 || true

if [[ -z "${METRIC_NAME}" || -z "${METRIC_VALUE}" ]]; then
  echo "Uso: $0 <nombre_metrica> <valor> [etiqueta=valor ...]" >&2
  exit 2
fi

# --- Construccion de las etiquetas -------------------------------------------
# Las etiquetas se aplican a la propia serie de la metrica, para que los
# dashboards puedan filtrar por rama, commit, ambiente o politica evaluada.
# Si una clave se repite, gana el ultimo valor (Prometheus rechaza las
# series con etiquetas duplicadas).
declare -A LABEL_MAP=()
LABEL_MAP["repository"]="${REPOSITORY}"
LABEL_MAP["job"]="${JOB_NAME}"

for pair in "$@"; do
  [[ -z "${pair}" ]] && continue
  key="${pair%%=*}"
  value="${pair#*=}"
  key="${key//[^a-zA-Z0-9_]/_}"
  LABEL_MAP["${key}"]="${value}"
done

LABELS=""
for key in "${!LABEL_MAP[@]}"; do
  value="${LABEL_MAP[${key}]//[^a-zA-Z0-9_.:@\-/]/_}"
  LABELS="${LABELS:+${LABELS},}${key}=\"${value}\""
done

# --- Etiquetas de la serie de identificacion ---------------------------------
# efa_ci_build_info identifica la ejecucion del pipeline. Se publica SIEMPRE
# con el mismo conjunto de etiquetas, para que sea una unica serie por job y
# no se fragmente en miles de combinaciones.
BUILD_INFO_LABELS="repository=\"${REPOSITORY}\",job=\"${JOB_NAME}\""

# --- Escape del valor --------------------------------------------------------
escaped_value="$(printf '%s' "${METRIC_VALUE}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g')"

# El nombre del repositorio no puede contener "/" porque forma parte de la
# ruta del Pushgateway.
GROUP_REPOSITORY="${REPOSITORY//\//_}"
GROUP_JOB="${JOB_NAME//\//_}"

echo ">> Publicando ${METRIC_NAME}{${LABELS}} = ${escaped_value}"

# El formato de exposicion de Prometheus exige que cada linea termine en
# salto de linea; de lo contrario el Pushgateway rechaza el cuerpo.
#
# El cuerpo se escribe en un archivo temporal porque la sustitucion de
# comandos ($( ... )) elimina los saltos de linea finales.
BODY_FILE="$(mktemp)"
trap 'rm -f "${BODY_FILE}"' EXIT
printf 'efa_ci_build_info{%s} 1\n%s{%s} %s\n' \
  "${BUILD_INFO_LABELS}" "${METRIC_NAME}" "${LABELS}" "${escaped_value}" > "${BODY_FILE}"

HTTP_CODE="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --data-binary "@${BODY_FILE}" \
  "${PUSHGATEWAY_URL}/metrics/job/${GROUP_JOB}/repository/${GROUP_REPOSITORY}")"

if [[ "${HTTP_CODE}" != "200" && "${HTTP_CODE}" != "202" ]]; then
  echo "!! No se pudo publicar la metrica en el Pushgateway (HTTP ${HTTP_CODE})" >&2
  echo "   Etiquetas enviadas: ${LABELS}" >&2
  exit 1
fi

echo ">> Metrica publicada correctamente"
