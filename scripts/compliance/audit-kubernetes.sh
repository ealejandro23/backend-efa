#!/usr/bin/env bash
# =============================================================================
# audit-kubernetes.sh - Politica P-SEC-004
#
# Verifica que los manifiestos de Kubernetes declaren un contexto de
# seguridad adecuado para cada pod:
#   1. runAsNonRoot: true y un UID distinto de 0.
#   2. seccompProfile configurado.
#   3. allowPrivilegeEscalation: false.
#   4. Capabilities reducidas (drop ALL).
#   5. Limites de recursos (requests y limits) declarados.
#   6. Probes de liveness y readiness presentes.
#   7. Sin modo privilegiado ni montaje del socket de Docker.
#
# Uso:
#   audit-kubernetes.sh [directorio_de_manifiestos]
# =============================================================================
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

TARGET_DIR="${1:-infra/k8s}"
FINDINGS=0

report() {
  echo "[BLOCKER] P-SEC-004 | $1 | $2"
  FINDINGS=$((FINDINGS + 1))
}

echo "=== P-SEC-004: Auditoria de seguridad de los manifiestos de Kubernetes ==="

# -----------------------------------------------------------------------------
# Analiza un documento YAML de un manifiesto.
# -----------------------------------------------------------------------------
process_document() {
  local DOCUMENT="$1"
  local MANIFEST="$2"
  local DOC_INDEX="$3"

  local KIND NAME LABEL CONTAINER_BLOCKS CONTAINER_COUNT RESOURCE_BLOCKS
  local IN_CONTAINERS=0 LINE

  KIND="$(grep -m1 -E '^kind:' <<< "${DOCUMENT}" | awk '{print $2}')"
  [[ -z "${KIND}" ]] && return 0

  case "${KIND}" in
    Deployment|StatefulSet|DaemonSet|Job|CronJob) ;;
    *) return 0 ;;
  esac

  NAME="$(grep -m1 -E '^  name:' <<< "${DOCUMENT}" | awk '{print $2}')"
  LABEL="${MANIFEST}[doc ${DOC_INDEX}] ${KIND}/${NAME}"

  # --- 1. Contexto de seguridad a nivel de pod ------------------------------
  if ! grep -qE 'runAsNonRoot:[[:space:]]*true' <<< "${DOCUMENT}"; then
    report "${LABEL}" "falta runAsNonRoot: true en el contexto de seguridad del pod"
  fi

  if grep -qE 'runAsUser:[[:space:]]*0[[:space:]]*$' <<< "${DOCUMENT}"; then
    report "${LABEL}" "el pod se ejecuta con runAsUser 0 (root)"
  fi

  if ! grep -qE 'seccompProfile' <<< "${DOCUMENT}"; then
    report "${LABEL}" "falta seccompProfile en el contexto de seguridad del pod"
  fi

  # --- 2. Contexto de seguridad a nivel de contenedor ------------------------
  # El bloque "containers" se extrae respetando la sangria: termina cuando
  # aparece otra clave del mismo nivel (por ejemplo "volumes:").
  CONTAINER_BLOCKS="$(awk '
    BEGIN { in_c = 0; c_indent = -1 }
    {
      if ($0 ~ /^[[:space:]]*containers:[[:space:]]*$/) {
        in_c = 1
        match($0, /^[[:space:]]*/)
        c_indent = RLENGTH
        next
      }
      if (in_c) {
        if ($0 ~ /^[[:space:]]*[a-zA-Z]+:[[:space:]]*$/) {
          match($0, /^[[:space:]]*/)
          if (RLENGTH <= c_indent) { in_c = 0; next }
        }
        print
      }
    }
  ' <<< "${DOCUMENT}")"

  if ! grep -qE 'allowPrivilegeEscalation:[[:space:]]*false' <<< "${CONTAINER_BLOCKS}"; then
    report "${LABEL}" "falta allowPrivilegeEscalation: false en algun contenedor"
  fi

  if ! grep -qE 'drop:' <<< "${CONTAINER_BLOCKS}" || ! grep -qE 'ALL' <<< "${CONTAINER_BLOCKS}"; then
    report "${LABEL}" "falta drop: [ALL] en las capabilities de algun contenedor"
  fi

  if grep -qE 'privileged:[[:space:]]*true' <<< "${DOCUMENT}"; then
    report "${LABEL}" "el pod declara privileged: true"
  fi

  if grep -qE 'docker\.sock' <<< "${DOCUMENT}"; then
    report "${LABEL}" "el pod monta el socket de Docker"
  fi

  if grep -qE 'hostNetwork:[[:space:]]*true|hostPID:[[:space:]]*true|hostIPC:[[:space:]]*true' <<< "${DOCUMENT}"; then
    report "${LABEL}" "el pod comparte el espacio de nombres del host (hostNetwork/hostPID/hostIPC)"
  fi

  # --- 3. Limites de recursos -----------------------------------------------
  # Los contenedores se cuentan por el "- name:" del primer nivel del bloque
  # "containers". Las entradas de "env:" tambien empiezan por "- name:", pero
  # con una indentacion mayor, de modo que se descartan por la sangria.
  CONTAINER_INDENT=""
  while IFS= read -r LINE; do
    if [[ "${LINE}" =~ ^([[:space:]]*)-[[:space:]]name: ]]; then
      CONTAINER_INDENT="${BASH_REMATCH[1]}"
      break
    fi
  done <<< "${CONTAINER_BLOCKS}"

  CONTAINER_COUNT=0
  RESOURCE_BLOCKS=0
  if [[ -n "${CONTAINER_INDENT}" ]]; then
    CONTAINER_COUNT="$(grep -cE "^${CONTAINER_INDENT}-[[:space:]]name:" <<< "${CONTAINER_BLOCKS}" || true)"
    RESOURCE_BLOCKS="$(grep -cE '^[[:space:]]*resources:' <<< "${CONTAINER_BLOCKS}" || true)"
  fi

  if [[ "${CONTAINER_COUNT}" -gt 0 && "${RESOURCE_BLOCKS}" -lt "${CONTAINER_COUNT}" ]]; then
    report "${LABEL}" "hay contenedores sin bloque 'resources' (requests y limits obligatorios)"
  fi

  if [[ "${CONTAINER_COUNT}" -gt 0 ]] && ! grep -qE '^[[:space:]]+limits:' <<< "${CONTAINER_BLOCKS}"; then
    report "${LABEL}" "no se declaran limites de recursos"
  fi

  # --- 4. Sondas de salud ----------------------------------------------------
  if ! grep -qE 'livenessProbe:' <<< "${DOCUMENT}"; then
    report "${LABEL}" "falta la sonda livenessProbe"
  fi

  if ! grep -qE 'readinessProbe:' <<< "${DOCUMENT}"; then
    report "${LABEL}" "falta la sonda readinessProbe"
  fi

  echo "  [INFO] ${LABEL} auditado"
}

