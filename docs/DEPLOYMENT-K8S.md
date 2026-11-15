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

## 7. Actualización a un cloud real

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

## 8. Evidencia de la evaluación

Las capturas y salidas de la ejecución verificada se encuentran en
`evidencias/` y en `docs/EVIDENCIAS.md`.
