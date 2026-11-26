# Registro de decisiones técnicas (ADR)

Cada entrada documenta una decisión de diseño relevante del proyecto: qué
se decidió, qué alternativas se consideraron, por qué se eligió esa y qué
consecuencia tiene. El formato sigue la estructura habitual de un ADR
(*Architecture Decision Record*).

---

## ADR-001 — Stack de observabilidad sobre la familia Prometheus + Grafana

**Estado:** aceptada
**Contexto:** el proyecto debe instrumentar logs, métricas de uso, errores y
disponibilidad del microservicio, y construir dashboards con métricas de
despliegue, cobertura, CPU/memoria y errores.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| Datadog / New Relic (SaaS) | Integración lista, panel prearmado. | Requiere cuenta y clave de API; no se puede verificar de forma autónoma ni auditar el código. |
| ELK (Elasticsearch + Logstash + Kibana) | Potente para buscar logs. | Muy pesado para un proyecto académico; 3 servicios más que mantener. |
| **Prometheus + Grafana + Loki + Alloy** | Código abierto, autocontenido en Docker, API abierta y auditable, secretos de Prometheus bien establecidos, dashboards en JSON versionable. | Hay que configurar el descubrimiento y el formato de logs. |

**Decisión:** Prometheus + Grafana + Loki + Grafana Alloy + Pushgateway.

**Consecuencias:**
- Todo el stack se levanta con `docker compose` sin cuentas ni claves externas.
- Los dashboards son archivos JSON versionados: se revisan en un Pull
  Request como cualquier otro cambio.
- Se asume el coste de configurar el descubrimiento de pods por
  anotaciones y de emitir los logs en JSON.

---

## ADR-002 — El actuator comparte el puerto con el servicio

**Estado:** aceptada
**Contexto:** Spring Boot permite mover los endpoints de gestión a un puerto
separado (`management.server.port`). Es la práctica recomendada para
aislar la superficie de administración.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| **Puerto de gestión separado (8081)** | Aislamiento real de la superficie de administración. | Rompe los healthchecks existentes de Docker Compose, del CD y obliga a cambiar las sondas de Kubernetes y los endpoints del Ingress. Añade un puerto que mantener. |
| **Mismo puerto, lista blanca de endpoints** | Un solo endpoint de salud para todos los consumidores; menos configuración; el Ingress no necesita una ruta extra. | Un atacante que alcance el puerto de negocio también alcanza `/actuator/health` y `/actuator/prometheus`. |

**Decisión:** mismo puerto, con **lista blanca explícita** de endpoints
expuestos:

```properties
management.endpoints.web.exposure.include=health,info,metrics,prometheus,caches,scheduledtasks,startup
```

Los endpoints que permiten mutar el estado (`loggers`, `shutdown`,
`refresh`) **no** se exponen. Los que sí se exponen son de solo lectura, y
además se fuerzan a `access=read-only`.

**Consecuencias:**
- Un único endpoint (`/actuator/health`) sirve al healthcheck de Compose, a
  las sondas de Kubernetes y a la verificación del CD.
- La información de salud del servicio queda accesible desde el puerto de
  negocio. Se acepta ese riesgo porque no contiene datos sensibles: el
  detalle se limita a nombre de base de datos, espacio en disco y estado de
  los componentes.
- Si en el futuro el servicio se expone a internet, esta decisión debe
  revisarse (ver «Revisión periódica»).

---

## ADR-003 — Kind como entorno orquestado de evaluación

**Estado:** aceptada
**Contexto:** el requisito es desplegar los microservicios en un entorno
orquestado en alguna nube, con monitoring, trazabilidad y observabilidad
integrados de forma automatizada.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| Docker Compose (ya usado en el proyecto) | Simple, ya conocido. | **No es un orquestador**: no hay scheduler, ni sondas, ni HPA, ni PDB, ni NetworkPolicy. La observabilidad no se integra de forma nativa. |
| AWS EKS | Cloud real. | Requiere cuenta, VPC, subredes, IAM y un clúster que cuesta dinero y tarda en crearse. El Free Tier caduca. |
| **Kind (Kubernetes sobre Docker)** | Kubernetes **real**: mismo apiserver, scheduler y kubelet. Cero costo, cero registro, arranque en minutos. Manifiestos idénticos a los de un cloud real. | No reproduce el balanceador de carga de un cloud ni la alta disponibilidad real. |

**Decisión:** Kind como entorno de evaluación, con los manifiestos escritos
para ser portables a EKS/GKE/AKS sin cambios.

**Consecuencias:**
- Los manifiestos de `infra/k8s/` son los mismos que se desplegarían en un
  cloud real; el cambio de entorno es un cambio de contexto de `kubectl`.
- El `kind-config.yaml` declara dos nodos (control-plane y worker) para
  poder verificar la distribución de réplicas.
- El Ingress se expone por `hostPort`, ya que no hay balanceador de carga
  externo.
- Se documenta explícitamente el procedimiento de migración a EKS.

---

## ADR-004 — Kustomize con `replacements` en lugar de Helm

