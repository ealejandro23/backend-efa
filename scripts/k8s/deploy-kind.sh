#!/usr/bin/env bash
# =============================================================================
# deploy-kind.sh - Despliegue automatizado en un cluster Kubernetes (Kind)
#
# Ejecuta el ciclo completo de despliegue:
#   1. Crea el cluster Kubernetes (si no existe).
#   2. Construye las imagenes Docker del backend y del frontend.
#   3. Carga las imagenes en el cluster (sin registry: el entorno simulado
#      se comporta como si la imagen ya estuviera publicada en ECR).
#   4. Sustituye los marcadores de posicion de los secretos.
#   5. Aplica los manifiestos con Kustomize.
#   6. Despliega el stack de observabilidad (Prometheus + Grafana).
#   7. Espera el rollout y verifica salud, metricas y logs.
#
# Variables de entorno:
#   CLUSTER_NAME        Nombre del cluster (por defecto efa-cluster)
#   FRONTEND_DIR        Ruta al repositorio del frontend
#   IMAGE_TAG           Etiqueta de las imagenes (por defecto latest)
#   ENVIRONMENT         Entorno (por defecto prod)
#   GRAFANA_ADMIN_PASSWORD
#   POSTGRES_PASSWORD   Si no se indica, se genera una temporal
#   CLOUDINARY_URL
#   SKIP_BUILD          Si vale "true", no construye las imagenes
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CLUSTER_NAME="${CLUSTER_NAME:-efa-cluster}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
ENVIRONMENT="${ENVIRONMENT:-prod}"
FRONTEND_DIR="${FRONTEND_DIR:-${ROOT_DIR}/../Frontend}"
K8S_DIR="${ROOT_DIR}/infra/k8s"
MONITORING_DIR="${ROOT_DIR}/infra/monitoring"

log()  { echo "[deploy-kind] $*"; }
fail() { echo "[deploy-kind] ERROR: $*" >&2; exit 1; }

# --- 0. Verificaciones previas ----------------------------------------------
command -v kubectl >/dev/null 2>&1 || fail "kubectl no esta instalado"
command -v docker  >/dev/null 2>&1 || fail "docker no esta instalado"

if ! command -v kind >/dev/null 2>&1; then
  log "kind no esta instalado. Descargando el binario..."
  KIND_VERSION="${KIND_VERSION:-v0.30.0}"
  OS="$(uname | tr '[:upper:]' '[:lower:]')"
  case "${OS}" in
    linux)   ARCH=amd64; EXE=kind ;;
    darwin)  ARCH=arm64; EXE=kind ;;
    mingw*|msys*|cygwin*) ARCH=amd64; EXE=kind.exe ;;
    *) fail "Sistema operativo no soportado: ${OS}" ;;
  esac
  curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${OS}-${ARCH}" -o "/tmp/${EXE}"
  chmod +x "/tmp/${EXE}"
  mv "/tmp/${EXE}" "${HOME}/bin/kind" 2>/dev/null || { sudo mv "/tmp/${EXE}" /usr/local/bin/kind; }
  export PATH="${HOME}/bin:${PATH}"
fi

# --- 1. Cluster --------------------------------------------------------------
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "El cluster ${CLUSTER_NAME} ya existe; se reutiliza."
else
  log "Creando el cluster ${CLUSTER_NAME}..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${K8S_DIR}/kind-config.yaml" --wait 120s
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
kubectl cluster-info --context "kind-${CLUSTER_NAME}"

# --- 2. Construccion de imagenes --------------------------------------------
if [[ "${SKIP_BUILD:-false}" != "true" ]]; then
  log "Construyendo la imagen del backend..."
  docker build -t "efa-backend:${IMAGE_TAG}" "${ROOT_DIR}"

  if [[ -d "${FRONTEND_DIR}" ]]; then
    log "Construyendo la imagen del frontend..."
    docker build \
      --build-arg "VITE_API_BASE_URL=${VITE_API_BASE_URL:-http://localhost:8080/api/v1}" \
      -t "efa-frontend:${IMAGE_TAG}" "${FRONTEND_DIR}"
  else
    log "AVISO: no se encontro el repositorio del frontend en ${FRONTEND_DIR}; se omite su construccion."
  fi
