# Plantilla de Pull Request - Proyecto EFA

## Descripcion

<!-- Que cambia este Pull Request y por que es necesario. -->

## Tipo de cambio

- [ ] Correccion de error (bugfix)
- [ ] Nueva funcionalidad (feature)
- [ ] Mejora de la observabilidad
- [ ] Cambio en el pipeline CI/CD
- [ ] Documentacion
- [ ] Configuracion de infraestructura

## Impacto en la observabilidad

<!--
Marque la casilla que corresponda. Si el cambio afecta a las metricas, los
logs o las alertas, debe actualizar tambien los dashboards y las reglas de
alerta correspondientes.
-->

- [ ] No afecta la observabilidad
- [ ] Afecta las metricas: se actualizan `infra/monitoring/grafana/dashboards/`
- [ ] Afecta los logs: se revisa el formato de salida del perfil afectado
- [ ] Afecta las alertas: se actualizan `infra/monitoring/prometheus/rules/`
- [ ] Afecta el descubrimiento en Kubernetes: se actualizan las anotaciones `prometheus.io/*`

## Cumplimiento

- [ ] Las pruebas automatizadas pasan (`mvn clean verify`)
- [ ] La cobertura no baja del umbral exigido (60%)
- [ ] El Quality Gate de SonarCloud esta en verde
- [ ] El escaneo de seguridad (Snyk) no reporta vulnerabilidades altas ni criticas
- [ ] No se introducen secretos en el codigo
- [ ] Se ejecuto `bash scripts/compliance/run-all.sh` y el resultado fue aprobado

## Despliegue

- [ ] No requiere cambios en el pipeline ni en los manifiestos
- [ ] Requiere actualizar `infra/k8s/`
- [ ] Requiere actualizar el `.env` de ejemplo o las variables de entorno documentadas

## Lista de verificacion para la revision

- [ ] El codigo es legible y sigue las convenciones del proyecto
- [ ] Los mensajes de log son utiles para diagnosticar un incidente
- [ ] Se Probaron los cambios localmente

## Evidencia

<!--
Enlace a la ejecucion del workflow, a las capturas de los dashboards o a
las salidas de los comandos de verificacion.
-->

