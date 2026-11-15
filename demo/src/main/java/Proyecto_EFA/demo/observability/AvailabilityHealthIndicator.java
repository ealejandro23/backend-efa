package Proyecto_EFA.demo.observability;

import javax.sql.DataSource;

import org.springframework.boot.health.contributor.Health;
import org.springframework.boot.health.contributor.HealthIndicator;
import org.springframework.stereotype.Component;

/**
 * Indicador de salud y disponibilidad del microservicio.
 *
 * <p>Verifica que la conexion con la base de datos responda dentro de un
 * limite razonable. El resultado alimenta dos consumidores:
 *
 * <ul>
 *   <li>El endpoint {@code /actuator/health}, que usan los healthchecks de
 *       Docker Compose y de Kubernetes (liveness y readiness probes).</li>
 *   <li>La metrica {@code efa.availability.up}, que es la que el dashboard
 *       usa para calcular la disponibilidad real del servicio.</li>
 * </ul>
 */
@Component("efaApplication")
public class AvailabilityHealthIndicator implements HealthIndicator {

    private final DataSource dataSource;
    private final ApplicationMetrics applicationMetrics;

    public AvailabilityHealthIndicator(DataSource dataSource, ApplicationMetrics applicationMetrics) {
        this.dataSource = dataSource;
        this.applicationMetrics = applicationMetrics;
    }

    @Override
    public Health health() {
        // La conexion se obtiene y se cierra dentro de un bloque
        // try-with-resources. Abrirla sin cerrarla agotaria el pool de
        // conexiones (Hikari) despues de varias consultas de salud.
        try (java.sql.Connection connection = dataSource.getConnection()) {
            if (connection == null || !connection.isValid(2)) {
                applicationMetrics.setDisponible(false);
                return Health.down()
                        .withDetail("componente", "base-de-datos")
                        .withDetail("motivo", "la conexion a la base de datos no responde")
                        .build();
            }

            applicationMetrics.setDisponible(true);
            return Health.up()
                    .withDetail("componente", "base-de-datos")
                    .withDetail("disponible", true)
                    .build();
        } catch (Exception e) {
            applicationMetrics.setDisponible(false);
            return Health.down(e)
                    .withDetail("componente", "base-de-datos")
                    .withDetail("motivo", "fallo al validar la conexion")
                    .build();
        }
    }
}
