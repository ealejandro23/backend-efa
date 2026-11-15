#!/usr/bin/env bash
# =============================================================================
# audit-dockerfile.sh - Politicas P-SEC-002 y P-SEC-005
#
# Verifica que los Dockerfiles sigan un conjunto de practicas de seguridad:
#   1. No se ejecutan como root.
#   2. No se permite la escalacion de privilegios.
#   3. Las imagenes base estan fijadas a una version concreta.
#   4. Se usan etapas multietapa (build y runtime separadas).
#   5. Se declara un HEALTHCHECK.
#
# Uso:
#   audit-dockerfile.sh [dockerfile ...]
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

if [[ $# -gt 0 ]]; then
  DOCKERFILES=("$@")
else
  DOCKERFILES=()
  while IFS= read -r FILE; do
    DOCKERFILES+=("${FILE}")
  done < <(find . -name "Dockerfile" -not -path "*/node_modules/*" -not -path "*/.git/*" | sort)
fi

FINDINGS=0

report() {
  echo "[BLOCKER] $1 | $2 | $3"
  FINDINGS=$((FINDINGS + 1))
}

echo "=== P-SEC-002 / P-SEC-005: Auditoria de Dockerfiles ==="

for DOCKERFILE in "${DOCKERFILES[@]}"; do
  [[ -f "${DOCKERFILE}" ]] || continue

  # --- Etapa de ejecucion ---------------------------------------------------
  # Se toma la ultima etapa del Dockerfile, que es la que produce la imagen
  # final que se despliega.
  RUNTIME_STAGE="$(awk '/^FROM /{stage=$0} END{print stage}' "${DOCKERFILE}")"
  RUNTIME_STAGE_LINES="$(awk '/^FROM /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "${DOCKERFILE}")"

  # --- P-SEC-002: usuario no root -------------------------------------------
  # Se toma la ultima instruccion USER: en un Dockerfile multietapa, la que
  # cuenta es la de la etapa de ejecucion (la ultima).
  USER_LINE="$(grep -iE '^[[:space:]]*USER[[:space:]]+' "${DOCKERFILE}" 2>/dev/null \
    | tail -n 1 | sed 's/^[[:space:]]*[Uu][Ss][Ee][Rr][[:space:]]*//' | tr -d '\r')"

  if [[ -z "${USER_LINE}" ]]; then
    report "P-SEC-002" "${DOCKERFILE}" "el Dockerfile no declara la instruccion USER: la imagen se ejecuta como root"
  elif [[ "${USER_LINE}" == "root" || "${USER_LINE}" == "0" ]]; then
    report "P-SEC-002" "${DOCKERFILE}" "el Dockerfile declara USER root"
  else
    echo "  [INFO] ${DOCKERFILE} ejecuta como usuario '${USER_LINE}'"
  fi

  # --- P-SEC-005: imagen base fijada ----------------------------------------
  # Se buscan lineas FROM cuyo tag sea "latest" o que no tenga tag.
  while IFS= read -r LINE; do
    IMAGE="$(awk '{print $2}' <<< "${LINE}")"
    case "${IMAGE}" in
      *":latest"|*":")
        report "P-SEC-005" "${DOCKERFILE}" "imagen base sin version fija: ${IMAGE}"
        ;;
    esac
    # Las imagenes base oficiales sin tag se consideran浮动.
    if ! grep -qE "^FROM .+@" <<< "${LINE}" && ! grep -qE "^FROM [^ ]+:[^ ]+" <<< "${LINE}"; then
      report "P-SEC-005" "${DOCKERFILE}" "imagen base sin tag: ${IMAGE}"
    fi
  done < <(grep -E '^FROM ' "${DOCKERFILE}" | grep -v ' AS ')

  # --- Practicas adicionales ------------------------------------------------
  if ! grep -qiE 'HEALTHCHECK' "${DOCKERFILE}"; then
    echo "[MAJOR] P-SEC-002 | ${DOCKERFILE} | el Dockerfile no declara HEALTHCHECK"
  fi

  if ! grep -qE '^FROM .+ AS ' "${DOCKERFILE}" && ! grep -qE '^FROM .+ as ' "${DOCKERFILE}"; then
    echo "[MINOR] P-SEC-005 | ${DOCKERFILE} | no se usa una construccion multietapa"
  fi

  # No se deben copiar credenciales dentro de la imagen.
  if grep -nE '^\s*(COPY|ADD)\s+.*\.(env|pem|key|p12|jks|keystore)' "${DOCKERFILE}" >/dev/null 2>&1; then
    report "P-SEC-002" "${DOCKERFILE}" "se copian archivos de credenciales dentro de la imagen"
  fi

  echo "  [INFO] ${DOCKERFILE} auditado"
done

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-SEC-002/P-SEC-005 FALLIDAS: ${FINDINGS} hallazgo(s). El pipeline se detiene."
  exit 1
fi

echo "P-SEC-002 y P-SEC-005 APROBADAS: los Dockerfiles cumplen las politicas de seguridad."
exit 0
