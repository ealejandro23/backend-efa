# Integración de las herramientas en el pipeline CI/CD

Este documento explica **cómo** cada herramienta se integra en el pipeline y
**cómo** esa integración produce decisiones técnicas. No es una lista de
herramientas: es la explicación del flujo de información que va desde el
código hasta la decisión de desplegar o no desplegar.

> **Indicador de logro cubierto:** IL3.2 / IE3 (métricas y dashboards en el
> proceso CI/CD) e IL3.3 / IE4 (documentación de la integración y su impacto
> en la toma de decisiones).

---

## 1. Flujo general

```
  push / pull request
          |
          v
  +-------------------------------------------------------+
  |  CI — Tests, Calidad y Seguridad                       |
  |                                                          |
  |  1. mvn clean verify        (JUnit 5 + JaCoCo)          |
  |  2. Gate de cobertura       (P-QA-002) --> STOP         |
  |  3. SonarCloud              (Quality Gate) --> STOP    |
  |  4. Snyk dependencias       (severidad alta) --> STOP  |
  |  5. docker build                                       |
  |  6. Snyk imagen             (severidad alta) --> STOP  |
  |  7. Publica metricas al Pushgateway                    |
  +-------------------------------------------------------+
          |
          | todas las etapas en verde
          v
  +-------------------------------------------------------+
  |  Compliance — Gate de cumplimiento                      |
  |                                                          |
  |  7. 13 politicas evaluadas --> STOP si alguna falla    |
  |  8.  Publica el resultado al Pushgateway               |
  +-------------------------------------------------------+
          |
          | el gate aprueba
          v
  +-------------------------------------------------------+
  |  CD — Build, push y deploy                              |
  |                                                          |
  |  9.  Job "gate": consulta la API de GitHub y verifica   |
  |      que TODAS las verificaciones obligatorias estan    |
  |      en verde para el commit --> STOP si no             |
  |  10. Construye la imagen desde el SHA verificado        |
  |  11. Publica en ECR (o simula)                          |
  |  12. Despliega (Compose o Kubernetes)                   |
  |  13. Verifica la salud y las metricas                   |
  |  14. Publica la duracion y el estado del despliegue     |
  +-------------------------------------------------------+
          |
          v
  +-------------------------------------------------------+
  |  Observabilidad continua                                 |
  |  Prometheus -> Grafana / Loki -> alertas -> gate        |
  +-------------------------------------------------------+
```

**Idea central:** el mismo identificador (`P-QA-002`, `P-SEC-001`,
`P-OBS-003`…) aparece en la regla de alerta de Prometheus, en la métrica
publicada en el Pushgateway, en la salida del gate de cumplimiento y en el
mensaje del pipeline. Eso permite recorrer el camino completo desde «se
disparó una alerta» hasta «qué control se violó» sin traducción manual.

---

## 2. Etapa por etapa

### 2.1 Pruebas automatizadas y cobertura

**Herramienta:** JUnit 5 + JaCoCo (Maven).

```bash
mvn -B -ntp clean verify
```

El paso siguiente es el **gate de cobertura**:

```bash
bash scripts/compliance/audit-coverage.sh demo/target/site/jacoco/jacoco.xml 0.60
bash scripts/ci/publish-coverage.sh demo/target/site/jacoco/jacoco.xml 0.60
```

`audit-coverage.sh` lee el XML de JaCoCo, extrae los contadores de líneas y
compara la proporción con el umbral. Si la cobertura baja del 60 %, el paso
falla y **el pipeline se detiene antes de construir la imagen**.

`publish-coverage.sh` hace dos cosas: publica `efa_ci_test_coverage_ratio`
en el Pushgateway y ejecuta el mismo gate. Es deliberado que la métrica se
publique **antes** de evaluar el gate: así, aunque el pipeline se detenga,
la causa queda registrada y es visible en Grafana.

