#!/usr/bin/env bash
# =============================================================================
# setup-cloudwatch.sh - Instala y configura el agente de AWS CloudWatch en la
# EC2 que ejecuta el cluster Kind (Ubuntu 24.04).
#
# Se ejecuta EN la EC2, con el usuario ubuntu, desde la raiz del repositorio
# (o desde una copia de infra/cloudwatch y de este script):
#   bash scripts/aws/setup-cloudwatch.sh
#
# Requisitos: la instancia debe tener un rol de IAM con permisos para
# CloudWatch y CloudWatch Logs (en el Learner Lab: LabInstanceProfile).
#
# Que hace:
#   1. Instala el agente oficial (amazon-cloudwatch-agent).
#   2. Carga infra/cloudwatch/amazon-cloudwatch-agent.json: CPU, memoria y
#      disco de la instancia, un receptor StatsD y los logs del backend.
#   3. Instala el servicio efa-backend-logs (logs de los pods del backend a
#      /var/log/efa/backend.log, que el agente envia a CloudWatch Logs).
#   4. Programa efa-cloudwatch-bridge.sh cada minuto (metricas de la
#      aplicacion desde Prometheus y Kubernetes hacia CloudWatch).
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "$0")/../.." && pwd)/infra/cloudwatch"
[[ -d "${DIR}" ]] || DIR="$(cd "$(dirname "$0")" && pwd)"
CW_CTL=/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl
CW_CFG=/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

echo ">>> 1. Agente de CloudWatch"
if [[ ! -x "${CW_CTL}" ]]; then
  curl -sSfL -o /tmp/amazon-cloudwatch-agent.deb \
    https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
  sudo dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
fi

echo ">>> 2. Configuracion del agente"
sudo install -m 0644 "${DIR}/amazon-cloudwatch-agent.json" "${CW_CFG}"
sudo mkdir -p /var/log/efa
sudo chown ubuntu:ubuntu /var/log/efa
touch /var/log/efa/backend.log
sudo "${CW_CTL}" -a fetch-config -m ec2 -s -c "file:${CW_CFG}"

echo ">>> 3. Servicio de logs del backend"
sudo install -m 0644 "${DIR}/efa-backend-logs.service" /etc/systemd/system/efa-backend-logs.service
sudo systemctl daemon-reload
sudo systemctl enable --now efa-backend-logs.service
sudo systemctl restart efa-backend-logs.service

echo ">>> 4. Puente de metricas de la aplicacion (cron cada minuto)"
sudo install -m 0755 "${DIR}/efa-cloudwatch-bridge.sh" /usr/local/bin/efa-cloudwatch-bridge.sh
CRON_LINE='* * * * * PATH=/usr/local/bin:/usr/bin:/bin /usr/local/bin/efa-cloudwatch-bridge.sh >> /var/log/efa/cloudwatch-bridge.log 2>&1'
( crontab -l 2>/dev/null | grep -v efa-cloudwatch-bridge || true; echo "${CRON_LINE}" ) | crontab -
/usr/local/bin/efa-cloudwatch-bridge.sh

echo ">>> Estado"
sudo "${CW_CTL}" -a status | grep -E '"status"|"configstatus"'
systemctl is-active efa-backend-logs.service
echo "Listo: metricas en el namespace EFA/EC2 y logs en el grupo /efa/backend"
