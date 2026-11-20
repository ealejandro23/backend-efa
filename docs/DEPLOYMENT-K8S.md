# Despliegue en Kubernetes (entorno orquestado)

Este documento describe el despliegue del microservicio EFA en un entorno
orquestado, cómo se integra la observabilidad de forma automatizada en ese
entorno y qué decisiones de diseño sustentan la solución.

> **Indicador de logro cubierto:** IL3.1 / IE2 (despliegue en entornos
> orquestados con monitoring, trazabilidad y observabilidad automatizados).

---

## 1. Elección del entorno

El requisito es desplegar en un entorno orquestado **en alguna nube de
preferencia**. La decisión se tomó siguiendo tres criterios:

| Criterio | Alternativas consideradas | Elección |
|---|---|---|
| Reproducibilidad de la evaluación | AWS EKS, GCP GKE, Azure AKS | **Kind** (Kubernetes real sobre Docker) |
| Costo | Clusters gestionados (gratis con cupones, pero con registro y límites) | Sin costo, sin cuenta, sin límites |
| Fidelidad del comportamiento | Docker Compose (sin scheduler, sin sondas, sin HPA) | Scheduler, sondas, HPA, PDB y NetworkPolicy reales |

**Kind** ([kind.sigs.k8s.io](https://kind.sigs.k8s.io)) crea un cluster de
Kubernetes **real**: el mismo `kube-apiserver`, el mismo `kube-scheduler`,
el mismo `kubelet` y los mismos `controller-manager` que en EKS, GKE o AKS.
No es una simulación: los pods se programan, las sondas se ejecutan, el
autoscaling responde y las `NetworkPolicy` se aplican.

La consecuencia práctica es que **los manifiestos de este proyecto son los
mismos que se desplegarían en un cloud real**. Cambiar de Kind a EKS
implica únicamente cambiar el contexto de `kubectl` y la autenticación:

```bash
# Entorno de evaluación (Kind)
kubectl config use-context kind-efa-cluster

# Entorno productive (EKS)
aws eks update-kubeconfig --name efa-cluster --region us-east-1
kubectl apply -k infra/k8s/overlays/prod     # <- los mismos manifiestos
```

---

## 2. Estructura de los manifiestos

```
infra/k8s/
├── base/                        # Configuración común a todos los entornos
│   ├── 00-namespace.yaml        # Namespace, ResourceQuota y LimitRange
│   ├── 01-rbac.yaml             # Cuentas de servicio y permisos mínimos
│   ├── 02-config.yaml           # ConfigMap + plantilla de Secret
│   ├── 03-postgres.yaml         # StatefulSet, Service y PVC de PostgreSQL
│   ├── 04-backend.yaml          # Deployment, Service, PDB y HPA del backend
│   ├── 05-frontend.yaml         # Deployment, Service y PDB del frontend
│   ├── 06-ingress.yaml          # Ingress (frontend + /api + /actuator)
│   ├── 07-networkpolicy.yaml    # Control de tráfico entre pods
│   ├── 08-servicemonitor.yaml  # ServiceMonitor y PrometheusRule
│   ├── build-info.env           # Metadatos de compilación (inyectados)
│   └── kustomization.yaml       # Base de Kustomize + replacements
├── overlays/
│   └── prod/                    # Particularidades del entorno de producción
│       └── kustomization.yaml
├── observability/               # Prometheus y Grafana dentro del cluster
│   ├── 01-prometheus.yaml
│   ├── 02-grafana.yaml
│   └── prometheus.yml
└── kind-config.yaml             # Configuración del cluster de evaluación
```

Se usa **Kustomize** (integrado en `kubectl`, sin dependencias adicionales)
en lugar de Helm porque la evaluación no requiere versionar plantillas de
chart, y Kustomize permite el mecanismo de `replacements`, que resulta más
directo para inyectar los metadatos de compilación.

---

## 3. Componentes desplegados

| Componente | Tipo | Réplicas | Función |
|---|---|---|---|
| `efa-db` | StatefulSet | 1 | PostgreSQL 16 con volumen persistente. |
| `efa-backend` | Deployment | 2 (3 en prod) | Microservicio Spring Boot. |
| `efa-frontend` | Deployment | 2 | nginx sirviendo la SPA con métricas. |
| `prometheus` | Deployment | 1 | Recolección de métricas y evaluación de alertas. |
| `grafana` | Deployment | 1 | Dashboards y exploración de logs. |
| `efa-ingress` | Ingress | — | Punto de entrada único. |

### Decisiones de disponibilidad

- **`maxUnavailable: 0` / `maxSurge: 1`** en el `RollingUpdate`: durante un
  despliegue nunca hay menos de las réplicas esperadas. Sin esta opción,
  Kubernetes podría eliminar la última réplica sana antes de que la nueva
  estuviera lista, provocando una caída total del servicio.
- **`startupProbe`**: da al proceso hasta 150 s para arrancar. Sin ella, la
  `livenessProbe` mataría el contenedor durante el arranque en frío (que en
  Spring Boot con JVM y conexión a la base de datos puede tardar).
- **`preStop: sleep 10`**: al retirar un pod, el endpoint de readiness deja
  de responder de inmediato, pero el contenedor sigue 10 s más aceptando
  conexiones para terminar las peticiones en curso.
- **`PodDisruptionBudget` con `minAvailable: 1`**: impide que una
  evacuación programada (por ejemplo, el mantenimiento de un nodo) deje el
  servicio sin ninguna réplica.
- **`topologySpreadConstraints`**: reparte las réplicas entre nodos. En un
  cluster de un solo nodo no tiene efecto, pero es lo que evita que una
  caída de nodo se lleve todas las réplicas.
- **`graceful shutdown`**: `server.shutdown=graceful` en el perfil `prod`
  hace que Spring Boot deje de aceptar peticiones nuevas y termine las que
  están en curso antes de cerrar.

---

## 4. Integración de la observabilidad en el despliegue

El punto clave de IE2 es que **la observabilidad no es una configuración
posterior al despliegue: se integra en el propio manifiesto**, de modo que
es imposible desplegar sin ella.

### 4.1 Descubrimiento de métricas por anotaciones

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/actuator/prometheus"
  prometheus.io/port: "8080"
  efa.io/commit: "..."      # inyectado por Kustomize
  efa.io/branch: "..."
  efa.io/build-time: "..."
```

Prometheus usa `kubernetes_sd_configs` con el rol `pod` y **solo** recolecta
los pods que declaran `prometheus.io/scrape: "true"`. No hay una lista de
destinos mantenida a mano: un pod nuevo se instrumenta solo por estar en el
manifiesto.

La etiqueta `efa.io/commit` se añade como *relabel* en Prometheus, de modo
que cada serie de métricas queda asociada al commit que la produjo. Eso
permide comparar el comportamiento de dos versiones sin bloquear
despliegues.

### 4.2 Prometheus dentro del cluster

`infra/k8s/observability/` despliega Prometheus con una `ClusterRole` que le
permite descubrir servicios y pods, y Grafana con los dashboards
aprovisionados desde ConfigMaps que el script genera a partir de los
archivos del repositorio. Los dashboards en el cluster son **exactamente los
mismos** que en el entorno local: no hay dos versiones que mantener.

Las reglas de alerta se replican en el cluster como `PrometheusRule`
(recurso del Prometheus Operator) para que funcionen tanto con Operator
como con el descubrimiento por `kubernetes_sd_configs`.

### 4.3 Logs

Los pods escriben en `stdout`/`stderr`. En el cluster, el recolector es un
`DaemonSet` de Grafana Alloy (`alloy-config.kubernetes.alloy`) que lee los
logs de la API de Kubernetes y los envía a Loki, etiquetándolos con los
metadatos reales del pod (namespace, deployment, app, versión).

### 4.4 Trazabilidad del despliegue

El `ConfigMap` `efa-build-info` se genera a partir de `build-info.env`, que
el pipeline reescribe en cada despliegue. Kustomize lo inyecta, mediante
`replacements`, en:

- las etiquetas `app.kubernetes.io/version` de los pods,
- las anotaciones `efa.io/commit`, `efa.io/branch` y `efa.io/build-time`,
- los valores `APP_VERSION`, `GIT_COMMIT`, `GIT_BRANCH` y `BUILD_TIME` del
  `ConfigMap` `efa-config`.

El resultado es que **el microservicio, sus métricas y sus logs reportan el
mismo commit**, y ese commit es exactamente el que pasó el gate de
cumplimiento.

### 4.5 Seguridad del despliegue

- `runAsNonRoot: true` con UID y GID explícitos.
- `seccompProfile: RuntimeDefault`.
- `allowPrivilegeEscalation: false` y `drop: ["ALL"]` en las capabilities.
- `automountServiceAccountToken: false` en el microservicio: no necesita
  hablar con la API de Kubernetes.
- `readOnlyRootFilesystem` en los contenedores que no escriben en disco.
- `ResourceQuota` y `LimitRange` a nivel de namespace.
- `PodSecurity Admission` en modo `enforce: restricted` sobre el namespace.
- `NetworkPolicy` con denegación por defecto: solo el frontend puede llamar
  al backend, y solo el backend puede llamar a la base de datos.

---

## 5. Despliegue automatizado

El script `scripts/k8s/deploy-kind.sh` ejecuta el ciclo completo y es el
mismo que invoca el pipeline:

```bash
# 1. Crear el cluster (si no existe)
kind create cluster --name efa-cluster --config infra/k8s/kind-config.yaml

# 2. Construir las imagenes
docker build -t efa-backend:latest .
docker build -t efa-frontend:latest ../Frontend

# 3. Cargarlas en el cluster
kind load docker-image efa-backend:latest --name efa-cluster

# 4. Sustituir secretos y metadatos de compilacion
#    (los secretos vienen de GitHub Secrets; los metadatos, del commit)

# 5. Aplicar los manifiestos
kubectl apply -k infra/k8s/overlays/prod

# 6. Desplegar Prometheus y Grafana con los dashboards versionados

# 7. Verificar la cadena de observabilidad
```

### Verificación que ejecuta el script

El script no se limita a aplicar manifiestos: **verifica que la
observabilidad funciona** y falla si no es así.

| Verificación | Qué demuestra |
|---|---|
| `/actuator/health` responde `UP` | El microservicio está operativo en el cluster. |
| `/actuator/prometheus` expone `efa_availability_up` | El microservicio está instrumentado y publica sus métricas. |
| Prometheus reporta objetivos con `"health":"up"` | El descubrimiento automático funciona: Prometheus encuentra los pods por anotación. |
| Grafana responde con el dashboard `efa-overview` | El aprovisionamiento de dashboards funciona dentro del cluster. |

### Ejecución manual

```bash
FRONTEND_DIR=../Frontend IMAGE_TAG=latest bash scripts/k8s/deploy-kind.sh
```

### Acceso a los servicios

```bash
# Prometheus
kubectl port-forward -n efa svc/prometheus-nodeport 9090:9090

# Grafana (admin / efa-observability)
kubectl port-forward -n efa svc/grafana-nodeport 3000:3000

# Ingress
# http://localhost:8080  (mapeado en kind-config.yaml)
```

---

## 6. Verificación desde el cluster

```bash
# Estado de los recursos
kubectl get pods,svc,ingress,hpa,pdb -n efa

# Sondas y estado de los pods
kubectl describe pod -n efa -l app.kubernetes.io/name=efa-backend

# Historial de eventos (detecta por qué un pod no arranca)
kubectl get events -n efa --sort-by=.lastTimestamp

# Métricas vivas desde el propio cluster
kubectl exec -n efa deploy/efa-backend -- \
  wget -qO- http://localhost:8080/actuator/prometheus | grep '^efa_'

# Objetivos descubiertos por Prometheus
kubectl exec -n efa deploy/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/targets'
```

---

## 7. Despliegue verificado en AWS (EC2 + Kind)

El cluster del pipeline (job «Deploy en Kubernetes (kind)» de
`compliance.yml`) vive solo mientras corre el runner. Para cumplir con un
entorno orquestado **en la nube** y poder observarlo de forma continua, el
mismo despliegue se ejecutó en una instancia EC2 de AWS (cuenta AWS Academy
Learner Lab, región `us-east-1`).

### 7.1 Por qué EC2 + Kind y no EKS

| Criterio | EKS | EC2 + Kind |
|---|---|---|
| Disponibilidad en Learner Lab | Restringido: no se pueden crear los roles IAM que exige EKS. | Disponible con `LabInstanceProfile`. |
| Costo | Plano de control (~US$0,10/h) + nodos. | Una `t3.large` (~US$0,08/h). |
| Cambios en el proyecto | Ninguno en los manifiestos (ver §8). | **Ninguno**: se reutiliza `scripts/k8s/deploy-kind.sh`, el mismo que valida el pipeline. |

Kind ejecuta los componentes reales de Kubernetes (API server, scheduler,
kubelet, etcd), de modo que las sondas, el HPA, los PDB y las NetworkPolicy
se comportan igual que en un cluster gestionado.

### 7.2 Infraestructura creada (desde AWS CloudShell)

| Recurso | Valor | Seguridad |
|---|---|---|
| Instancia EC2 | `efa-k8s`, `t3.large` (2 vCPU, 8 GiB), Ubuntu 24.04, disco gp3 de 30 GiB | Tag `Project=EFA-EP3` |
| Security Group | `efa-k8s-sg` | SSH (22) solo desde la IP de CloudShell; Grafana (30090), Prometheus (30093) y app (8080) solo desde la IP del equipo. Nada abierto a `0.0.0.0/0`. |
| Llave SSH | `efa-k8s-key` (ed25519) | Guardada solo en CloudShell. |

La instancia se aprovisiona con *user-data*: instala Docker, Kind y kubectl,
clona el backend y el frontend y ejecuta `deploy-kind.sh`.

### 7.3 Problemas encontrados y cómo se resolvieron

El despliegue en un nodo de 2 vCPU expuso defectos que el runner de GitHub
(4 vCPU) no mostraba:

| Síntoma | Causa | Solución |
|---|---|---|
| `efa-db-0` y `prometheus` en `Pending`: `0/1 nodes are available: 1 Insufficient cpu`. El backend en `CrashLoopBackOff` (sin base de datos). | Las *requests* sumaban ~2150m de CPU sobre 2000m disponibles. | Backend y frontend a 1 réplica; `minReplicas: 1` en el HPA. |
| Un `rollout restart` del backend quedaba en `Pending`. | El *rolling update* crea el pod nuevo antes de borrar el viejo y no había CPU para ambos. | `maxSurge: 0, maxUnavailable: 1` en el nodo de capacidad limitada. |
| Grafana y Prometheus respondían `HTTP 000` en los NodePort. | `efa-default-deny` bloqueaba también el tráfico de entrada a las interfaces web. | NetworkPolicy `efa-allow-dashboards-ingress` (puertos 3000 y 9090). Quién entra se controla en el Security Group. |
| Target `cadvisor` (CPU/memoria) y `kubernetes-apiservers` en `down`. | (1) Prometheus no tenía permitido salir hacia la IP del nodo; (2) no enviaba el token de su ServiceAccount al kubelet. | NetworkPolicy `efa-allow-prometheus-to-nodes` (puertos 10250 y 6443) y `authorization.credentials_file` en `prometheus.yml`. |
| Todos los paneles de Grafana con «No data» y error. | `default deny` bloqueaba el DNS a Grafana: no resolvía `prometheus.efa.svc.cluster.local`. | NetworkPolicy `efa-allow-monitoring-dns` (solo puerto 53 hacia `kube-dns`). |
| Paneles vacíos con el filtro «All». | Las variables del dashboard sin `allValue` generaban `environment=~""`. | `allValue: ".*"` en las variables. |
| «Disponibilidad (SLO 99%)» en 0 %. | La fórmula calculaba `1 - (ok/total)`, es decir, la tasa de error. | Fórmula corregida a `ok/total`. |
| «Versión desplegada» mostraba `latest / unknown`. | El script no recibía `GIT_COMMIT` (`git` rechazó el repositorio por *dubious ownership*; en el pipeline la variable no se pasaba). | Etiqueta y anotación del pod con el commit; `GIT_COMMIT` y `GIT_BRANCH` agregados al job de Kubernetes en `compliance.yml`. |
| Pod del Pushgateway rechazado. | El `LimitRange` del namespace exige mínimo 50m de CPU y 128Mi por contenedor. | Recursos del Pushgateway ajustados a la política. |

### 7.4 Métricas del pipeline en el cluster

En GitHub Actions el Pushgateway es un *service container* que desaparece al
terminar el job, por lo que las métricas del pipeline no persistían. En el
cluster de AWS se desplegó un Pushgateway persistente
(`infra/k8s/observability/03-pushgateway.yaml`) y un recolector
(`scripts/ci/collect-pipeline-metrics.sh`) que reconstruye las métricas
desde sus fuentes oficiales: la API de GitHub Actions (build, etapas,
despliegues, políticas de cumplimiento, protección de rama) y la API de
SonarCloud (cobertura y Quality Gate). Un `cron` en la EC2 lo ejecuta cada
10 minutos.

### 7.5 Resultado verificado

```console
$ kubectl get pods -n efa
efa-backend-...    1/1  Running
efa-db-0           1/1  Running
efa-frontend-...   2/2  Running
grafana-...        1/1  Running
prometheus-...     1/1  Running
pushgateway-...    1/1  Running

Prometheus targets: cadvisor, efa-backend-k8s, efa-frontend-k8s,
                    kubernetes-apiservers, prometheus, pushgateway -> up
Version desplegada (efa_deploy_info): 10eba1d / 10eba1d
Metricas del pipeline: build_success=1, cobertura=0.918,
                       duracion del despliegue=142 s, politicas aprobadas=12
```

### 7.6 Costos y apagado

La sesión del Learner Lab detiene la instancia al terminar; al reiniciarla
cambia la IP pública. Para eliminar todo al cerrar la evaluación:

```bash
source ~/efa-env.sh
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
aws ec2 delete-security-group --group-id "$SG_ID"
aws ec2 delete-key-pair --key-name efa-k8s-key
```

---

## 8. Actualización a un cluster gestionado (EKS)

El cambio de Kind a un cluster gestionado no requiere modificar los
manifiestos. Los pasos son:

1. **Provisionar el cluster.**
   ```bash
   aws eks create-cluster --name efa-cluster --region us-east-1 \
     --kubernetes-version 1.32 --nodegroup-name efa-nodes \
     --node-type t3.medium --scaling-config-minSize 2 --scaling-config-maxSize 4
   aws eks update-kubeconfig --name efa-cluster --region us-east-1
   ```

2. **Instalar el ingress controller y el stack de observabilidad.**
   ```bash
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
   ```

3. **Publicar las imágenes en el registro de la nube.**
   ```bash
   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <registro>.dkr.ecr.us-east-1.amazonaws.com
   docker tag efa-backend:latest <registro>.dkr.ecr.us-east-1.amazonaws.com/efa-backend:<sha>
   docker push <registro>.dkr.ecr.us-east-1.amazonaws.com/efa-backend:<sha>
   ```

4. **Ajustar la imagen y el Secret.**
   ```bash
   kubectl set image deployment/efa-backend backend=<registro>.dkr.ecr.us-east-1.amazonaws.com/efa-backend:<sha> -n efa
   kubectl create secret generic efa-secrets -n efa \
     --from-literal=POSTGRES_PASSWORD=... --from-literal=CLOUDINARY_URL=...
   ```

5. **Desplegar.**
   ```bash
   kubectl apply -k infra/k8s/overlays/prod
   ```

El workflow `deploy.yml` ya conserva los pasos de autenticación en AWS y de
publicación en Amazon ECR; solo hay que desactivar `DEMO_MODE`.

---

## 9. Evidencia de la evaluación

Las capturas y salidas de la ejecución verificada se encuentran en
`evidencias/` y en `docs/EVIDENCIAS.md`.
