x
exit
exit
# Estrategia de ramificación, convenciones y trazabilidad

Este documento describe cómo el equipo organiza el repositorio
`backend-efa`: los modelos de ramificación evaluados, las ramas que se
usan y para qué, las convenciones de commits y pull requests, los
comandos del flujo y cómo se rastrea un cambio desde el commit hasta el
despliegue.

Indicadores de la EFT relacionados: IE1, IE2, IE3 e IE5.

---

## 1. Modelos de ramificación

| Modelo | Ramas | Cómo se integra un cambio | Se adapta mejor a |
|---|---|---|---|
| **Git Flow** | `main`, `develop`, `feature/*`, `release/*`, `hotfix/*` | Las funcionalidades se integran en `develop`; una `release/*` estabiliza la versión y se fusiona en `main`; un `hotfix/*` sale de `main` y vuelve a `main` y a `develop`. | Productos con versiones planificadas y varias versiones en mantenimiento. |
| **GitHub Flow** | `main` y ramas cortas por cambio | Cada cambio sale de `main` en una rama corta, se revisa en un pull request con checks automáticos y vuelve a `main`, que siempre se puede desplegar. | Servicios web con despliegue continuo. |
| **Trunk-based development** | `main` (*trunk*) y ramas de horas o un par de días | Integraciones muy frecuentes y pequeñas en el tronco, apoyadas en pruebas automáticas y *feature flags*. | Equipos con CI muy maduro y alta frecuencia de integración. |
| **GitLab Flow** | `main` más ramas de entorno (`staging`, `production`) | Los cambios avanzan de una rama de entorno a la siguiente. | Equipos que promueven versiones entre entornos mediante ramas. |

Diferencias que importan en un entorno colaborativo en la nube:

- **Duración de las ramas:** Git Flow mantiene ramas largas (`develop`,
  `release/*`); GitHub Flow y trunk-based usan ramas cortas, que generan
  menos conflictos.
- **Punto de despliegue:** en Git Flow se despliega desde `main` después
  de una *release*; en GitHub Flow y trunk-based, cada merge a `main` es
  candidato a despliegue.
- **Dependencia del CI:** cuanto más corta la rama, más se depende de que
  las pruebas, el análisis y las políticas automáticas detengan los
  cambios defectuosos antes del merge.

---

## 2. Ramas del proyecto

| Rama | Propósito | Origen → destino | Protección |
|---|---|---|---|
| `main` | Código estable y desplegable. Cada merge dispara CI, cumplimiento y CD. | — | PR obligatorio con 1 aprobación, 2 checks obligatorios, rama al día, historial lineal, sin *force push*, sin borrado y sin bypass de administradores. |
| `develop` | Integración de funcionalidades (etapa Git Flow del semestre). Un push dispara `ci.yml`. | — | — |
| `feature/<descripcion>` | Una funcionalidad o mejora. | `main` (o `develop`) → PR | Pasa por los checks del PR |
| `hotfix/<descripcion>` | Corrección urgente de producción (por ejemplo, seguridad). | `main` → PR a `main` | Igual que `feature/*` |
| `release/<version>` | Estabilización de una versión antes de pasar a `main`. | `develop` → `main` | — |
| `fix/<descripcion>` | Corrección no urgente. | `main` → PR | — |
| `docs/<descripcion>` | Solo documentación. | `main` → PR | — |
| `dependabot/*` | Actualizaciones automáticas de dependencias. | Las crea Dependabot | Revisión del CI antes del merge |

Despliegue a producción: además de la protección de `main`, el job
**Deploy en EC2** usa el *environment* `production`, que exige la
aprobación de un revisor distinto de quien disparó el despliegue y solo
acepta ramas protegidas.

---

## 3. Flujo aplicado (evidencia en el historial)

### 3.1 Git Flow (Evaluaciones Parciales 1 y 2)

| PR | Rama | Tipo de cambio |
|---|---|---|
| #1 | `feature/mejora-busqueda` | Funcionalidad → `develop` |
| #2 | `feature/resumen-ventas` | Funcionalidad → `develop` |
| #3 | `feature/documentacion-devops` | Documentación → `develop` |
| #4 | `hotfix/correccion-validacion-stock` | Hotfix → `main`, propagado a `develop` (commit `55479fe`) |
| #5 | `develop` | Integración → `main` |
| #7 | `feature/validacion-producto` | Funcionalidad |
| #8 | `release/v1.x` | Versión → `main` |

### 3.2 Ramas cortas sobre `main` protegida (EP3 y EFT)

| PR | Rama | Cambio |
|---|---|---|
| #22 | `docs/alinear-branch-protection` | Documentación del cumplimiento |
| #23 | `feat/ep3-aws-observabilidad` | Kubernetes en AWS con observabilidad |
| #24 | `fix/sonar-seguridad` | Hallazgos de seguridad de SonarCloud |
| #27 | `feature/pruebas-en-contenedor` | Pruebas unitarias dentro del contenedor |
| #28 | `hotfix/dependencias-vulnerables` | **Hotfix de seguridad**: 7 vulnerabilidades críticas y 7 altas que detuvieron el pipeline |
| #29 | `feature/publicar-docker-hub` | Publicación de la imagen en Docker Hub |
| #30 | `feature/aprobacion-despliegue` | Aprobación obligatoria para desplegar |
| #31 | `feature/pruebas-aceptacion` | Pruebas de aceptación antes de producción |
| #32 | `feature/cloudwatch` | Métricas y logs en AWS CloudWatch |

