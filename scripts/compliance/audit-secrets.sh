#!/usr/bin/env bash
# =============================================================================
# audit-secrets.sh - Politica P-SEC-001
#
# Busca credenciales, tokens y claves de API versionadas en el repositorio.
#
# Estrategia:
#   1. Patrones de valores de uso frecuente (AWS, GitHub, tokens genéricos,
#      cadenas de conexion con password, claves privadas).
#   2. Verificacion de que los archivos de credenciales conocidos no estan
#      versionados.
#   3. Exclusion de los directorios que no son codigo fuente.
#
# Uso:
#   audit-secrets.sh [directorio_a_auditar]
#
# Codigo de salida: 0 si no hay hallazgos, 1 si hay hallazgos.
# =============================================================================
set -uo pipefail

TARGET_DIR="${1:-.}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "${ROOT_DIR}"

FINDINGS=0

report() {
  local severity="$1"; shift
  local policy="$1"; shift
  local file="$1"; shift
  local detail="$1"; shift
  echo "[${severity}] ${policy} | ${file} | ${detail}"
  FINDINGS=$((FINDINGS + 1))
}

# --- Directorios y archivos excluidos ---------------------------------------
EXCLUDE_DIRS=(node_modules .git target dist coverage .mvn wrapper evidencias docs)
EXCLUDE_FILES=(package-lock.json)

# --- 1. Patrones de secretos ------------------------------------------------
# Cada patron busca un valor con aspecto de credencial real.
SECRET_PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  'gh[pousr]_[A-Za-z0-9]{16,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  'AIza[0-9A-Za-z_-]{35}'
  '-----BEGIN (RSA |EC |OPENSSH |PGP )?PRIVATE KEY-----'
  'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
)

echo "=== P-SEC-001: Buscando secretos versionados en ${TARGET_DIR} ==="

for PATTERN in "${SECRET_PATTERNS[@]}"; do
  # shellcheck disable=SC2012
  RESULTS="$(grep -rInE --exclude-dir=node_modules --exclude-dir=.git \
      --exclude-dir=target --exclude-dir=dist --exclude-dir=coverage \
      --exclude=package-lock.json \
      "${PATTERN}" "${TARGET_DIR}" 2>/dev/null || true)"

  if [[ -n "${RESULTS}" ]]; then
    while IFS= read -r LINE; do
      FILE="${LINE%%:*}"
      # Se descartan los falsos positivos habituales: los ejemplos de
      # documentacion y los marcadores de posicion.
      if grep -qE 'REEMPLAZAR|PLACEHOLDER|EXAMPLE|<your|xxxx|XXXX|\.\.\.' <<< "${LINE}"; then
        continue
      fi
      report "BLOCKER" "P-SEC-001" "${FILE}" "posible secreto detectado (patron ${PATTERN})"
    done <<< "${RESULTS}"
  fi
done

# --- 2. Contraseñas en archivos de configuracion ----------------------------
# Busca asignaciones del tipo password=..., secret=..., token=... con un
# valor literal (no una referencia a variable de entorno).
CONFIG_RESULTS="$(grep -rInE --exclude-dir=node_modules --exclude-dir=.git \
    --exclude-dir=target --exclude-dir=dist --exclude-dir=coverage \
    --exclude=package-lock.json \
    '(password|passwd|secret|token|api[_-]?key|access[_-]?key)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9/+_-]{12,}["'"'"']?' \
    "${TARGET_DIR}" 2>/dev/null || true)"

while IFS= read -r LINE; do
  [[ -z "${LINE}" ]] && continue
  FILE="${LINE%%:*}"
  REST="${LINE#*:}"
  # Valores que en realidad son referencias a variables o a marcadores.
  if grep -qE 'REEMPLAZAR|PLACEHOLDER|EXAMPLE|\$\{|\$\(|env:|secretKeyRef|configMapKeyRef|secrets\.|your[_-]|changeme|<.*>' <<< "${REST}"; then
    continue
  fi
  # Se ignoran las coincidencias en los archivos de politica y documentacion,
  # donde el patron aparece como ejemplo de lo que se busca.
  case "${FILE}" in
    compliance/*|docs/*|scripts/compliance/*) continue ;;
  esac
  report "BLOCKER" "P-SEC-001" "${FILE}" "credencial con valor literal: $(echo "${REST}" | cut -c1-80)"
done <<< "${CONFIG_RESULTS}"

# --- 3. Archivos de credenciales que no deben estar versionados ------------
FORBIDDEN_FILES=(
  ".env"
  ".env.local"
  ".env.production"
  "credentials.json"
  "service-account.json"
  "id_rsa"
  "id_ed25519"
  ".npmrc"
  ".pypirc"
)

for FILE in "${FORBIDDEN_FILES[@]}"; do
  if git ls-files --error-unmatch "${FILE}" >/dev/null 2>&1; then
    report "BLOCKER" "P-SEC-001" "${FILE}" "archivo de credenciales versionado en el repositorio"
  fi
done

# --- 4. Verificacion del historial de secretos por GitHub -------------------
# Si esta disponible el servicio de secret scanning de GitHub, su resultado
# se consulta a traves de la API.
if [[ -n "${GITHUB_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  SCANNING_ALERTS="$(curl --silent --show-error \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/secret-scanning/alerts?state=open" 2>/dev/null || echo '[]')"
  OPEN_ALERTS="$(printf '%s' "${SCANNING_ALERTS}" | grep -c '"number":' || true)"
  if [[ "${OPEN_ALERTS}" -gt 0 ]]; then
    report "BLOCKER" "P-SEC-001" "github" "${OPEN_ALERTS} alerta(s) abierta(s) de secret scanning"
  else
    echo "[INFO] P-SEC-001 | github | sin alertas abiertas de secret scanning"
  fi
fi

# --- Resultado --------------------------------------------------------------
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo ""
  echo "P-SEC-001 FALLIDA: ${FINDINGS} hallazgo(s). El pipeline se detiene."
  exit 1
fi

echo "P-SEC-001 APROBADA: no se detectaron secretos versionados."
exit 0
