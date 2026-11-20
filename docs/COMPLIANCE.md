# Políticas de cumplimiento y auditoría automatizada

Este documento describe el catálogo de políticas de cumplimiento del
proyecto EFA, cómo se evalúan de forma automatizada en el pipeline y qué
consecuencia tiene su incumplimiento.

> **Indicadores cubiertos:** IL3.3 / IE5 (políticas de cumplimiento y
> auditoría automatizada) e IL3.3 / IE6 (interrupción del pipeline ante
> fallas críticas).

---

## 1. Enfoque

El cumplimiento no se implementa como un documento que describe buenas
prácticas, sino como **reglas ejecutables**. Cada política tiene:

- un **identificador estable** (`P-SEC-001`, `P-QA-002`, …),
- una **severidad** que determina si su incumplimiento detiene el pipeline,
- un **script de auditoría** que la verifica mecánicamente,
- una **justificación** del por qué se exige.

Los identificadores son los mismos que usan las reglas de alerta de
Prometheus (`cumplimiento: "P-OBS-003"`) y las etiquetas de las métricas de
cumplimiento (`efa_ci_compliance_policy_passed{policy="P-OBS-003"}`). Eso
permite correlacionar la falla del pipeline, la alerta y el panel de
Grafana con un mismo identificador.

### Severidades

| Severidad | Efecto | Ejemplo |
|---|---|---|
| `blocker` | El pipeline se detiene. No hay despliegue. | Se detectó un secreto en el código. |
| `major` | El pipeline se detiene. No hay despliegue. | Las acciones del workflow no están fijadas a una versión. |
| `minor` | Se informa en el informe, pero el pipeline continúa. | Falta un párrafo en la documentación. |

El catálogo completo está en [`compliance/policies/catalog.yml`](../compliance/policies/catalog.yml).

---

## 2. Catálogo de políticas

### 2.1 Seguridad

| ID | Política | Severidad | Verificación |
|---|---|---|---|
| **P-SEC-001** | Sin secretos hardcodeados en el código | blocker | `audit-secrets.sh` |
| **P-SEC-002** | Contenedores sin privilegios y ejecutados como usuario no root | blocker | `audit-dockerfile.sh` + `audit-kubernetes.sh` |
| **P-SEC-003** | Dependencias e imagen sin vulnerabilidades altas o críticas | blocker | `audit-dependencies.sh` (Trivy) + Snyk en el CI |
| **P-SEC-004** | Manifiestos de Kubernetes con contexto de seguridad completo | blocker | `audit-kubernetes.sh` |
| **P-SEC-005** | Imágenes base fijadas a una versión | major | `audit-dockerfile.sh` |
| **P-SEC-006** | Reglas de protección de rama activas en GitHub | major | `verify-branch-protection.sh` |

**P-SEC-001** busca credenciales con tres estrategias independientes: patrones
de valor conocido (claves AWS `AKIA…`, tokens de GitHub `ghp_…`, claves
privadas PEM, JWT), asignaciones del tipo `password=…` con **valor literal**
(no referencias a variables de entorno), y la presencia de archivos de
credenciales conocidos (`.env`, `id_rsa`, `credentials.json`) entre los
archivos versionados. Además consulta las alertas abiertas del *secret
scanning* de GitHub cuando el token tiene permisos.

**P-SEC-004** comprueba, para cada `Deployment`, `StatefulSet`, `DaemonSet`,
`Job` y `CronJob`, la presencia de: `runAsNonRoot: true`, un UID distinto de
cero, `seccompProfile`, `allowPrivilegeEscalation: false`,
`drop: ["ALL"]`, límites de recursos, y las sondas `livenessProbe` y
`readinessProbe`. También rechaza `privileged: true`, el montaje del socket
de Docker y `hostNetwork`/`hostPID`/`hostIPC`.

### 2.2 Calidad

| ID | Política | Severidad | Verificación |
|---|---|---|---|
| **P-QA-001** | Quality Gate de análisis estático aprobado | blocker | SonarCloud en el CI (`sonar.qualitygate.wait=true`) |
| **P-QA-002** | Cobertura de pruebas ≥ 60 % | blocker | `audit-coverage.sh` (JaCoCo) |
| **P-QA-003** | Suite de pruebas completa y en verde | blocker | `mvn clean verify` en el CI |
| **P-QA-004** | Acciones de GitHub fijadas a una versión | major | `audit-workflows.sh` |

**P-QA-002** lee el reporte XML de JaCoCo, extrae los contadores
agregados de líneas (`missed`/`covered`), calcula la proporción y la
compara con el umbral. Si está por debajo, **el pipeline se detiene antes de
construir la imagen**. La métrica también se publica en el Pushgateway
(`efa_ci_test_coverage_ratio`), de modo que la tendencia de cobertura es
visible en Grafana y no solo el valor puntual.