**Estado:** aceptada
**Contexto:** el proyecto necesita parametrizar los manifiestos de
Kubernetes (versión, commit, etiqueta de imagen, host del Ingress) según el
despliegue concreto.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| **Kustomize** (integrado en `kubectl`) | Sin dependencias adicionales; `replacements` permite inyectar valores de un ConfigMap en campos arbitrarios de otros recursos, incluidas las anotaciones del pod. | Menos potente que Helm para lógica condicional. |
| Helm | Plantillas muy potentes; ecosistema amplio. | Requiere instalar Helm; las plantillas con `{{ }}` no son YAML válido, lo que impide validarlas directamente y complica la auditoría automática de los manifiestos. |
| `sed` sobre el YAML | Sin dependencias. | Frágil: un cambio de formato rompe silenciosamente el despliegue. |

**Decisión:** Kustomize, con `replacements` para inyectar los metadatos de
compilación.

**Consecuencias:**
- `infra/k8s/base/build-info.env` es la única fuente de los metadatos de
  versión; el script de despliegue la reescribe en cada ejecución.
- Los manifiestos siguen siendo YAML válido y se pueden auditar con
  `audit-kubernetes.sh` sin adaptaciones.
- La etiqueta de la imagen se inyecta en el manifiesto renderizado (con
  `sed` sobre la salida de `kubectl kustomize`), de modo que el rollout
  ocurre una sola vez con la imagen correcta.

---

## ADR-005 — Grafana Alloy en lugar de Promtail

**Estado:** aceptada
**Contexto:** el proyecto necesita recolectar los logs de los contenedores
y de los pods para indexarlos en Loki.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| **Promtail** | Configuración muy sencilla y con mucha documentación. | Está en fin de vida: Grafana ha retirado su soporte. |
| **Grafana Alloy** | Es el recolector que la propia Grafana recomienda como sustituto de Promtail; misma familia de herramientas; configuración más expresiva (etiquetado, filtrado, relabeling). | Configuración con sintaxis propia (comentarios `//`, no `#`). |
| Fluent Bit / Vector | Muy maduros, excellent rendimiento. | Otra configuración y otro ecosistema que aprender. |

**Decisión:** Grafana Alloy, con una configuración separada para Docker
Compose (`alloy-config.docker.alloy`) y otra para Kubernetes
(`alloy-config.kubernetes.alloy`, desplegada como DaemonSet).

**Consecuencias:**
- La sintaxis de Alloy no es YAML: los comentarios usan `//`. Es un detalle
  que costó una iteración y que queda documentado en el propio archivo.
- La corrección de la sintaxis fue detectada por el comando `alloy
  validate`, que se usa como verificación previa a desplegar.

---

## ADR-006 — El pipeline publica sus métricas al Pushgateway

**Estado:** aceptada
**Contexto:** el tablero de CI/CD debe mostrar la duración del despliegue, la
cobertura de pruebas y el resultado de los controles.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| **Pushgateway** | Es el modelo canónico de Prometheus para métricas que nacen y mueren dentro de un job. Pushgateway reemplaza el valor de cada serie, lo que obliga a implementar el patrón leer→incrementar→publicar para los contadores. | La API es de reemplazo, no de acumulación. |
| Exponer un endpoint del runner y scrapearlo | Modelo push puro. | El runner de GitHub Actions es efímero: cuando termina el job, el endpoint desaparece y la serie se queda "stale". |
| Enviar las métricas a Grafana Cloud | Panel listo. | Requiere cuenta y una clave de API que habría que proteger. |

**Decisión:** Pushgateway, como *service container* del runner (accesible en
`localhost:9091`).

**Consecuencias:**
- Las métricas del pipeline llegan a Prometheus por el job `pushgateway`,
  y de ahí a Grafana por el mismo camino que las del servicio. Un solo
  origen de datos.
- El contador de despliegues requiere el patrón leer→incrementar→publicar,
  documentado en `scripts/ci/publish-deploy-metrics.sh`.
- El formato de exposición exige que cada línea termine en salto de línea: un
  detalle sutil que provoca un `400` del Pushgateway si se olvida. La
  utilidad centraliza el formato en un único lugar (`publish-metrics.sh`)
  para que el error no se repita.

---

## ADR-007 — El gate de cumplimiento es una verificación obligatoria de la rama

**Estado:** aceptada
**Contexto:** el indicador IE6 exige que el pipeline se detenga ante una
falla crítica de seguridad o calidad y que el entorno productivo quede
protegido.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| Solo el CI falla (sin branch protection) | Simple. | Nada impide integrar el cambio: la protección depende de que la persona que revisa se acuerde. |
| Solo reglas de protección de rama | Obliga a pasar el CI. | Las reglas se=configuran en la interfaz de GitHub, fuera del repositorio: no se revisan ni se versionan. |
| **Gate como verificación obligatoria + reglas versionadas** | La barrera es técnica, no de procedimiento. La configuración declarada se versiona y se audita con un script. | Requiere configurar las reglas en GitHub además de mantener el archivo. |