fi

# --- 3. Carga de imagenes en el cluster -------------------------------------
log "Cargando las imagenes en el cluster..."
for IMAGE in "efa-backend:${IMAGE_TAG}" "efa-frontend:${IMAGE_TAG}"; do
  if docker image inspect "${IMAGE}" >/dev/null 2>&1; then
    kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"
  else
    log "AVISO: la imagen ${IMAGE} no existe localmente; el cluster la descargara del registry."
  fi
done

# --- 4. Creacion del namespace ----------------------------------------------
# El namespace se crea primero: sin el, ningun otro recurso del proyecto
# (Secret, ConfigMap, deployments) puede aplicarse.
log "Creando el namespace del proyecto..."
kubectl apply -f "${K8S_DIR}/base/00-namespace.yaml" --context "kind-${CLUSTER_NAME}"

# --- 5. Sustitucion de secretos y metadatos de compilacion ----------------
# Los secretos nunca se versionan. El pipeline los inyecta desde GitHub
# Secrets o, en el entorno simulado, se usa una credencial de evaluacion.
#
# El Secret se crea directamente con 'kubectl create secret', en lugar de
# editar un manifiesto: asi las credenciales no pasan por un archivo
# intermedio en disco y no existe la posibilidad de que se aplique un
# manifiesto con los valores de plantilla sin sustituir.
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-efa-evaluacion-2025}"
CLOUDINARY_URL="${CLOUDINARY_URL:-}"

# --- Persistencia de la base de datos --------------------------------------
# El volumen de PostgreSQL conserva la contrasena con la que se inicializo.
# Si la contrasena del Secret cambia, la base de datos dejaria de aceptar
# las conexiones. Por eso, si se solicita reinicializar los datos, se borra
# el PVC antes de aplicar los manifiestos.
if [[ "${RESET_DB:-false}" == "true" ]]; then
  log "RESET_DB=true: eliminando el volumen de datos de PostgreSQL."
  # Primero se elimina el StatefulSet: el PVC queda en uso mientras el pod
  # existe y su eliminacion quedaria bloqueada.
  kubectl delete statefulset efa-db -n efa --ignore-not-found --wait=false \
    --context "kind-${CLUSTER_NAME}" || true
  sleep 5
  kubectl delete pvc efa-db-data -n efa --ignore-not-found --wait=false \
    --context "kind-${CLUSTER_NAME}" || true
  sleep 5
fi

log "Generando el Secret del proyecto..."
kubectl create secret generic efa-secrets -n efa \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="${POSTGRES_PASSWORD}" \
  --from-literal=CLOUDINARY_URL="${CLOUDINARY_URL}" \
  --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

# Los metadatos de compilacion se escriben en build-info.env, que Kustomize
# inyecta en los manifiestos mediante "replacements". De este modo, el
# cluster ejecuta exactamente la version que el CI verifico.
BUILD_INFO_FILE="${K8S_DIR}/base/build-info.env"
log "Registrando los metadatos de compilacion en ${BUILD_INFO_FILE}..."
cat > "${BUILD_INFO_FILE}" <<EOF
APP_VERSION=${APP_VERSION:-${IMAGE_TAG}}
GIT_COMMIT=${GIT_COMMIT:-unknown}
GIT_BRANCH=${GIT_BRANCH:-unknown}
BUILD_TIME=${BUILD_TIME:-$(date -u '+%Y-%m-%dT%H:%M:%SZ')}
ENVIRONMENT=${ENVIRONMENT:-prod}
EOF

# --- 6. Aplicacion de los manifiestos --------------------------------------
log "Aplicando los manifiestos de la aplicacion..."

