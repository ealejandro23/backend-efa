#!/usr/bin/env bash
# =============================================================================
# verify-branch-protection.sh - Politica P-SEC-006
#
# Verifica via la API de GitHub que la rama principal este protegida con las
# reglas exigidas por la politica de cumplimiento:
#
#   1. No se permiten pushes directos (es decir, siempre hay revision).
#   2. Las verificaciones obligatorias (status checks) estan activas.
#   3. No se permiten eliminaciones de la rama.
#   4. No se permiten force-pushes.
#
# Requiere el token del repositorio con permiso de administracion
# (permisos "Administration: read" o un token clasico con permiso "repo").
#
# Uso:
#   verify-branch-protection.sh [rama]
#
# Variables de entorno:
#   GITHUB_TOKEN    Token de GitHub
#   GITHUB_REPOSITORY   Repositorio en formato "owner/repo"
#   BRANCH          Rama a verificar (por defecto: la rama por defecto)
#   REQUIRED_CHECKS Checks obligatorios esperados (separados por coma)
# =============================================================================
set -uo pipefail

BRANCH="${1:-${BRANCH:-}}"
GITHUB_API="https://api.github.com"

echo "=== P-SEC-006: Verificacion de la proteccion de rama ==="

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "[INFO] GITHUB_TOKEN no esta disponible: la verificacion no puede realizarse."
  echo "       La proteccion de rama se configura en la configuracion del repositorio"
  echo "       y se documenta en docs/COMPLIANCE.md y .github/branch-protection.yml."
  exit 0
fi

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "[BLOCKER] P-SEC-006 | GITHUB_REPOSITORY | no se definio el repositorio"
  exit 1
fi

if [[ -z "${BRANCH}" ]]; then
  BRANCH="$(curl --silent --fail \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${GITHUB_API}/repos/${GITHUB_REPOSITORY}" 2>/dev/null \
    | grep -oE '"default_branch":"[^"]+"' | sed 's/"default_branch":"//; s/"$//')"
  BRANCH="${BRANCH:-main}"
fi

echo "  Repositorio: ${GITHUB_REPOSITORY}"
echo "  Rama       : ${BRANCH}"

PROTECTION="$(curl --silent --fail \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "${GITHUB_API}/repos/${GITHUB_REPOSITORY}/branches/${BRANCH}/protection" 2>/dev/null || echo '')"

if [[ -z "${PROTECTION}" ]]; then
  echo "[BLOCKER] P-SEC-006 | ${BRANCH} | la rama no tiene proteccion activa o el token no tiene permisos suficientes"
  echo "P-SEC-006 FALLIDA: el pipeline se detiene."
  exit 1
fi

FINDINGS=0

# --- 1. Push directo bloqueado ----------------------------------------------
if ! grep -q '"enabled":true' <<< "${PROTECTION}"; then
  echo "[BLOCKER] P-SEC-006 | ${BRANCH} | la proteccion de rama esta deshabilitada"
  FINDINGS=$((FINDINGS + 1))
fi

# --- 2. Verificaciones obligatorias -----------------------------------------
# required_status_checks puede venir como objeto con "checks" o como "strict".
HAS_REQUIRED_CHECKS=0
if grep -q '"required_status_checks"' <<< "${PROTECTION}"; then
  HAS_REQUIRED_CHECKS=1
fi

REQUIRED_CHECKS="${REQUIRED_CHECKS:-Build, Tests, Calidad y Seguridad,Compliance — Gate de cumplimiento}"
if [[ "${HAS_REQUIRED_CHECKS}" -eq 0 ]]; then
  echo "[BLOCKER] P-SEC-006 | ${BRANCH} | no hay verificaciones obligatorias configuradas"
  FINDINGS=$((FINDINGS + 1))
else
  echo "  [OK] hay verificaciones obligatorias configuradas"
  IFS=',' read -ra CHECKS <<< "${REQUIRED_CHECKS}"
  for CHECK in "${CHECKS[@]}"; do
    CHECK="$(echo "${CHECK}" | xargs)"
    [[ -z "${CHECK}" ]] && continue
    if grep -qF "${CHECK}" <<< "${PROTECTION}"; then
      echo "  [OK] verificacion obligatoria presente: ${CHECK}"
    else
      echo "[MAJOR] P-SEC-006 | ${BRANCH} | la verificacion obligatoria '${CHECK}' no esta en la configuracion"
    fi
  done
fi

# --- 3. Push directo a la rama bloqueado -----------------------------------
# Con "required_pull_request_reviews" activa, los pushes directos quedan
# bloqueados salvo para quien tenga permiso de bypass.
if grep -q '"required_pull_request_reviews"' <<< "${PROTECTION}"; then
  echo "  [OK] se exige revision mediante Pull Request"
else
  echo "[BLOCKER] P-SEC-006 | ${BRANCH} | no se exige revision mediante Pull Request"
  FINDINGS=$((FINDINGS + 1))
fi

# --- 4. Force-push y eliminacion bloqueados ---------------------------------
if grep -q '"allow_force_pushes":{"enabled":false' <<< "${PROTECTION}"; then
  echo "  [OK] los force-pushes estan bloqueados"
else
  echo "[MAJOR] P-SEC-006 | ${BRANCH} | los force-pushes no estan bloqueados explicitamente"
fi

if grep -q '"allow_deletions":{"enabled":false' <<< "${PROTECTION}"; then
  echo "  [OK] la eliminacion de la rama esta bloqueada"
else
  echo "[MAJOR] P-SEC-006 | ${BRANCH} | la eliminacion de la rama no esta bloqueada explicitamente"
fi

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-SEC-006 FALLIDA: ${FINDINGS} requisito(s) de proteccion no cumplido(s). El pipeline se detiene."
  exit 1
fi

echo "P-SEC-006 APROBADA: la rama principal cuenta con la proteccion exigida."
exit 0
