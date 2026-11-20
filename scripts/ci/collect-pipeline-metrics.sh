#!/usr/bin/env bash
# =============================================================================
# collect-pipeline-metrics.sh - Metricas del pipeline CI/CD para Grafana
#
# Los workflows de GitHub Actions publican sus metricas en un Pushgateway que
# corre como service container del runner: al terminar el job, ese Pushgateway
# desaparece junto con las metricas. Este script resuelve esa limitacion
# reconstruyendo las metricas del pipeline desde sus fuentes oficiales y
# publicandolas en el Pushgateway PERSISTENTE del cluster:
#
#   - GitHub Actions API: resultado del build, duracion de las etapas,
#     duracion y resultado de los despliegues, politicas de cumplimiento.
#   - SonarCloud API: cobertura de pruebas y Quality Gate.
#
# Alimenta el dashboard "EFA - Pipeline CI/CD, Cobertura y Despliegue".
# Solo usa APIs publicas (repositorio y proyecto SonarCloud publicos).
#
# Uso:
#   PUSHGATEWAY_URL=http://localhost:9091 bash scripts/ci/collect-pipeline-metrics.sh
#   DRY_RUN=true bash scripts/ci/collect-pipeline-metrics.sh   # solo muestra
#
# Variables:
#   REPOSITORY      owner/repo (por defecto ealejandro23/backend-efa)
#   BRANCH          rama a observar (por defecto main)
#   SONAR_PROJECT   clave del proyecto en SonarCloud
#   PUSHGATEWAY_URL URL del Pushgateway (por defecto http://localhost:9091)
#   GITHUB_TOKEN    opcional: eleva el limite de la API de GitHub
# =============================================================================
set -euo pipefail

REPOSITORY="${REPOSITORY:-ealejandro23/backend-efa}"
BRANCH="${BRANCH:-main}"
SONAR_PROJECT="${SONAR_PROJECT:-ealejandro23_backend-efa}"
PUSHGATEWAY_URL="${PUSHGATEWAY_URL:-http://localhost:9091}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG="${SCRIPT_DIR}/../../compliance/policies/catalog.yml"

GH_API="https://api.github.com/repos/${REPOSITORY}"
AUTH=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

gh_get() { curl -fsS -m 20 -H "Accept: application/vnd.github+json" "${AUTH[@]}" "${GH_API}$1"; }
sonar_get() { curl -fsS -m 20 "https://sonarcloud.io/api$1" 2>/dev/null || echo '{}'; }
# Segundos entre dos fechas ISO-8601.
secs() { echo $(( $(date -d "$2" +%s) - $(date -d "$1" +%s) )); }
# Nombre de etapa apto como valor de etiqueta.
slug() { echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/([^)]*)//g; s/[^a-z0-9]\+/_/g; s/^_//; s/_$//'; }

BASE="repository=\"${REPOSITORY}\",branch=\"${BRANCH}\""
OUT=""
add() { OUT+="$1"$'\n'; }
help_type() { add "# TYPE $1 gauge"; }

echo "[collector] Repositorio ${REPOSITORY} (${BRANCH})"

# --- 1. Ultimo CI completado en la rama ---------------------------------------
CI_RUN="$(gh_get "/actions/workflows/main.yml/runs?branch=${BRANCH}&status=completed&per_page=1" | jq '.workflow_runs[0]')"
CI_ID="$(jq -r '.id' <<< "${CI_RUN}")"
CI_SHA="$(jq -r '.head_sha[0:7]' <<< "${CI_RUN}")"
CI_OK="$(jq -r 'if .conclusion == "success" then 1 else 0 end' <<< "${CI_RUN}")"
echo "[collector] CI #$(jq -r '.run_number' <<< "${CI_RUN}") commit ${CI_SHA}: $(jq -r '.conclusion' <<< "${CI_RUN}")"

help_type efa_ci_build_info
add "efa_ci_build_info{${BASE},commit=\"${CI_SHA}\",run_id=\"${CI_ID}\"} 1"
help_type efa_ci_build_success
add "efa_ci_build_success{${BASE},commit=\"${CI_SHA}\"} ${CI_OK}"

# Duracion de cada etapa (paso) del job principal del CI.
CI_JOBS="$(gh_get "/actions/runs/${CI_ID}/jobs")"
help_type efa_ci_stage_duration_seconds
SNYK_DEPS_OK=1
while IFS=$'\t' read -r NAME START END CONCLUSION; do
  [[ "${START}" == "null" || "${END}" == "null" ]] && continue
  case "${NAME}" in Set\ up*|Post\ *|Complete*|Initialize*|Stop\ containers) continue ;; esac
  [[ "${NAME}" == "Escaneo Snyk de dependencias" && "${CONCLUSION}" != "success" ]] && SNYK_DEPS_OK=0
  DUR="$(secs "${START}" "${END}")"
  add "efa_ci_stage_duration_seconds{${BASE},stage=\"$(slug "${NAME}")\"} ${DUR}"
done < <(jq -r '.jobs[] | select(.name == "Build, Tests, Calidad y Seguridad") | .steps[] | [.name, .started_at, .completed_at, .conclusion] | @tsv' <<< "${CI_JOBS}")

