# Gate de cumplimiento — Proyecto EFA

Este directorio contiene el catálogo de políticas de cumplimiento y los
scripts que las verifican de forma automatizada.

La documentación completa (qué significa cada política, por qué se exige y
cómo se integra con el pipeline) está en
[`docs/COMPLIANCE.md`](../docs/COMPLIANCE.md).

---

## Uso rápido

```bash
# Ejecutar todas las políticas y mostrar el informe completo
bash scripts/compliance/run-all.sh --continuar

# Detenerse en la primera política bloqueante incumplida
bash scripts/compliance/run-all.sh

# Evaluar solo un subconjunto
bash scripts/compliance/run-all.sh --solo "P-SEC-001 P-QA-002"
```

Código de salida:

| Código | Significado |
|---|---|
| `0` | Todas las políticas evaluadas se cumplieron (las de severidad `minor` pueden haber fallado: se informan pero no bloquean). |
| `1` | Al menos una política bloqueante fue incumplida. **El pipeline se detiene y no hay despliegue.** |

---

## Estructura

```
compliance/
├── README.md                  Este archivo
└── policies/
    └── catalog.yml            Catálogo de políticas con su justificación

scripts/compliance/
├── run-all.sh                 Gate consolidado (punto de entrada)
├── audit-secrets.sh           P-SEC-001
├── audit-dockerfile.sh        P-SEC-002 y P-SEC-005
├── audit-dependencies.sh      P-SEC-003
├── audit-kubernetes.sh        P-SEC-004
├── verify-branch-protection.sh P-SEC-006
├── audit-coverage.sh          P-QA-002
├── audit-workflows.sh         P-QA-004, P-CI-001, P-CI-002 y P-CI-003
├── audit-observability.sh     P-OBS-001 y P-OBS-002
├── audit-alerts.sh            P-OBS-003, P-OBS-004 y P-OBS-005
└── audit-docs.sh              P-DOC-001 y P-DOC-002
```

---

## Catálogo resumido

| ID | Política | Severidad |
|---|---|---|
| P-SEC-001 | Sin secretos hardcodeados | blocker |
| P-SEC-002 | Contenedores sin privilegios ni root | blocker |
| P-SEC-003 | Dependencias sin vulnerabilidades altas o críticas | blocker |
| P-SEC-004 | Manifiestos Kubernetes con contexto de seguridad | blocker |
| P-SEC-005 | Imágenes base fijadas a una versión | major |
| P-SEC-006 | Protección de rama activa | major |
| P-QA-001 | Quality Gate aprobado | blocker |
| P-QA-002 | Cobertura ≥ 60 % | blocker |
| P-QA-003 | Suite de pruebas en verde | blocker |
| P-QA-004 | Acciones de GitHub fijadas | major |
| P-CI-001 | El despliegue exige verificaciones en verde | blocker |
| P-CI-002 | El despliegue es trazable a un commit verificado | major |
| P-CI-003 | Las etapas de control no toleran fallos | blocker |
| P-OBS-001 | Métricas y sonda de salud expuestas | blocker |
| P-OBS-002 | Descubrimiento automático de métricas | major |
| P-OBS-003 | Sin alertas críticas de disponibilidad | blocker |
| P-OBS-004 | Sin alertas críticas de tasa de errores | blocker |
| P-OBS-005 | Sin alertas críticas de saturación de memoria | blocker |
| P-DOC-001 | Documentación actualizada | minor |
| P-DOC-002 | Uso de IA declarado | minor |

---

## Añadir una política nueva

1. **Declararla** en `compliance/policies/catalog.yml` con su identificador,
   severidad, descripción, script y justificación.
2. **Escribir el script** en `scripts/compliance/` siguiendo el patrón de los
   existentes:
   - mensajes con el prefijo `[BLOCKER] P-XXX-000 | archivo | detalle`,
   - código de salida `0` si se cumple, `1` si se incumple,
   - un bloque `echo` al final que resuma el resultado.
3. **Registrarla** en el array `AUDITS` de `scripts/compliance/run-all.sh`.
4. **Documentarla** en `docs/COMPLIANCE.md`.
5. **Probarla** introduciendo un incumplimiento y confirmando que el gate
   la detecta y bloquea.

---

## Requisitos

| Requisito | Necesario para |
|---|---|
| Bash 4 o superior | Todas las auditorías. |
| `curl` | Consultas a la API de GitHub y a Prometheus. |
| `trivy` (opcional) | `audit-dependencies.sh`. Sin él, la auditoría informa que no pudo evaluar. |
| `GITHUB_TOKEN` | `verify-branch-protection.sh`. Sin él, se omite con aviso. |
| `PROMETHEUS_URL` | `audit-alerts.sh`. Sin Prometheus accesible, se omite con aviso. |
| Reporte de JaCoCo | `audit-coverage.sh` (`demo/target/site/jacoco/jacoco.xml`). |

Los scripts son **portables**: no dependen de `jq` ni de herramientas
específicas de una distribución, para poder ejecutarse tanto en el runner de
GitHub Actions (Ubuntu) como en un entorno local.