**Decisión:** el gate de cumplimiento es una verificación obligatoria de la
rama principal, y su configuración declarada se versiona en
`.github/branch-protection.yml`. El script
`verify-branch-protection.sh` comprueba que la configuración real de GitHub
coincide con la declarada.

**Consecuencias:**
- El job del gate se llama de forma que coincida exactamente con el
  `context` declarado en las reglas (`Compliance — Gate de cumplimiento`);
  si no coinciden, GitHub no bloquea el merge y el control sería inútil.
- El despliegue tiene **una segunda** barrera: el job `gate` de `deploy.yml`
  consulta la API de GitHub y comprueba los `check-runs` del commit. Así, el
  control no depende de un único mecanismo.

---

## ADR-008 — Logs estructurados con el encoder nativo de Spring Boot

**Estado:** aceptada
**Contexto:** para que Loki indexe los logs por campos (nivel, servicio,
traza) en lugar de por texto, la aplicación debe emitirlos en JSON.

**Alternativas consideradas:**

| Alternativa | A favor | En contra |
|---|---|---|
| **Formato ECS nativo de Spring Boot 4** (`logging.structured.format.console=ecs`) | Sin dependencias adicionales; incluye el MDC automáticamente; formato estándar (Elastic Common Schema) que Loki y Grafana entienden de forma nativa. | Configurable mediante propiedades, no mediante un `logback-spring.xml` a medida. |
| `logstash-logback-encoder` | Formato Logstash muy extendido; configuración muy flexible. | Dependencia externa que hay que auditar y actualizar. |
| `logback-spring.xml` propio | Control total del formato. | Dos formatos que mantener (texto para local, JSON para producción) y una clase más de configuración. |

**Decisión:** el encoder nativo de Spring Boot en formato ECS, activado
únicamente en el perfil `prod`.

**Consecuencias:**
- El perfil de desarrollo conserva el texto plano, que es más legible.
- Se eliminó la dependencia `logstash-logback-encoder` del `pom.xml`.
- El MDC (con el identificador de correlación) aparece automáticamente en
  cada línea JSON, sin trabajo adicional.

---

## Revisión periódica

Estas decisiones deben revisarse si:

- el servicio se expone a internet (revisar ADR-002),
- el volumen de logs crece lo suficiente como para justificar un clúster de
  Loki (evaluar la arquitectura de indexado),
- el cluster de evaluación pasa a ser un cluster de producción (revisar
  ADR-003 y eldimensionamiento de los límites de recursos).

---

## ADR-009 — Malla de servicios con Istio

**Estado:** pendiente (no aplicada en la entrega)
**Contexto:** la pauta de la EFT pide usar Istio para manejar las redes y
las métricas de los servicios. El clúster de evaluación es un Kind de un
solo nodo sobre una EC2 `t3.large` (2 vCPU, 8 GiB). En la EP3, con dos
réplicas del backend y del frontend, el planificador rechazó pods por
`Insufficient cpu` y hubo que bajar a una réplica (ver
`DEPLOYMENT-K8S.md` §7). El backend reserva 200m de CPU y 384Mi de
memoria.

**Qué aportaría Istio al proyecto:**

| Capacidad | Uso en el proyecto |
|---|---|
| mTLS entre servicios (`PeerAuthentication` en modo `STRICT`) | Cifrado y autenticación del tráfico frontend → backend → base de datos, además de las NetworkPolicy actuales |
| Métricas de tráfico de Envoy (`istio_requests_total`, `istio_request_duration_milliseconds`) | Tasa, errores y latencia entre servicios, sin cambiar el código, para los dashboards de Grafana |
| Reintentos, *timeouts* y *circuit breaking* (`VirtualService`, `DestinationRule`) | Resiliencia del backend ante fallas de la base de datos |
| División de tráfico por porcentaje | Despliegues *canary* de una versión nueva del backend |

**Costo de recursos con los valores por defecto de Istio:** el plano de
control (`istiod`) reserva 500m de CPU y 2Gi de memoria, y cada *sidecar*
de Envoy reserva 100m de CPU y 128Mi por pod.

**Plan de implementación:**

1. Instalar con el perfil mínimo y recursos reducidos:
   `istioctl install --set profile=minimal --set values.pilot.resources.requests.cpu=100m --set values.pilot.resources.requests.memory=256Mi -y`.
2. Inyectar el *sidecar* solo en el backend
   (`sidecar.istio.io/inject: "true"` en la plantilla del pod) con
   `sidecar.istio.io/proxyCPU: 50m` y `sidecar.istio.io/proxyMemory: 64Mi`.
3. Agregar a Prometheus un job que recoja las métricas de Envoy (puerto
   15090) y un panel de tráfico entre servicios en Grafana.
4. Aplicar `PeerAuthentication` en modo `PERMISSIVE` y, una vez
   verificado, `STRICT`.
5. Agregar la verificación al job de Kubernetes del pipeline.

**Decisión y justificación:**

> Esta sección la redacta el equipo, sin apoyo de IA (las justificaciones
> técnicas son de autoría propia, según la pauta).

[Decisión y justificación del equipo]