**Decisión que habilita:** si la cobertura cae, se priorizan pruebas en el
módulo afectado (visible en el dashboard CI/CD) en lugar de descubrir el
problema semanas después.

### 2.2 Análisis estático y Quality Gate

**Herramienta:** SonarCloud (Maven).

```bash
mvn -B -ntp org.sonarsource.scanner.maven:sonar-maven-plugin:5.8.0.7211:sonar \
  -Dsonar.projectKey=... \
  -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml \
  -Dsonar.qualitygate.wait=true
```

`sonar.qualitygate.wait=true` es la opción clave: hace que el plugin **espere**
al veredicto del Quality Gate en lugar de terminar el paso al enviar el
análisis. Si el gate falla, el paso falla y el pipeline se detiene.

**Decisión que habilita:** el Quality Gate define umbrales objetivos
(cobertura, duplicación, vulnerabilidades, complejidad, entre otros). Cuando falla, el
informe señala el archivo y la línea exacta, de modo que la corrección es
dirigida y no una discussión de opinión.

### 2.3 Seguridad de dependencias e imagen

**Herramientas:** Snyk (dependencias Maven e imagen Docker) y Trivy.

```bash
snyk test --file=pom.xml --package-manager=maven --severity-threshold=high
snyk container test proyecto-efa-backend:latest --file=Dockerfile --severity-threshold=high
```

Ambos análisis **son parte del pipeline principal**: si uno falla, el CI
queda en rojo y el CD bloqueado.

**Decisión que habilita:** cuando Snyk reporta una vulnerabilidad, se decide
entre actualizar la dependencia o mitigated el riesgo de forma documentada.
La imagen base Alpine del runtime se adoptó precisamente para corregir
vulnerabilidades detectadas en la imagen anterior.

### 2.4 Publicación de métricas del pipeline

**Herramienta:** Pushgateway.

```bash
bash scripts/ci/publish-metrics.sh efa_ci_test_coverage_ratio 0.73 branch=main commit=16774fb
bash scripts/ci/publish-metrics.sh efa_ci_build_success 1 branch=main
bash scripts/ci/publish-metrics.sh efa_ci_quality_gate_passed 1 branch=main
bash scripts/ci/publish-metrics.sh efa_ci_compliance_policy_passed 1 branch=main policy=P-QA-002 severity=blocker
```

**Por qué Pushgateway y no otro mecanismo.** Las métricas de un job de CI
nacen y mueren dentro de la ejecución: no hay un endpoint activo que
Prometheus pueda scrapear. El modelo *push* es el correcto para este caso.
El script se apoya en la API del Pushgateway, que **reemplaza** el valor de
la serie en cada publicación.

**El caso del contador.** `efa_ci_deployments_total` sí necesita acumular.
Como el Pushgateway reemplaza en lugar de sumar, el script implementa el
patrón leer → incrementar → publicar:

```bash
CURRENT_VALUE="$(curl -s "${PUSHGATEWAY_URL}/metrics" | awk '/^efa_ci_deployments_total\{/ { print $NF }' | tail -n 1)"
NEW_VALUE=$((CURRENT_VALUE + 1))
```

**Decisión que habilita:** el dashboard CI/CD convierte estas métricas en
indicadores de entrega: duración por etapa, cobertura por commit, resultado
del Quality Gate. Con esa información se identifica la etapa lenta del
pipeline y se prioriza optimizar esa, no todo el pipeline.

### 2.5 Gate de cumplimiento

**Herramienta:** scripts propios de auditoría + las herramientas anteriores.

```bash
bash scripts/compliance/run-all.sh --continuar
```

El gate evalúa 13 políticas y consolida el resultado. Si alguna política
bloqueante falla, **el job falla**, y como ese job es una verificación
obligatoria de la rama principal, GitHub impide el merge.

