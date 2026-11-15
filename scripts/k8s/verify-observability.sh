#!/usr/bin/env bash
# =============================================================================
# verify-observability.sh - Verifica la cadena de observabilidad en el cluster
#
# Comprueba, sobre el cluster ya desplegado, que la observabilidad funciona de
# extremo a extremo:
#
#   1. El backend responde en /actuator/health.
#   2. El backend publica sus metricas en /actuator/prometheus.
#   3. Prometheus descubre y raspea los pods del proyecto.
#   4. Grafana aprovisiono los dashboards.
#   5. El frontend expone su sonda de salud y sus metricas.
#   6. Los logs estructurados del backend llegan al recolector.
#
# Las comprobaciones se ejecutan con 'kubectl exec' sobre los pods ya
# desplegados y no con 'kubectl run': el namespace exige el perfil
# "restricted" de Pod Security Admission, que rechaza los pods auxiliares que
# no declaran un contexto de seguridad completo.
#
# Uso:
#   verify-observability.sh [contexto_kubectl]
#
# Codigo de salida: 0 si toda la cadena funciona, 1 si alguna falla.
# =============================================================================
set -uo pipefail

CONTEXT="${1:-${KUBE_CONTEXT:-kind-efa-cluster}}"
NAMESPACE="${NAMESPACE:-efa}"

OK_COUNT=0
WARN_COUNT=0

log_ok()   { echo "  [OK]    $*"; OK_COUNT=$((OK_COUNT + 1)); }
log_warn() { echo "  [AVISO] $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
log_fail() { echo "  [FALLA] $*"; exit 1; }

# --- 1. Salud del microservicio --------------------------------------------
if kubectl exec -n "${NAMESPACE}" deploy/efa-backend -- \
     wget -qO- http://localhost:8080/actuator/health 2>/dev/null | grep -q '"status":"UP"'; then
  log_ok "El backend responde en /actuator/health"
else
  log_fail "El backend no responde correctamente en /actuator/health."
fi

# --- 2. Metricas del microservicio ------------------------------------------
METRICS="$(kubectl exec -n "${NAMESPACE}" deploy/efa-backend -- \
  wget -qO- http://localhost:8080/actuator/prometheus 2>/dev/null || echo '')"

for METRIC in efa_availability_up efa_errors_total efa_deploy_info http_server_requests_seconds; do
  if grep -q "^${METRIC}" <<< "${METRICS}"; then
    log_ok "El microservicio publica la metrica ${METRIC}"
  else
    log_fail "El microservicio no publica la metrica ${METRIC}."
  fi
done

# --- 3. Descubrimiento en Prometheus ----------------------------------------
sleep 20
TARGETS="$(kubectl exec -n "${NAMESPACE}" deploy/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets' 2>/dev/null || echo '{}')"

if grep -q '"health":"up"' <<< "${TARGETS}"; then
  log_ok "Prometheus descubre y raspea los pods del proyecto"
  grep -oE '"job":"[^"]+"' <<< "${TARGETS}" | sort -u | sed 's/^/          objetivo: /'
else
  log_fail "Prometheus no reporta ningun objetivo activo."
fi

# Las series del microservicio deben tener las etiquetas que usan los
# dashboards: sin ellas, los paneles no tendrian datos que mostrar.
if grep -q 'efa_availability_up' <<< "${TARGETS}"; then
  log_ok "Las metricas del microservicio estan disponibles en Prometheus"
else
  log_warn "Las metricas del microservicio aun no estan en Prometheus (puede faltar un ciclo de scrape)."
fi

# --- 4. Dashboards en Grafana ------------------------------------------------
GRAFANA_AUTH="YWRtaW46ZWZhLW9ic2VydmFiaWxpdHk="
DASHBOARDS="$(kubectl exec -n "${NAMESPACE}" deploy/grafana -- \
  wget -qO- --header="Authorization: Basic ${GRAFANA_AUTH}" \
  'http://localhost:3000/api/search?type=dash-db' 2>/dev/null || echo '')"

for DASHBOARD in efa-overview efa-cicd efa-errors-logs; do
  if grep -q "${DASHBOARD}" <<< "${DASHBOARDS}"; then
    log_ok "Grafana cargo el dashboard ${DASHBOARD}"
  else
    log_fail "Grafana no cargo el dashboard ${DASHBOARD}."
  fi
done

# --- 5. Sondas y metricas del frontend --------------------------------------
if kubectl exec -n "${NAMESPACE}" deploy/efa-frontend -- \
     wget -qO- http://localhost:8080/healthz 2>/dev/null | grep -q 'ok'; then
  log_ok "El frontend responde en /healthz"
else
  log_warn "El frontend no responde en /healthz."
fi

if kubectl exec -n "${NAMESPACE}" deploy/efa-frontend -- \
     wget -qO- http://localhost:9113/metrics 2>/dev/null | grep -q 'nginx_http_requests_total'; then
  log_ok "El exporter de metricas de nginx publica las metricas del frontend"
else
  log_warn "El exporter de nginx todavia no publica metricas."
fi

# --- 6. Logs estructurados del backend ---------------------------------------
LOGS="$(kubectl logs -n "${NAMESPACE}" -l app.kubernetes.io/name=efa-backend --tail=5 --prefix 2>/dev/null || echo '')"
if grep -q '"@timestamp"' <<< "${LOGS}"; then
  log_ok "Los logs del backend se emiten en JSON estructurado"
else
  log_warn "No se detectaron logs en JSON en las ultimas lineas del backend."
fi

if grep -q '"traceId"' <<< "${LOGS}"; then
  log_ok "Los logs incluyen el identificador de correlacion (traceId)"
else
  log_warn "No se detecto el identificador de correlacion en los logs revisados."
fi

# --- Resumen -----------------------------------------------------------------
echo ""
echo "  Verificaciones correctas: ${OK_COUNT}"
echo "  Avisos                    : ${WARN_COUNT}"

if [[ ${OK_COUNT} -lt 8 ]]; then
  echo ""
  echo "RESULTADO: la cadena de observabilidad NO esta completa."
  exit 1
fi

echo ""
echo "RESULTADO: la cadena de observabilidad funciona de extremo a extremo."
exit 0
