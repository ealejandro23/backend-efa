#!/usr/bin/env bash
# =============================================================================
# create-cloudwatch-dashboard.sh - Dashboard y alarmas de CloudWatch
#
# Se ejecuta desde AWS CloudShell (o cualquier equipo con la AWS CLI y
# credenciales), despues de setup-cloudwatch.sh:
#   bash scripts/aws/create-cloudwatch-dashboard.sh <instance-id> [region]
#
# Crea:
#   - Grupo de logs /efa/backend (retencion 7 dias).
#   - Dashboard "EFA-Backend": CPU, memoria, disco, disponibilidad,
#     peticiones, errores 4xx/5xx, latencia p95, pods y logs de errores.
#   - Alarmas: EFA-Backend-Caido, EFA-CPU-Alta y EFA-Errores-5xx.
# =============================================================================
set -euo pipefail

INSTANCE_ID="${1:?Uso: $0 <instance-id> [region]}"
REGION="${2:-us-east-1}"
NS="EFA/EC2"
DIM="Name=InstanceId,Value=${INSTANCE_ID}"

echo ">>> Grupo de logs /efa/backend"
aws logs create-log-group --region "${REGION}" --log-group-name /efa/backend 2>/dev/null || true
aws logs put-retention-policy --region "${REGION}" --log-group-name /efa/backend --retention-in-days 7

m() { printf '["%s","%s","InstanceId","%s"]' "${NS}" "$1" "${INSTANCE_ID}"; }
w() { # titulo x y ancho alto metrica[,metrica...] [stat]
  printf '{"type":"metric","x":%s,"y":%s,"width":%s,"height":%s,"properties":{"title":"%s","region":"%s","stat":"%s","period":60,"view":"timeSeries","metrics":[%s]}}' \
    "$2" "$3" "$4" "$5" "$1" "${REGION}" "${7:-Average}" "$6"
}

BODY="{\"widgets\":[
$(w 'Backend disponible (1 = UP)' 0 0 8 6 "$(m efa_backend_disponible)" Minimum),
$(w 'Peticiones por minuto' 8 0 8 6 "$(m efa_peticiones_por_minuto)"),
$(w 'Latencia p95 (ms)' 16 0 8 6 "$(m efa_latencia_p95_ms)"),
$(w 'Errores 4xx y 5xx por minuto' 0 6 8 6 "$(m efa_errores_4xx_por_minuto),$(m efa_errores_5xx_por_minuto)"),
$(w 'Pods Running (namespace efa)' 8 6 8 6 "$(m efa_pods_running)" Minimum),
$(w 'CPU de la instancia (%)' 16 6 8 6 "$(m cpu_usage_user),$(m cpu_usage_system)"),
$(w 'Memoria usada (%)' 0 12 12 6 "$(m mem_used_percent)"),
$(w 'Disco usado (%)' 12 12 12 6 "$(m disk_used_percent)"),
{\"type\":\"log\",\"x\":0,\"y\":18,\"width\":24,\"height\":6,\"properties\":{\"title\":\"Logs del backend: advertencias y errores\",\"region\":\"${REGION}\",\"view\":\"table\",\"query\":\"SOURCE '/efa/backend' | fields @timestamp, @message | filter @message like /WARN|ERROR/ | sort @timestamp desc | limit 50\"}}
]}"

echo ">>> Dashboard EFA-Backend"
aws cloudwatch put-dashboard --region "${REGION}" --dashboard-name EFA-Backend --dashboard-body "${BODY}" \
  --query 'DashboardValidationMessages' --output text

echo ">>> Alarmas"
aws cloudwatch put-metric-alarm --region "${REGION}" --alarm-name EFA-Backend-Caido \
  --alarm-description "El backend no responde a Prometheus durante 3 minutos" \
  --namespace "${NS}" --metric-name efa_backend_disponible --dimensions "${DIM}" \
  --statistic Minimum --period 60 --evaluation-periods 3 --threshold 1 \
  --comparison-operator LessThanThreshold --treat-missing-data breaching

aws cloudwatch put-metric-alarm --region "${REGION}" --alarm-name EFA-CPU-Alta \
  --alarm-description "CPU de usuario de la instancia sobre 80% durante 5 minutos" \
  --namespace "${NS}" --metric-name cpu_usage_user --dimensions "${DIM}" \
  --statistic Average --period 60 --evaluation-periods 5 --threshold 80 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching

aws cloudwatch put-metric-alarm --region "${REGION}" --alarm-name EFA-Errores-5xx \
  --alarm-description "Mas de 5 errores 5xx por minuto durante 3 minutos" \
  --namespace "${NS}" --metric-name efa_errores_5xx_por_minuto --dimensions "${DIM}" \
  --statistic Average --period 60 --evaluation-periods 3 --threshold 5 \
  --comparison-operator GreaterThanThreshold --treat-missing-data notBreaching

aws cloudwatch describe-alarms --region "${REGION}" --alarm-name-prefix EFA- \
  --query 'MetricAlarms[].[AlarmName,StateValue]' --output text
echo "Dashboard: https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards/dashboard/EFA-Backend"