**Decisión que habilita:** el equipo sabe, antes de integrar, que el cambio
introduce un secreto, que baja la cobertura, que deja un contenedor
ejecutándose como root o que un manifiesto quedó sin sonda de salud. La
corrección ocurre en el Pull Request, no en producción.

### 2.6 Gate de despliegue

**Herramienta:** API de GitHub + `workflow_run`.

El job `gate` de `deploy.yml` no se limita a esperar el resultado del CI:
**consulta la API de GitHub** y comprueba, para el commit exacto que se
va a desplegar, que cada verificación obligatoria está en `success`:

```bash
STATE="$(curl --silent \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/commits/${TARGET_SHA}/check-runs?per_page=100" \
  | grep -oE "\"name\":\"${CHECK}\"[^}]*\"conclusion\":\"[a-z]+\"" \
  | grep -oE '"conclusion":"[a-z]+"' | tail -n 1 | cut -d'"' -f4)"
```

Si alguna no está en verde, el gate falla y **no se despliega**.

**Decisión que habilita:** existe una única fuente de verdad sobre si un
commit es desplegable. Aunque alguien añadiera un paso al workflow sin
respetar el orden, el gate impide que llegue a producción.

### 2.7 Despliegue y verificación

**Entorno Docker Compose (simulado):**

```bash
docker compose -p efa-ci-demo up -d --no-build --pull never --wait --wait-timeout 180
curl --fail http://localhost:8083/actuator/health -o health.json
grep -q '"status":"UP"' health.json
curl --fail http://localhost:8083/actuator/prometheus -o metrics.txt
grep -q '^efa_availability_up' metrics.txt
```

La última comprobación es importante: **no basta con que el servicio
responda, tiene que estar instrumentado**. Un despliegue sin métricas
rompería la cadena de observabilidad, y el pipeline lo detecta.

**Entorno Kubernetes:** `scripts/k8s/deploy-kind.sh` ejecuta el ciclo
completo y verifica salud, métricas, descubrimiento en Prometheus y carga de
dashboards en Grafana. El detalle está en
[`docs/DEPLOYMENT-K8S.md`](DEPLOYMENT-K8S.md).

**Decisión que habilita:** el despliegue no se da por bueno hasta que se
comprueba que es observable. Un servicio que arranca pero que no reporta
métricas es, para efectos operativos, un servicio que no existe.

### 2.8 Métricas del despliegue

Al finalizar, el job de despliegue publica:

```bash
bash scripts/ci/publish-deploy-metrics.sh 214.5 success branch=main
```

- `efa_ci_deployment_duration_seconds`: duración total.
- `efa_ci_deployment_status`: 1 si fue exitoso, 0 si falló.
- `efa_ci_stage_duration_seconds{stage="build|quality|deploy"}`: por etapa.
- `efa_ci_deployments_total`: contador acumulado.

---

## 3. Trazabilidad completa: del código a la producción simulada

| Eslabón | Dato generado | Dónde queda registrado |
|---|---|---|
| Código | Commit SHA | `git log`, GitHub |
| Compilación | Versión, commit, rama, fecha | Variables de entorno de la imagen; `efa-build-info` ConfigMap |
| Imagen | Digest de la imagen | Registro (ECR) o `kind load` |
| Despliegue | SHA desplegado | `github.event.workflow_run.head_sha`, `efa.io/commit` |
| Métricas | Serie etiquetada con `commit` | Prometheus |
| Logs | Campo `service.version` y `commit` | Loki |
| Verificación | Resultado del gate, checks del commit | GitHub Actions |
| Panel | Versión en ejecución | `efa_deploy_info` en Grafana |

La cadena completa es verificable de extremo a extremo:

```bash
# 1. ¿Qué versión está corriendo?
curl -s http://localhost:8083/actuator/info

# 2. ¿Qué versión reportan las métricas?
curl -s http://localhost:9090/api/v1/query?query=efa_deploy_info

# 3. ¿Qué commit desplegó el pipeline?
kubectl get deployment efa-backend -n efa -o jsonpath='{.spec.template.metadata.annotations.efa\.io/commit}'

# 4. ¿Ese commit pasó todos los controles?
gh api "repos/ealejandro23/backend-efa/commits/<commit>/check-runs"
```