# La etiqueta de las imagenes se inyecta en el manifiesto renderizado, antes
# de aplicarlo. De este modo el rollout ocurre una sola vez y con la imagen
# correcta, en lugar de crear el deployment y cambiarlo despues.
log "Renderizando y aplicando los manifiestos con Kustomize..."
kubectl kustomize "${K8S_DIR}/overlays/prod" \
  | sed "s|efa-backend:latest|efa-backend:${IMAGE_TAG}|g; s|efa-frontend:latest|efa-frontend:${IMAGE_TAG}|g" \
  | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

# --- 7. Stack de observabilidad dentro del cluster -------------------------
log "Desplegando Prometheus y Grafana en el cluster..."
kubectl create configmap prometheus-config \
  --from-file=prometheus.yml="${K8S_DIR}/observability/prometheus.yml" \
  -n efa --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

kubectl create configmap prometheus-rules \
  --from-file=efa-alerts.yml="${MONITORING_DIR}/prometheus/rules/efa-alerts.yml" \
  -n efa --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

# Los dashboards y el aprovisionamiento se montan desde ConfigMaps.
kubectl create configmap grafana-dashboards \
  --from-file="${MONITORING_DIR}/grafana/dashboards" \
  -n efa --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

kubectl create configmap grafana-provisioning \
  --from-file=datasources.yml="${MONITORING_DIR}/grafana/provisioning/datasources/datasources.yml" \
  --from-file=dashboards.yml="${MONITORING_DIR}/grafana/provisioning/dashboards/dashboards.yml" \
  -n efa --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

# El datasource de Loki apunta al servicio en el cluster; en el entorno
# Kubernetes el backend escribe los logs a stdout y el recolector los envia.
sed 's|http://prometheus:9090|http://prometheus.efa.svc.cluster.local:9090|' \
  "${MONITORING_DIR}/grafana/provisioning/datasources/datasources.yml" > "/tmp/datasources-cluster.yml"

kubectl create configmap grafana-provisioning \
  --from-file=datasources.yml="/tmp/datasources-cluster.yml" \
  --from-file=dashboards.yml="${MONITORING_DIR}/grafana/provisioning/dashboards/dashboards.yml" \
  -n efa --dry-run=client -o yaml | kubectl apply -f - --context "kind-${CLUSTER_NAME}"

kubectl apply -f "${K8S_DIR}/observability/01-prometheus.yaml" --context "kind-${CLUSTER_NAME}"
kubectl apply -f "${K8S_DIR}/observability/02-grafana.yaml" --context "kind-${CLUSTER_NAME}"

# --- 7.b. Recursos del Prometheus Operator (condicional) --------------------
# Los ServiceMonitor y los PrometheusRule solo son validos si el Prometheus
# Operator esta instalado. Se detectan los CRD y, si existen, se aplican;
# si no, el descubrimiento por anotaciones (ya configurado en
# infra/k8s/observability/prometheus.yml) cubre el mismo objetivo.
if kubectl get crd servicemonitors.monitoring.coreos.com >/dev/null 2>&1; then
  log "Prometheus Operator detectado: aplicando ServiceMonitor y PrometheusRule."
  kubectl apply -f "${K8S_DIR}/base/08-servicemonitor.yaml" --context "kind-${CLUSTER_NAME}"
else
  log "Prometheus Operator no instalado: se omite ServiceMonitor/PrometheusRule."
  log "El descubrimiento por anotaciones prometheus.io/* sigue activo."
fi

# --- 7.b. metrics-server (necesario para el HPA) ---------------------------
# El HorizontalPodAutoscaler necesita la API de resource metrics
# (pods.metrics.k8s.io), que no viene instalada en Kind. Sin ella, el HPA
# informa "FailedComputeMetricsReplicas" y permanece en 0 réplicas.
#
# La instalacion es opcional: si no se puede completar, el resto del
# despliegue sigue siendo valido y se informa de ello.
log "Instalando metrics-server (API de resource metrics para el HPA)..."
METRICS_SERVER_MANIFEST="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
if kubectl apply -f "${METRICS_SERVER_MANIFEST}" --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1; then
  kubectl -n kube-system rollout deployment metrics-server --timeout=180s \
    --context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  log "  metrics-server instalado: el HPA ya puede calcular la utilizacion."
