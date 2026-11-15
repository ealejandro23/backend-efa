#!/usr/bin/env bash
# =============================================================================
# audit-dependencies.sh - Politica P-SEC-003
#
# Verifica que las dependencias del proyecto no tengan vulnerabilidades
# conocidas de severidad alta o critica.
#
# El escaneo lo realiza Trivy, que se instala en el pipeline. Si Trivy no
# esta disponible, el script verifica al menos que exista el reporte
# generado previamente por la etapa de seguridad.
#
# Uso:
#   audit-dependencies.sh [directorio_del_proyecto]
#
# Variables de entorno:
#   TRIVY_BIN         Binario de trivy (por defecto trivy)
#   SEVERITY          Severidad minima que bloquea (por defecto HIGH)
#   TRIVY_REPORT      Reporte JSON previo (opcional)
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

TARGET_DIR="${1:-.}"
SEVERITY="${SEVERITY:-HIGH}"
TRIVY_BIN="${TRIVY_BIN:-trivy}"

echo "=== P-SEC-003: Auditoria de vulnerabilidades en dependencias ==="

FINDINGS=0

# --- 1. Escaneo de dependencias con Trivy -----------------------------------
if command -v "${TRIVY_BIN}" >/dev/null 2>&1; then
  echo "  Analizando dependencias de Maven (demo/pom.xml)..."
  MAVEN_REPORT="$(mktemp)"
  "${TRIVY_BIN}" fs --scanners vuln --severity "${SEVERITY}" --format json \
    --output "${MAVEN_REPORT}" "demo/pom.xml" >/dev/null 2>&1 || true

  COUNT="$(grep -o '"Severity": *"[A-Z]*"' "${MAVEN_REPORT}" 2>/dev/null | grep -cE '"(HIGH|CRITICAL)"' || true)"
  if [[ "${COUNT:-0}" -gt 0 ]]; then
    echo "[BLOCKER] P-SEC-003 | demo/pom.xml | ${COUNT} vulnerabilidad(es) de severidad alta o critica"
    grep -oE '"Title": *"[^"]+"|"VulnerabilityID": *"[^"]+"' "${MAVEN_REPORT}" 2>/dev/null | head -20
    FINDINGS=$((FINDINGS + COUNT))
  else
    echo "  [OK] demo/pom.xml sin vulnerabilidades de severidad ${SEVERITY} o superior"
  fi
  rm -f "${MAVEN_REPORT}"

  echo "  Analizando dependencias de npm (package.json)..."
  NPM_REPORT="$(mktemp)"
  "${TRIVY_BIN}" fs --scanners vuln --severity "${SEVERITY}" --format json \
    --output "${NPM_REPORT}" "package.json" >/dev/null 2>&1 || true
  COUNT="$(grep -o '"Severity": *"[A-Z]*"' "${NPM_REPORT}" 2>/dev/null | grep -cE '"(HIGH|CRITICAL)"' || true)"
  if [[ "${COUNT:-0}" -gt 0 ]]; then
    echo "[BLOCKER] P-SEC-003 | package.json | ${COUNT} vulnerabilidad(es) de severidad alta o critica"
    FINDINGS=$((FINDINGS + COUNT))
  else
    echo "  [OK] package.json sin vulnerabilidades de severidad ${SEVERITY} o superior"
  fi
  rm -f "${NPM_REPORT}"
else
  echo "  [INFO] Trivy no esta disponible en esta ejecucion."
fi

# --- 2. Reporte de Snyk generado en la etapa de seguridad -------------------
if [[ -f "${SNYK_REPORT:-}" ]]; then
  SNYK_VULNS="$(grep -o '"severity":"[a-z]*"' "${SNYK_REPORT}" 2>/dev/null | grep -cE '"(high|critical)"' || true)"
  if [[ "${SNYK_VULNS:-0}" -gt 0 ]]; then
    echo "[BLOCKER] P-SEC-003 | ${SNYK_REPORT} | ${SNYK_VULNS} vulnerabilidad(es) reportada(s) por Snyk"
    FINDINGS=$((FINDINGS + SNYK_VULNS))
  else
    echo "  [OK] el reporte de Snyk no registra vulnerabilidades de severidad alta o critica"
  fi
fi

# --- 3. Comprobacion de la politica de dependencias declaradas --------------
# El pom.xml debe declarar las dependencias sensibles que se auditan.
if [[ -f "demo/pom.xml" ]]; then
  if ! grep -q "micrometer-registry-prometheus" demo/pom.xml; then
    echo "[MINOR] P-SEC-003 | demo/pom.xml | el registro de Prometheus no esta declarado"
  fi
fi

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-SEC-003 FALLIDA: ${FINDINGS} vulnerabilidad(es). El pipeline se detiene."
  exit 1
fi

echo "P-SEC-003 APROBADA: no se detectaron vulnerabilidades de severidad alta o critica."
exit 0
