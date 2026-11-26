# Uso de inteligencia artificial en el proyecto

Este documento cumple con el requisito de la pauta de evaluación: **declarar
qué herramientas de inteligencia artificial se usaron y cómo se aplicaron**.

> Referencia normativa: [Uso ética de la IA en la DUOC](https://bibliotecas.duoc.cl/ia).

---

## Principio declarado

La inteligencia artificial se usó **como apoyo**, nunca como reemplazo del
razonamiento técnico del equipo.

| Permitido | No permitido |
|---|---|
| Generar código boilerplate y archivos de configuración a partir de una especificación del equipo. | Redactar las reflexiones individuales de las conclusiones. |
| Detectar errores de sintaxis y de API en configuraciones. | Generar justificaciones técnicas que el equipo no pueda defender. |
| Redactar documentación descriptiva de lo que el equipo implementó. | Sustituir el diseño, la arquitectura o las decisiones del equipo. |
| Orientar la búsqueda de referencias y de la documentación oficial. | Dar por bueno un resultado sin verificarlo. |
| Generar los JSON de los dashboards a partir de una especificación de las métricas. | Generar las políticas de cumplimiento sin revisarlas. |

---

## Herramientas utilizadas

| Herramienta | Uso concreto en este proyecto | Verificación realizada |
|---|---|---|
| **Asistente de IA integrado en el entorno de desarrollo** (OpenCode, con modelos `minimax-M3.1-Flash-Free`) | Generación inicial de los archivos de configuración (Prometheus, Loki, Alloy, Grafana, Docker Compose), de los manifiestos de Kubernetes, de los scripts de auditoría de cumplimiento y de los dashboards JSON. Corrección de errores de compilación (paquetes reubicados en Spring Boot 4, propiedades de Actuator con nombre nuevo, sintaxis de Alloy). | Todas las configuraciones se aplicaron y se verificaron con las herramientas reales: `docker compose config`, `alloy validate`, `kubectl apply`, `kubectl rollout status`, `mvn verify`, `docker build`. |
| **Documentación oficial de Grafana** (grafana.com/docs/alloy, grafana.com/docs/grafana) | Verificación de la sintaxis de los componentes de Alloy (`loki.source.docker`, `discovery.relabel`, `stage.static_labels`) y de las propiedades de Spring Boot para el logging estructurado ECS. | Lectura de la documentación de la versión vigente (`alloy v1.21.3`, `Spring Boot 4.0.9`). |
| **Docker Hub API** | Verificación de que las etiquetas de imagen utilizadas existen (`prom/prometheus:v3.16.0`, `grafana/loki:3.7.9`, `grafana/alloy:v1.21.3`, `grafana/grafana:12.4.15`, `prom/pushgateway:v1.11.5`). | Consulta del registro antes de fijar cada versión. |

---

## Aplicaciones por indicador

### IE1 — Monitoreo y logging

La IA generó la estructura inicial de `prometheus.yml`, `loki-config.yml`,
`alloy-config.docker.alloy` y `alloy-config.kubernetes.alloy`. **Todos
esos archivos fallaron en su primera ejecución** por reasons que solo se
detectaron probando:

| Problema detectado | Cómo se detectó | Corrección |
|---|---|---|
| Alloy no acepta comentarios `#`. | `alloy validate` devolvió `illegal character U+0023 '#'`. | Se reescribieron todos los comentarios con `//`. |
| `relabel_rules` es un atributo, no un bloque. | `alloy validate` devolvió `"relabel_rules" must be an attribute, but is used as a block`. | Se reestructuró usando `discovery.docker` + `discovery.relabel`, que es el patrón documentado. |
| `target_labels` no existe en Alloy (es `target_label`). | El contenedor de Alloy no arrancaba; el error quedó en sus logs. | Se corrigió el nombre del atributo. |
| `stage.label` no existe. | `alloy validate` devolvió `unrecognized block name "stage.label"`. | Se usó `stage.static_labels` para las constantes. |
| Loki 3.7 movió `max_label_names_per_series` de `distributor` a `limits_config`. | Los logs del contenedor de Loki mostraban el error de deserialización. | Se movieron los campos al bloque correcto. |
| La imagen de Loki es *distroless*: no tiene shell ni `wget`, de modo que no puede ejecutar un `healthcheck`. | `docker exec efa-loki sh -c ...` devolvió `executable file not found`. | Se implementó un contenedor auxiliar (`loki-ready`) que comprueba `/ready` desde la red. |

**Ninguno de esos errores se habría detectado leyendo el código.** Se
detectaron ejecutando el stack. Ese es el criterio que el equipo aplicó:
*lo generado por IA es una hipótesis, no un resultado*.

### IE2 — Despliegue en Kubernetes

Los manifiestos de `infra/k8s/` se generaron con asistencia de IA y se
corregieron sobre la base de las ejecuciones reales:

| Problema detectado | Cómo se detectó | Corrección |
|---|---|---|
| Kubernetes no sustituye variables `${...}` en los manifiestos. | `kubectl apply` falló con `Invalid value: "${ENVIRONMENT:-prod}": a valid label must be...`. | Se eliminaron los marcadores de posición y se implementó la inyección de metadatos con `replacements` de Kustomize. |
| Un `Role` no puede declarar `nonResourceURLs`. | `kubectl apply` falló con `namespaced rules cannot apply to non-resource URLs`. | Se eliminó esa regla del `Role` (queda en el `ClusterRole` de Prometheus). |
| `commonLabels` modifica `spec.selector`, que es inmutable. | `kubectl apply` falló con `spec.selector: Invalid value ... field is immutable`. | Se cambió a `labels: [{includeSelectors: false, pairs: {...}}]`. |
| Los CRD de Prometheus Operator no están en Kind. | `kubectl apply` falló con `no matches for kind "ServiceMonitor"`. | Esos recursos se aplican de forma condicional, y el descubrimiento por anotaciones cubre el mismo objetivo sin depender del Operator. |
| El `StatefulSet` no es un `Deployment`. | `kubectl rollout status deployment/efa-db` devolvió `deployments.apps "efa-db" not found`. | El script distingue `statefulset/` de `deployment/`. |

### IE3 — Dashboards

Los tres dashboards se generaron como JSON de Grafana y se validaron con
dos mecanismos: parseo de JSON (`JSON.parse`) y **carga real en Grafana**,
verificando con la API que aparecen en la carpeta «Proyecto EFA».

Durante la revisión manual se corrigió un texto corrupto en una descripción
de panel y se ajustaron las expresiones PromQL para que usen las etiquetas
realmente presentes en las métricas (`environment`, `service`, `namespace`).

### IE5 e IE6 — Cumplimiento

Los scripts de auditoría se generaron con asistencia y se probaron contra
el repositorio:

- `audit-secrets.sh` se probó con un archivo que contenía un token de
  ejemplo, para comprobar que lo detectaba.
- `audit-dockerfile.sh` se probó contra el Dockerfile real, que usa
  `eclipse-temurin:21-jre-alpine` (con tag fijo) y no declara `USER`: el
  script lo señaló correctamente.
- `audit-kubernetes.sh` se ejecutó contra `infra/k8s/` y señalar las
  ausencias reales (por ejemplo, que los contenedores del frontend no
  declaraban `allowPrivilegeEscalation`).
- `audit-workflows.sh` se ejecutó contra los workflows reales.

### Corrección de un defecto de producción

Durante la verificación en el entorno de ejecución, el healthcheck del
backend empezó a devolver `503` con el error
`HikariPool-1 - Connection is not available (total=10, active=10, idle=0)`.
El análisis del código mostró que `AvailabilityHealthIndicator` obtenía una
conexión JDBC **sin cerrarla**, agotando el pool de conexiones en 30
minutos. Se corrigió usando *try-with-resources*. Esta es la clase de
defecto que la observación automatizada detecta y que una revisión de
código rápida no habría detectado.

---

## Segunda etapa: puesta en verde del pipeline y despliegue en AWS

En la sesión del 19-11-2026 se usó **Claude (Anthropic)** como asistente
para diagnosticar fallas del pipeline y del despliegue y para proponer
correcciones. El equipo ejecutó cada cambio, revisó los resultados y decidió
qué integrar.

| Uso concreto | Verificación realizada |
|---|---|
| Diagnóstico de los fallos del CI a partir de los logs (token de SonarCloud vencido, Quality Gate por cobertura, vulnerabilidades de Jackson y OpenJDK). | Re-ejecución de los workflows hasta verlos en verde en GitHub Actions. |
| Redacción de `ObservabilityComponentsTest` (pruebas de las clases de observabilidad). | Las pruebas compilaron y pasaron en el CI; SonarCloud aprobó el Quality Gate. |
| Corrección del gate del CD (nombres de los *check runs*, uso de `jq`), de la instalación de Kind en el runner y del paso de Snyk (detalle legible y artefactos). | Ejecuciones del CD bloqueando con CI en rojo y desplegando con todo en verde. |
| Propuesta de la excepción temporal de Snyk (`.snyk`) para una vulnerabilidad sin parche publicado. | Snyk confirmó que no existía imagen corregida; la excepción vence el 31-12-2026. |
| Comandos de AWS CloudShell para la EC2, el Security Group y el despliegue; NetworkPolicies adicionales, autenticación de Prometheus, Pushgateway persistente y recolector de métricas del pipeline. | Verificación en el cluster: pods en `Running`, targets `up`, consultas reales Grafana → Prometheus y dashboards con datos. |
| Corrección de dos paneles del dashboard (SLO invertido, versión desplegada) y de las variables «All». | Revisión visual en Grafana con tráfico generado. |
| Redacción de la actualización de `DEPLOYMENT-K8S.md` §7 y `EVIDENCIAS.md` §10. | Revisada por el equipo contra las salidas reales. |

Las reflexiones individuales y las conclusiones del informe **no** se
redactaron con esta herramienta.

---

## Tercera etapa: Evaluación Final Transversal

En la sesión del 25-11-2026 se usó **Claude (Anthropic)** para revisar la
pauta de la EFT contra el repositorio y proponer los cambios faltantes. El
equipo ejecutó cada paso en AWS CloudShell, revisó los resultados y aprobó
cada PR.

| Uso concreto | Verificación realizada |
|---|---|
| Revisión de la pauta y lista de requisitos faltantes. | Contraste con el estado real del repositorio y de los workflows. |
| Etapa `tester` del Dockerfile y pasos de pruebas en contenedor y publicación en Docker Hub (#27, #29). | CI en verde con 55 pruebas dentro del contenedor; tags publicados en Docker Hub. |
| Diagnóstico de la falla de Snyk y propuesta del hotfix de versiones (#28). | Snyk en verde con Spring Boot 4.0.10 y PostgreSQL JDBC 42.7.15. |
| Configuración del *environment* `production` y del job de aceptación con su script (#30, #31). | Prueba local en CloudShell (12/12) y ejecución real del CD con aprobación. |
| Configuración del agente de CloudWatch, del puente de métricas, del dashboard y de las alarmas (#32). | Métricas y logs recibidos en CloudWatch; dashboard con datos. |
| Redacción de `docs/BRANCHING.md` (salvo la justificación) y de `EVIDENCIAS.md` §11. | Revisada por el equipo contra el historial y las ejecuciones reales. |

La justificación de la estrategia de ramificación (`docs/BRANCHING.md` §8),
las conclusiones y las reflexiones individuales **no** se redactaron con
esta herramienta.

---

## Contenido redactado sin apoyo de IA

Conforme a lo exigido por la pauta, **las reflexiones individuales de cada
integrante son de autoría exclusiva de cada persona y no se generaron con
apoyo de inteligencia artificial**. Son la sección `4. Reflexiones
individuales` del informe final.

Del mismo modo, las justificaciones de diseño de
`docs/DECISION-RECORDS.md` y de `docs/COMPLIANCE.md` reflejan el criterio
del equipo: se explican las alternativas descartadas **por qué se
descartaron**, que es la parte que la IA no puede inferir sin el contexto
del proyecto.

---

## Verificación de originalidad

Todo el contenido generado con asistencia de IA fue:

1. ** Ejecutado** con las herramientas reales del proyecto (Docker, Maven,
   kubectl, Grafana, Prometheus, Alloy, Loki).
2. **Revisado** línea a línea por los integrantes del equipo.
3. **Corregido** donde la verificación automática detectó discrepancias
   (todas las listadas en la tabla anterior).
4. **Documentado**: este registro permite a quien evalúe conocer exactamente
   qué partes del repositorio han pasado por la herramienta.

No se emplearon herramientas de IA para generar datos de resultados de
pruebas, informes de calidad ni salidas de ejecución: todas las evidencias
del directorio `evidencias/` proceden de ejecuciones reales.