# Resultado del escaneo de seguridad (1 = se detectaron vulnerabilidades altas).
help_type efa_ci_security_vulnerabilities
add "efa_ci_security_vulnerabilities{${BASE},severity=\"high\"} $(( 1 - SNYK_DEPS_OK ))"

# --- 2. SonarCloud: cobertura y Quality Gate ----------------------------------
COVERAGE="$(sonar_get "/measures/component?component=${SONAR_PROJECT}&metricKeys=coverage" \
  | jq -r '[.component.measures[]? | select(.metric == "coverage") | .value][0] // empty')"
if [[ -n "${COVERAGE}" ]]; then
  help_type efa_ci_test_coverage_ratio
  add "efa_ci_test_coverage_ratio{${BASE},commit=\"${CI_SHA}\"} $(awk "BEGIN{print ${COVERAGE}/100}")"
  echo "[collector] Cobertura (SonarCloud): ${COVERAGE}%"
else
  echo "[collector] AVISO: no se pudo leer la cobertura en SonarCloud"
fi
QG="$(sonar_get "/qualitygates/project_status?projectKey=${SONAR_PROJECT}&branch=${BRANCH}" | jq -r '.projectStatus.status // empty')"
if [[ -n "${QG}" ]]; then
  help_type efa_ci_quality_gate_passed
  add "efa_ci_quality_gate_passed{${BASE},commit=\"${CI_SHA}\"} $([[ "${QG}" == "OK" ]] && echo 1 || echo 0)"
  echo "[collector] Quality Gate: ${QG}"
fi

# --- 3. Despliegues (workflow deploy.yml) -------------------------------------
DEPLOYS_OK="$(gh_get "/actions/workflows/deploy.yml/runs?status=success&per_page=1" | jq -r '.total_count')"
LAST_DEPLOY="$(gh_get "/actions/workflows/deploy.yml/runs?status=completed&per_page=1" | jq '.workflow_runs[0]')"
DEPLOY_CONCL="$(jq -r '.conclusion' <<< "${LAST_DEPLOY}")"
DEPLOY_DUR="$(secs "$(jq -r '.run_started_at' <<< "${LAST_DEPLOY}")" "$(jq -r '.updated_at' <<< "${LAST_DEPLOY}")")"
echo "[collector] Ultimo despliegue: ${DEPLOY_CONCL} en ${DEPLOY_DUR}s (exitosos en total: ${DEPLOYS_OK})"

help_type efa_ci_deployment_duration_seconds
add "efa_ci_deployment_duration_seconds{${BASE}} ${DEPLOY_DUR}"
help_type efa_ci_deployment_status
for S in success failure; do
  add "efa_ci_deployment_status{${BASE},status=\"${S}\"} $([[ "${DEPLOY_CONCL}" == "${S}" ]] && echo 1 || echo 0)"
done
help_type efa_ci_deployments_total
add "efa_ci_deployments_total{${BASE}} ${DEPLOYS_OK}"

# --- 4. Politicas de cumplimiento (ultimo gate) -------------------------------
COMP_ID="$(gh_get "/actions/workflows/compliance.yml/runs?branch=${BRANCH}&status=completed&per_page=1" | jq -r '.workflow_runs[0].id')"
help_type efa_ci_compliance_policy_passed
while IFS=$'\t' read -r NAME CONCLUSION; do
  for POLICY in $(grep -oE 'P-[A-Z]+-[0-9]{3}' <<< "${NAME}"); do
    # P-SEC-006 se evalua aparte: su paso usa continue-on-error y su
    # "conclusion" en la API siempre es success.
    [[ "${POLICY}" == "P-SEC-006" ]] && continue
    SEV="$(awk -v id="${POLICY}" '$0 ~ "id: "id {f=1} f && /severity:/ {print $2; exit}' "${CATALOG}" 2>/dev/null || true)"
    add "efa_ci_compliance_policy_passed{${BASE},policy=\"${POLICY}\",severity=\"${SEV:-n/a}\"} $([[ "${CONCLUSION}" == "success" ]] && echo 1 || echo 0)"
  done
done < <(gh_get "/actions/runs/${COMP_ID}/jobs" | jq -r '.jobs[] | select(.name == "Compliance — Gate de cumplimiento") | .steps[] | [.name, .conclusion] | @tsv')

# P-SEC-006: proteccion de la rama, leida directamente de la API de GitHub.
PROTECTED="$(gh_get "/branches/${BRANCH}" | jq -r 'if .protected then 1 else 0 end')"
add "efa_ci_compliance_policy_passed{${BASE},policy=\"P-SEC-006\",severity=\"major\"} ${PROTECTED}"
echo "[collector] Rama ${BRANCH} protegida: $([[ "${PROTECTED}" == "1" ]] && echo si || echo no)"

# --- 5. Publicacion -----------------------------------------------------------
if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo "${OUT}"
  exit 0
fi
curl -fsS -m 20 -X PUT --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/efa-pipeline-collector" <<< "${OUT}"
echo "[collector] $(grep -c '^efa_' <<< "${OUT}") series publicadas en ${PUSHGATEWAY_URL}"