Cada uno de estos PR pasó los checks obligatorios y fue aprobado por un
integrante distinto del autor antes del *squash and merge*.

---

## 4. Comandos del flujo

### 4.1 Nueva funcionalidad

```bash
git fetch origin
git checkout -b feature/<descripcion> origin/main     # rama corta desde main
# ... cambios ...
git add <archivos>                                      # nunca "git add ." a ciegas
git commit -m "feat(<area>): <que cambia>"              # Conventional Commits
git push -u origin feature/<descripcion>
gh pr create --base main --head feature/<descripcion>  # abre el PR y dispara el CI
gh pr checks <numero> --watch                           # espera los checks
# otro integrante revisa y aprueba; luego:
gh pr merge <numero> --squash --delete-branch
```

### 4.2 Hotfix

```bash
git checkout -b hotfix/<descripcion> origin/main
# ... correccion minima ...
git commit -m "fix(<area>): <que corrige y por que>"
git push -u origin hotfix/<descripcion>
gh pr create --base main --head hotfix/<descripcion>
```

Si hay PR abiertos que dependen de la corrección, se actualizan después
del merge:

```bash
gh pr update-branch <numero>    # incorpora el main corregido a la rama del PR
```

Ejemplo real: el PR #27 quedó bloqueado por Snyk; el hotfix #28 se
fusionó primero y `gh pr update-branch 27` dejó el #27 en verde.

---

## 5. Convenciones

### 5.1 Commits (Conventional Commits)

Formato: `tipo(ámbito): descripción en minúsculas`, con un cuerpo que
explica el **qué** y el **por qué** cuando el cambio no es trivial.

| Tipo | Uso | Ejemplo del repositorio |
|---|---|---|
| `feat` | Funcionalidad nueva | `feat(observabilidad): metricas y logs del backend en AWS CloudWatch` |
| `fix` | Corrección | `fix(deps): corregir 7 vulnerabilidades criticas y 7 altas en dependencias` |
| `ci` | Pipelines y automatización | `ci(cd): pruebas de aceptacion obligatorias antes de desplegar a produccion` |
| `docs` | Documentación | `docs(cumplimiento): alinear la politica de rama con la configuracion real` |
| `test` | Pruebas | `test: agregar pruebas de cobertura para calculo de ventas` |
| `security` | Seguridad | `security(snyk): excepcion temporal documentada para OpenJDK sin parche` |
| `chore` | Mantenimiento | `chore(deps): bump actions/checkout from 4 to 7` |

### 5.2 Pull requests

- Un PR por cambio, con un título en formato Conventional Commits.
- La descripción indica qué cambia, cómo se verificó y qué requisito
  cubre.
- No se fusiona sin los checks en verde y sin la aprobación de otro
  integrante; el autor no puede aprobar su propio PR.
- Se integra con **squash and merge**: un commit por PR en `main`, lo que
  mantiene el historial lineal y legible.
- La rama se elimina después del merge.

### 5.3 Nombres de ramas

`<tipo>/<descripcion-en-minusculas-con-guiones>`, por ejemplo
`feature/pruebas-aceptacion` o `hotfix/dependencias-vulnerables`.

---

## 6. Trazabilidad de un cambio

Ejemplo con el PR #29:

| Paso | Evidencia |
|---|---|
| Commit | `7563dc5` en `main` (squash del PR #29) |
| Revisión | PR #29 aprobado por un integrante distinto del autor |
| Verificación | CI, cumplimiento, SonarCloud y Snyk del commit en verde |
| Artefacto | Imagen `felipensio/efa-backend:7563dc5` en Docker Hub (además de `latest`) |
| Despliegue | El CD despliega exactamente ese SHA (`needs.gate.outputs.commit_sha`) |
| Ejecución | Etiquetas `commit` y `version` en las métricas de Prometheus y en los logs |

---

## 7. Historial anterior a la convención

`main` tiene 107 commits; 45 siguen Conventional Commits. Los commits que
no la siguen (por ejemplo `Update deploy.yml` o `intento 100`) son de las
primeras semanas, cuando se editaba desde la interfaz web de GitHub. No se
reescribieron porque la protección de `main` prohíbe el *force push* y
porque reescribir un historial compartido rompe la trazabilidad. Desde la
EP3 todos los cambios entran por PR con mensajes descriptivos.

---

## 8. Justificación de la estrategia

> **Esta sección la redacta el equipo, sin apoyo de IA**, como exige la
> pauta (las justificaciones técnicas son de autoría propia).
>
> Preguntas que debe responder:
> - ¿Por qué empezaron con Git Flow y por qué, desde la EP3, trabajan con
>   ramas cortas sobre `main` protegida?
> - ¿Qué ventaja concreta les dio cada enfoque en este proyecto (por
>   ejemplo, el hotfix #28)?
> - ¿Por qué descartaron trunk-based development y GitLab Flow?

[Justificación del equipo]