### 2.3 Integridad del pipeline

| ID | Política | Severidad | Verificación |
|---|---|---|---|
| **P-CI-001** | El despliegue solo ocurre con las verificaciones en verde | blocker | `audit-workflows.sh` + job `gate` de `deploy.yml` |
| **P-CI-002** | El despliegue es trazable a un commit verificado | major | `audit-workflows.sh` |
| **P-CI-003** | Las etapas de seguridad y calidad no son tolerantes a fallos | blocker | `audit-workflows.sh` |

**P-CI-003** es la política que da sentido a todas las demás: si un paso de
SonarCloud, Snyk, Trivy, auditoría o pruebas declarara
`continue-on-error: true`, el control existiría pero sería decorativo. El
script detecta exactamente esa situación.

### 2.4 Observabilidad

| ID | Política | Severidad | Verificación |
|---|---|---|---|
| **P-OBS-001** | El microservicio expone métricas y sonda de salud | blocker | `audit-observability.sh` |
| **P-OBS-002** | Los manifiestos declaran cómo recolectar sus métricas | major | `audit-observability.sh` |
| **P-OBS-003** | Sin alertas críticas de disponibilidad activas | blocker | `audit-alerts.sh` |
| **P-OBS-004** | Sin alertas críticas de tasa de errores activas | blocker | `audit-alerts.sh` |
| **P-OBS-005** | Sin alertas críticas de saturación de memoria activas | blocker | `audit-alerts.sh` |

**P-OBS-003/004/005** consultan Prometheus en tiempo de despliegue:

```promql
ALERTS{alertstate="firing", severity="critical", cumplimiento=~"(P-OBS-003|P-OBS-004|P-OBS-005)"}
```

Si hay resultados, el despliegue se detiene. La rationale es directa:
**desplegar sobre un servicio que ya está fallando agrava la incidencia.**

### 2.5 Documentación

| ID | Política | Severidad | Verificación |
|---|---|---|---|
| **P-DOC-001** | Documentación de integración actualizada | minor | `audit-docs.sh` |
| **P-DOC-002** | Uso de inteligencia artificial declarado | minor | `audit-docs.sh` |

---

## 3. Ejecución de la auditoría

### 3.1 Ejecución individual

```bash
bash scripts/compliance/audit-secrets.sh .
bash scripts/compliance/audit-dockerfile.sh
bash scripts/compliance/audit-kubernetes.sh infra/k8s
bash scripts/compliance/audit-workflows.sh .github/workflows
bash scripts/compliance/audit-observability.sh
bash scripts/compliance/audit-coverage.sh demo/target/site/jacoco/jacoco.xml 0.60
bash scripts/compliance/audit-alerts.sh http://localhost:9090
bash scripts/compliance/verify-branch-protection.sh main
```

### 3.2 Ejecución consolidada (el gate)

```bash
# Todas las politivas, mostrando el informe completo
bash scripts/compliance/run-all.sh --continuar

# Solo un subconjunto
bash scripts/compliance/run-all.sh --solo "P-SEC-001 P-QA-002"

# Detenerse en la primera falla bloqueante
bash scripts/compliance/run-all.sh
```

Salida del gate (extracto de una ejecución real):

```
############################################################
#  GATE DE CUMPLIMIENTO - PROYECTO EFA
#  2026-11-10T21:44:07Z
#  Commit: 16774fb
#  Rama  : main
############################################################

------------------------------------------------------------
>> P-SEC-001 [blocker] Sin secretos hardcodeados
------------------------------------------------------------
=== P-SEC-001: Buscando secretos versionados en . ===
P-SEC-001 APROBADA: no se detectaron secretos versionados.

>> P-SEC-001: APROBADA

...

############################################################
#  RESUMEN DEL GATE DE CUMPLIMIENTO
############################################################
  Politicas evaluadas : 13
  Aprobadas           : 13
  Fallidas (bloqueantes): 0
  Fallidas (menores)  : 0
  Omitidas            : 0

############################################################
#  RESULTADO: CUMPLIMIENTO APROBADO
#  El pipeline puede continuar con el despliegue.
############################################################
```

### 3.3 Integración en el pipeline

El workflow `compliance.yml` ejecuta el gate. El job se llama
**«Compliance — Gate de cumplimiento»** y es una verificación **obligatoria**
de la rama principal (ver §4).

---

## 4. Branch protection rules

Las reglas de protección de rama son el control que convierte el gate en
una barrera real: sin ellas, el gate es solo informativo.

### Configuración declarada

La configuración se versiona en
[`.github/branch-protection.yml`](../.github/branch-protection.yml) para que
los cambios en la política se revisen como cualquier otro cambio y para que
el script de verificación pueda compararla con el estado real de GitHub.

### Configuración aplicada

