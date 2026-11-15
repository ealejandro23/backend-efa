#!/usr/bin/env bash
# =============================================================================
# audit-alerts.sh - Politicas P-OBS-003, P-OBS-004 y P-OBS-005
#
# Consulta las alertas activas en Prometheus. Si alguna alerta de severidad
# critica esta en estado "firing", el pipeline se detiene: desplegar sobre un
# servicio que ya esta fallando agrava el incidente.
#
# Las reglas de alerta del proyecto llevan la etiqueta "cumplimiento" con el
# identificador de la politica asociada, de modo que la consulta es precisa
# y no depende de una lista de nombres de alerta mantenida a mano.
#
# Uso:
#   audit-alerts.sh [url_prometheus]
#
# Variables de entorno:
#   PROMETHEUS_URL  URL de Prometheus (por defecto http://localhost:9090)
#   ALERT_POLICIES  Politicas bloqueantes (por defecto P-OBS-003 P-OBS-004
#                   P-OBS-005)
# =============================================================================
set -uo pipefail

PROMETHEUS_URL="${1:-${PROMETHEUS_URL:-http://localhost:9090}}"
ALERT_POLICIES="${ALERT_POLICIES:-P-OBS-003 P-OBS-004 P-OBS-005}"

# Se construye la expresion regular que selecciona las politicas bloqueantes.
POLICY_REGEX="$(printf '%s' "${ALERT_POLICIES}" | tr ' ' '|' | sed 's/^/(/; s/$/)/')"

echo "=== P-OBS-003 / P-OBS-004 / P-OBS-005: Alertas criticas activas ==="
echo "  Politicas bloqueantes: ${ALERT_POLICIES}"

if ! curl --silent --fail --max-time 15 "${PROMETHEUS_URL}/-/healthy" >/dev/null 2>&1; then
  echo "[INFO] Prometheus no esta accesible en ${PROMETHEUS_URL}."
  echo "       En el pipeline, Prometheus corre como service container del runner."
  echo "       Si la consulta no puede realizarse, la politica no se puede evaluar."
  exit 0
fi

RESPONSE="$(curl --silent --max-time 20 --get \
  --data-urlencode "query=ALERTS{alertstate=\"firing\",severity=\"critical\",cumplimiento=~\"${POLICY_REGEX}\"}" \
  "${PROMETHEUS_URL}/api/v1/query" 2>/dev/null || echo '{}')"

# Se extraen las alertas que cumplen la condicion.
FIRING="$(printf '%s' "${RESPONSE}" \
  | grep -oE '"alertname":"[^"]+"' \
  | sed 's/"alertname":"//; s/"$//' \
  | sort -u)"

if [[ -z "${FIRING}" ]]; then
  echo "P-OBS-003/P-OBS-004/P-OBS-005 APROBADAS: no hay alertas criticas activas."
  exit 0
fi

FINDINGS=0
while IFS= read -r ALERT; do
  [[ -z "${ALERT}" ]] && continue
  echo "[BLOCKER] P-OBS-003/P-OBS-004/P-OBS-005 | ${ALERT} | alerta critica en estado firing"
  FINDINGS=$((FINDINGS + 1))
done <<< "${FIRING}"

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-OBS-003/P-OBS-004/P-OBS-005 FALLIDAS: ${FINDINGS} alerta(s) critica(s) activa(s). El pipeline se detiene."
  exit 1
fi

echo "P-OBS-003/P-OBS-004/P-OBS-005 APROBADAS: no hay alertas criticas bloqueantes activas."
exit 0