---

## 4. Resumen: herramienta → problema que resuelve

| Herramienta | Problema que resuelve | Métrica o evidencia que produce |
|---|---|---|
| **Micrometer + Actuator** | No hay forma objetiva de saber cómo se comporta el servicio. | `http_server_requests_*`, `jvm_*`, `efa_*`. |
| **Prometheus** | Los datos de la aplicación no son consultables ni alertables. | Series temporales; reglas de alerta. |
| **Grafana** | Los datos no se ven sin una herramienta de visualización. | Tres dashboards aprovisionados. |
| **Loki + Alloy** | Los logs no se pueden consultar de forma estructurada. | Logs indexados por `service`, con `traceId`. |
| **Pushgateway** | Las métricas del pipeline no existen en Prometheus. | `efa_ci_*`. |
| **cAdvisor** | No se sabe si el servicio consume más de lo previsto. | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes`. |
| **JaCoCo** | No se sabe si las pruebas cubren el código. | `efa_ci_test_coverage_ratio`. |
| **SonarCloud** | La calidad se evalúa de forma subjetiva. | Quality Gate. |
| **Snyk / Trivy** | Las dependencias y la imagen tienen vulnerabilidades conocidas. | `efa_ci_security_vulnerabilities`. |
| **Kind + Kubernetes** | El despliegue no se parece a producción. | Manifiestos, sondas, HPA, PDB. |
| **Kustomize** | La configuración del cluster se desactualiza respecto al código. | Manifiestos declarativos con `replacements`. |
| **API de GitHub (gate)** | Nada impedía desplegar un commit sin verificar. | Job `gate` del CD. |
| **Branch protection** | Nada impedía integrar código sin revisar. | `verify-branch-protection.sh`. |
| **Auditorías propias** | Las políticas del proyecto no se verificaban. | `efa_ci_compliance_policy_passed`. |
| **CODEOWNERS** | Los cambios sensibles no tenían responsable. | Revisión obligatoria por área. |

---

## 5. Verificación local del pipeline

Para ejecutar las mismas comprobaciones fuera de GitHub Actions:

```bash
# 1. Pruebas y cobertura
cd demo && mvn -B -ntp clean verify && cd ..

# 2. Gate de cumplimiento completo
bash scripts/compliance/run-all.sh --continuar

# 3. Publicar métricas al Pushgateway local
export PUSHGATEWAY_URL=http://localhost:9091
bash scripts/ci/publish-coverage.sh demo/target/site/jacoco/jacoco.xml 0.60

# 4. Verificar los dashboards
curl -s -u admin:efa-observability "http://localhost:3000/api/search?type=dash-db"
```

---

## 6. Archivos del pipeline

| Archivo | Función |
|---|---|
| `.github/workflows/main.yml` | CI: pruebas, cobertura, calidad, seguridad y publicación de métricas. |
| `.github/workflows/compliance.yml` | Gate de cumplimiento y despliegue en Kubernetes. |
| `.github/workflows/deploy.yml` | CD: gate de despliegue, build, publicación y despliegue. |
| `.github/workflows/ci.yml` | CI complementario para la rama `develop`. |
| `.github/prometheus-compliance.yml` | Prometheus del runner para el gate de alertas. |
| `scripts/ci/publish-metrics.sh` | Publicación genérica de métricas. |
| `scripts/ci/publish-coverage.sh` | Publicación y gate de la cobertura. |
| `scripts/ci/publish-deploy-metrics.sh` | Métricas de despliegue. |
| `scripts/compliance/run-all.sh` | Gate consolidado de cumplimiento. |
| `scripts/k8s/deploy-kind.sh` | Despliegue automatizado en Kubernetes. |