| Regla | Valor | Motivo |
|---|---|---|
| Revisiones requeridas | 1 aprobación | Ningún cambio entra sin que otro integrante lo revise. La revisión obligatoria de *code owners* no se activó: el equipo es de dos personas y bloquearía cambios cuando el responsable no está disponible. |
| Revisiones obsoletas | Descartadas al hacer push | Una revisión deja de ser válida si el código cambia después. |
| Verificaciones obligatorias | `Build, Tests, Calidad y Seguridad` (job del CI) y `Compliance — Gate de cumplimiento` | Ambas deben estar en verde; con `strict: true`, además hay que tener la rama al día. |
| Push directo | Bloqueado | Todo cambio entra por Pull Request. |
| Force-push | Bloqueado | No se puede reescribir el historial de la rama principal. |
| Borrado de la rama | Bloqueado | Salvaguarda contra la eliminación accidental. |
| Historial lineal | Requerido, sin merges de commits | Historial auditable. |

### Verificación automatizada

```bash
export GITHUB_TOKEN=<token con permisos de administración>
export GITHUB_REPOSITORY=ealejandro23/backend-efa
bash scripts/compliance/verify-branch-protection.sh main
```

El script consulta la API de GitHub y verifica que las reglas anteriores
estén efectivamente aplicadas. Si la rama no tiene protección, **el
pipeline se detiene**.

### CODEOWNERS

[`.github/CODEOWNERS`](../.github/CODEOWNERS) asigna responsables por área.
Las áreas sensibles tienen responsable específico:

| Ruta | Responsable | Motivo |
|---|---|---|
| `.github/workflows/`, `scripts/ci/`, `scripts/compliance/` | Responsable de DevOps | Un cambio aquí puede omitir un control. |
| `infra/`, `Dockerfile`, `docker-compose.yml` | Responsable de DevOps | Un cambio aquí afecta la seguridad del despliegue. |
| `demo/src/main/java/.../observability/` | Responsable de DevOps | Un cambio aquí puede degradar la observabilidad. |
| `docs/`, `compliance/`, `README.md` | Ambos integrantes | La documentación es parte de la entrega. |

---

## 5. Otras herramientas de cumplimiento del proyecto

Además del gate propio, el proyecto incorpora:

| Herramienta | Control que aporta | Dónde se ejecuta |
|---|---|---|
| **SonarCloud** | Análisis estático y Quality Gate objetivo sobre el código. | `main.yml`, etapa «Análisis SonarCloud». |
| **Snyk** | Vulnerabilidades conocidas en dependencias Maven y en la imagen Docker. | `main.yml`, etapas de seguridad. |
| **Trivy** | Vulnerabilidades en dependencias e imagen, y análisis de la IaC. | `audit-dependencies.sh` y etapa propia del CI. |
| **Dependabot** | Actualizaciones automáticas de dependencias, Docker y acciones. | `.github/dependabot.yml`. |
| **Secret scanning de GitHub** | Detección de credenciales en el historial. | Servicio nativo del repositorio; su resultado lo consulta `audit-secrets.sh`. |
| **Pod Security Admission** | Rechaza pods que no cumplan el perfil `restricted`. | Etiquetado del namespace `efa`. |
| **NetworkPolicy** | Control de tráfico entre pods con denegación por defecto. | `infra/k8s/base/07-networkpolicy.yaml`. |

---

## 6. Resultado esperado de una falla

Cuando una política bloqueante se incumple:

1. El paso correspondiente en GitHub Actions **falla**.
2. El job «Compliance — Gate de cumplimiento» **falla**.
3. GitHub **impide el merge** del Pull Request (verificación obligatoria).
4. El workflow de despliegue **no se ejecuta**, porque se gatrega por
   `workflow_run` del CI y además tiene un job `gate` propio que consulta la
   API de GitHub para confirmar que todas las verificaciones obligatorias
   están en verde.
5. El entorno productivo **queda sin cambios**.
6. El resultado se publica en el Pushgateway como
   `efa_ci_compliance_policy_passed{policy="P-OBS-003"} 0`, lo que lo hace
   visible en el tablero de Grafana.

---

## 7. Archivos

| Archivo | Contenido |
|---|---|
| `compliance/policies/catalog.yml` | Catálogo completo de políticas con su justificación. |
| `compliance/README.md` | Guía rápida de uso del gate. |
| `scripts/compliance/run-all.sh` | Gate consolidado. |
| `scripts/compliance/audit-*.sh` | Auditorías individuales. |
| `scripts/compliance/verify-branch-protection.sh` | Verificación de la protección de rama. |
| `.github/branch-protection.yml` | Configuración de protección de rama versionada. |
| `.github/CODEOWNERS` | Responsables por área. |
| `.github/pull_request_template.md` | Plantilla de Pull Request con lista de verificación de cumplimiento. |