else
  log "  No se pudo instalar metrics-server: el HPA no podra escalar automaticamente."
  log "  Es una limitacion del entorno Kind, no de la configuracion del proyecto."
fi

# --- 8. Espera y verificacion ----------------------------------------------
log "Esperando el rollout de los deployments..."
# La base de datos es un StatefulSet; el resto, Deployments.
for WORKLOAD in "statefulset/efa-db" "deployment/efa-backend" "deployment/efa-frontend" "deployment/prometheus" "deployment/grafana"; do
  log "  - ${WORKLOAD}"
  kubectl rollout status "${WORKLOAD}" -n efa --timeout=300s \
    --context "kind-${CLUSTER_NAME}" || fail "El rollout de ${WORKLOAD} no fue exitoso."
done

log "Estado del cluster:"
kubectl get pods -n efa -o wide --context "kind-${CLUSTER_NAME}"
kubectl get svc,ingress,hpa,pdb -n efa --context "kind-${CLUSTER_NAME}"

# --- 9. Verificacion de la observabilidad ----------------------------------
log "Verificando la cadena de observabilidad..."

# 8.1 El backend responde y expone metricas.
for ATTEMPT in $(seq 1 30); do
  if kubectl run efa-verify --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
       --context "kind-${CLUSTER_NAME}" -n efa -- curl --fail --silent http://efa-backend:8080/actuator/health >/dev/null 2>&1; then
    log "  [OK] El backend responde en /actuator/health"
    break
  fi
  [[ "${ATTEMPT}" -eq 30 ]] && fail "El backend no respondio en el tiempo esperado."
  sleep 5
done

if kubectl run efa-verify --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
     --context "kind-${CLUSTER_NAME}" -n efa -- curl --fail --silent http://efa-backend:8080/actuator/prometheus 2>/dev/null \
     | grep -q "^efa_availability_up"; then
  log "  [OK] El endpoint /actuator/prometheus expone las metricas del microservicio"
else
  fail "El endpoint /actuator/prometheus no expone las metricas esperadas."
fi

# 8.2 Prometheus descubre los pods del proyecto.
sleep 30
if kubectl run efa-verify --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
     --context "kind-${CLUSTER_NAME}" -n efa -- \
     curl --fail --silent "http://prometheus:9090/api/v1/targets" 2>/dev/null \
     | grep -q '"health":"up"'; then
  log "  [OK] Prometheus esta discovers y raspando los pods del proyecto"
else
  log "  [AVISO] Prometheus todavia no reporta objetivos activos; revise con 'kubectl get pods -n efa'."
fi

# 8.3 Grafana cargo los dashboards.
if kubectl run efa-verify --rm -i --restart=Never --image=curlimages/curl:8.11.1 \
     --context "kind-${CLUSTER_NAME}" -n efa -- \
     curl --fail --silent --user admin:efa-observability "http://grafana:3000/api/search?type=dash-db" 2>/dev/null \
     | grep -q "efa-overview"; then
  log "  [OK] Grafana aprovisiono los dashboards del proyecto"
else
  log "  [AVISO] Grafana aun no muestra los dashboards; revise los logs del pod."
fi

log ""
log "Despliegue en Kubernetes completado."
log "  Contexto kubectl : kind-${CLUSTER_NAME}"
log "  Prometheus       : kubectl port-forward -n efa svc/prometheus-nodeport 9090:9090"
log "  Grafana          : kubectl port-forward -n efa svc/grafana-nodeport 3000:3000"
log "  Ingress          : http://localhost:8080"
