#!/usr/bin/env bash
# =============================================================================
# acceptance-tests.sh - Pruebas de aceptacion de la API del backend EFA
#
# Se ejecutan en el CD (deploy.yml, job "Pruebas de aceptacion") contra la
# imagen candidata ya construida, levantada con su base de datos PostgreSQL
# real mediante Docker Compose. Si alguna falla, el pipeline no publica la
# imagen ni pide la aprobacion para desplegar a produccion.
#
# A diferencia de las pruebas unitarias (JUnit con H2), estas pruebas
# validan el artefacto final tal como se va a desplegar: la imagen Docker,
# el perfil "prod", PostgreSQL y la API HTTP de punta a punta.
#
# Uso:
#   scripts/ci/acceptance-tests.sh [URL_BASE]     (por defecto http://localhost:8083)
# =============================================================================
set -euo pipefail

BASE_URL="${1:-http://localhost:8083}"
CODIGO="ACC-${GITHUB_SHA:-local}"
CODIGO="${CODIGO:0:20}"
RESP="$(mktemp)"
PASS=0
FAIL=0

# req METODO RUTA [CUERPO_JSON] -> imprime el codigo HTTP; el cuerpo queda en $RESP
req() {
  local metodo="$1" ruta="$2" cuerpo="${3:-}"
  if [[ -n "${cuerpo}" ]]; then
    curl -s -o "${RESP}" -w '%{http_code}' -X "${metodo}" \
      -H 'Content-Type: application/json' -d "${cuerpo}" "${BASE_URL}${ruta}"
  else
    curl -s -o "${RESP}" -w '%{http_code}' -X "${metodo}" "${BASE_URL}${ruta}"
  fi
}

# check DESCRIPCION ESPERADO OBTENIDO
check() {
  if [[ "$2" == "$3" ]]; then
    echo "  OK     $1"
    PASS=$((PASS + 1))
  else
    echo "  FALLA  $1 (esperado: $2, obtenido: $3)"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Pruebas de aceptacion contra ${BASE_URL} ==="

# A1. El servicio esta disponible
CODE="$(req GET /actuator/health)"
check "A1 /actuator/health responde 200" 200 "${CODE}"
check "A1 el estado de salud es UP" UP "$(jq -r '.status' "${RESP}" 2>/dev/null || echo invalido)"

# A2. El catalogo de productos se puede consultar
CODE="$(req GET /api/v1/productos)"
check "A2 GET /api/v1/productos responde 200" 200 "${CODE}"

# A3. Se puede crear un producto valido (escribe en PostgreSQL)
CODE="$(req POST /api/v1/productos \
  "{\"nombre\":\"Producto aceptacion\",\"descripcion\":\"prueba del pipeline\",\"precio\":4990.0,\"stock\":5,\"codigo\":\"${CODIGO}\"}")"
check "A3 POST /api/v1/productos valido responde 201" 201 "${CODE}"
ID="$(jq -r '.id // empty' "${RESP}" 2>/dev/null || true)"

# A4. El producto creado se recupera con sus datos (lee desde PostgreSQL)
if [[ -n "${ID}" ]]; then
  CODE="$(req GET "/api/v1/productos/${ID}")"
  check "A4 GET /api/v1/productos/${ID} responde 200" 200 "${CODE}"
  check "A4 el producto conserva su codigo" "${CODIGO}" "$(jq -r '.codigo' "${RESP}")"
  check "A4 el producto conserva su stock" 5 "$(jq -r '.stock' "${RESP}")"
else
  check "A4 el alta devolvio un id" "un id" "sin id"
fi

# A5. La API rechaza datos invalidos
CODE="$(req POST /api/v1/productos '{"nombre":"","precio":100.0}')"
check "A5 POST /api/v1/productos sin nombre responde 400" 400 "${CODE}"

# A6. Un recurso inexistente responde 404
CODE="$(req GET /api/v1/productos/999999)"
check "A6 GET /api/v1/productos/999999 responde 404" 404 "${CODE}"

# A7. Una ruta inexistente responde 404
CODE="$(req GET /api/v1/ruta-inexistente)"
check "A7 GET /api/v1/ruta-inexistente responde 404" 404 "${CODE}"

# A8. El servicio expone sus metricas para el monitoreo
CODE="$(req GET /actuator/prometheus)"
check "A8 /actuator/prometheus responde 200" 200 "${CODE}"
if grep -q '^efa_availability_up' "${RESP}"; then
  check "A8 expone la metrica efa_availability_up" si si
else
  check "A8 expone la metrica efa_availability_up" si no
fi

rm -f "${RESP}"
echo "=== Resultado: ${PASS} aprobadas, ${FAIL} fallidas ==="

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "### Pruebas de aceptacion"
    echo "- Aprobadas: ${PASS}"
    echo "- Fallidas: ${FAIL}"
  } >> "${GITHUB_STEP_SUMMARY}"
fi

if [[ "${FAIL}" -gt 0 ]]; then
  echo "::error::Fallaron ${FAIL} pruebas de aceptacion. No se publica ni se despliega."
  exit 1
fi