MANIFESTS=()
while IFS= read -r FILE; do
  MANIFESTS+=("${FILE}")
done < <(find "${TARGET_DIR}" -name "*.yaml" -not -path "*/overlays/*" | sort)

for MANIFEST in "${MANIFESTS[@]}"; do
  # Se procesa cada documento del manifiesto por separado. La separacion se
  # hace en bash (y no con awk) para que un "---" dentro de un bloque no
  # desplace el contenido de los demas documentos.
  DOC_INDEX=0
  DOCUMENT=""
  IN_DOCUMENT=0

  while IFS= read -r LINE || [[ -n "${LINE}" ]]; do
    if [[ "${LINE}" =~ ^---[[:space:]]*$ ]]; then
      # Fin del documento actual.
      if [[ "${IN_DOCUMENT}" -eq 1 ]]; then
        DOC_INDEX=$((DOC_INDEX + 1))
        process_document "${DOCUMENT}" "${MANIFEST}" "${DOC_INDEX}"
      fi
      DOCUMENT=""
      IN_DOCUMENT=1
      continue
    fi
    if [[ "${IN_DOCUMENT}" -eq 1 ]]; then
      DOCUMENT="${DOCUMENT}${LINE}"$'\n'
    fi
  done < "${MANIFEST}"

  # Ultimo documento del archivo.
  if [[ "${IN_DOCUMENT}" -eq 1 && -n "${DOCUMENT}" ]]; then
    DOC_INDEX=$((DOC_INDEX + 1))
    process_document "${DOCUMENT}" "${MANIFEST}" "${DOC_INDEX}"
  fi
done

echo ""
if [[ "${FINDINGS}" -gt 0 ]]; then
  echo "P-SEC-004 FALLIDA: ${FINDINGS} hallazgo(s). El pipeline se detiene."
  exit 1
fi

echo "P-SEC-004 APROBADA: los manifiestos cumplen la politica de seguridad."
exit 0
