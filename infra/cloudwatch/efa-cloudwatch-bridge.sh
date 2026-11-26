#!/usr/bin/env bash
# =============================================================================
# efa-cloudwatch-bridge.sh - Metricas de la aplicacion hacia AWS CloudWatch
#
# Se ejecuta cada minuto (cron) en la EC2. Consulta a Prometheus (que ya
# recoge las metricas del backend en el cluster) y al cluster de Kubernetes,
# y envia los valores al agente de CloudWatch por StatsD (127.0.0.1:8125).
# El agente los publica en el namespace "EFA/EC2" junto con CPU, memoria y
# disco de la instancia.
#
# Metricas publicadas:
#   efa_backend_disponible        1 si el backend responde, 0 si no
#   efa_peticiones_por_minuto     peticiones HTTP por minuto
#   efa_errores_4xx_por_minuto    respuestas 4xx por minuto
#   efa_errores_5xx_por_minuto    respuestas 5xx por minuto
#   efa_latencia_p95_ms           latencia p95 en milisegundos
#   efa_pods_running              pods en estado Running en el namespace efa
# =============================================================================
set -uo pipefail

PROM="${PROMETHEUS_URL:-http://localhost:30093}"
JOB='job=~"efa-backend.*"'

# consulta EXPRESION -> imprime el valor numerico (0 si no hay datos)
consulta() {
  curl -s --max-time 10 -G "${PROM}/api/v1/query" --data-urlencode "query=$1" \
    | python3 -c 'import json,sys,math
try:
    r = json.load(sys.stdin)["data"]["result"]
    v = float(r[0]["value"][1]) if r else 0.0
    print(0 if math.isnan(v) or math.isinf(v) else round(v, 3))
except Exception:
    print(0)'
}

# gauge NOMBRE VALOR -> envia una metrica tipo gauge al agente
gauge() {
  printf '%s:%s|g' "$1" "$2" > /dev/udp/127.0.0.1/8125
}

DISPONIBLE="$(consulta "max(up{${JOB}})")"
PETICIONES="$(consulta "sum(rate(http_server_requests_seconds_count{${JOB}}[5m])) * 60")"
E4XX="$(consulta "sum(rate(http_server_requests_seconds_count{${JOB},status=~\"4..\"}[5m])) * 60")"
E5XX="$(consulta "sum(rate(http_server_requests_seconds_count{${JOB},status=~\"5..\"}[5m])) * 60")"
P95="$(consulta "histogram_quantile(0.95, sum by (le) (rate(http_server_requests_seconds_bucket{${JOB}}[5m]))) * 1000")"
PODS="$(kubectl get pods -n efa --no-headers 2>/dev/null | grep -c ' Running ' || true)"

gauge efa_backend_disponible "${DISPONIBLE}"
gauge efa_peticiones_por_minuto "${PETICIONES}"
gauge efa_errores_4xx_por_minuto "${E4XX}"
gauge efa_errores_5xx_por_minuto "${E5XX}"
gauge efa_latencia_p95_ms "${P95}"
gauge efa_pods_running "${PODS:-0}"

echo "$(date -u +%FT%TZ) disponible=${DISPONIBLE} rpm=${PETICIONES} 4xx=${E4XX} 5xx=${E5XX} p95_ms=${P95} pods=${PODS:-0}"
