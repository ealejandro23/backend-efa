package Proyecto_EFA.demo.observability;

import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

/**
 * Metricas de negocio y de disponibilidad del microservicio.
 *
 * <p>Micrometer ya expone automaticamente las metricas HTTP del framework
 * ({@code http_server_requests_seconds}, {@code jvm_memory_used_bytes}, etc.).
 * Esta clase agrega las que el framework no puede conocer:
 *
 * <ul>
 *   <li>{@code efa.errors.total}: contador de errores de aplicacion,
 *       etiquetado por tipo y por endpoint. Es la serie que usa el panel
 *       "Errores registrados" y la regla de alerta de tasa 5xx.</li>
 *   <li>{@code efa.availability.up}: indicador de disponibilidad del
 *       servicio (1 = disponible, 0 = no disponible). Permite calcular el
 *       porcentaje de disponibilidad real, no solo el de las peticiones que
 *       el sistema alcanza a responder.</li>
 *   <li>{@code efa.request.duration}: duracion de las peticiones de negocio,
 *       independiente de la instrumentacion por defecto del contenedor.</li>
 *   <li>{@code efa.deploy.info}: metadatos de la version desplegada
 *       (commit, version, entorno) como metricas, para saber desde el
 *       dashboard que build esta en ejecucion.</li>
 * </ul>
 */
@Component
public class ApplicationMetrics {

    private final MeterRegistry registry;
    private final Counter errorCounter;
    private final Timer requestTimer;
    private final AtomicInteger availability = new AtomicInteger(1);

    private final String version;
    private final String commit;
    private final String environment;

    public ApplicationMetrics(MeterRegistry registry,
                              @Value("${info.app.version:dev}") String version,
                              @Value("${info.app.commit:unknown}") String commit,
                              @Value("${info.app.environment:dev}") String environment) {
        this.registry = registry;
        this.version = version;
        this.commit = commit;
        this.environment = environment;

        this.errorCounter = Counter.builder("efa.errors.total")
                .description("Errores de aplicacion registrados por el microservicio")
                .tag("service", "efa-backend")
                .register(registry);

        this.requestTimer = Timer.builder("efa.request.duration")
                .description("Duracion de las peticiones de negocio")
                .publishPercentileHistogram()
                .register(registry);

        // Disponibilidad: 1 disponible / 0 no disponible.
        Gauge.builder("efa.availability.up", availability, AtomicInteger::get)
                .description("Disponibilidad del microservicio (1 = disponible, 0 = no disponible)")
                .tag("service", "efa-backend")
                .register(registry);

        // Metadatos del despliegue como metricas.
        Gauge.builder("efa.deploy.info", () -> 1)
                .description("Metadatos de la version desplegada en ejecucion")
                .tag("service", "efa-backend")
                .tag("version", version)
                .tag("commit", commit)
                .tag("environment", environment)
                .register(registry);

        Gauge.builder("efa.build.timestamp", () -> System.currentTimeMillis() / 1000.0)
                .description("Momento de arranque del proceso")
                .tag("service", "efa-backend")
                .register(registry);
    }

    /**
     * Registra un error de aplicacion.
     *
     * @param tipo      clasificacion del error (por ejemplo {@code http_5xx})
     * @param endpoint  recurso afectado
     */
    public void registrarError(String tipo, String endpoint) {
        registry.counter("efa.errors.total", "service", "efa-backend", "tipo", tipo, "endpoint", endpoint)
                .increment();
    }

    /**
     * Registra la duracion de una peticion de negocio.
     *
     * @param duracionMs duracion en milisegundos
     * @param operacion  nombre de la operacion
     */
    public void registrarDuracion(long duracionMs, String operacion) {
        requestTimer.record(duracionMs, TimeUnit.MILLISECONDS);
        registry.counter("efa.business.operations", "operacion", operacion, "service", "efa-backend")
                .increment();
    }

    /**
     * Marca el servicio como disponible o no disponible.
     *
     * @param disponible {@code true} si el servicio esta operativo
     */
    public void setDisponible(boolean disponible) {
        availability.set(disponible ? 1 : 0);
    }

    /**
     * @return {@code true} si el servicio se considera disponible
     */
    public boolean isDisponible() {
        return availability.get() == 1;
    }

    public MeterRegistry getRegistry() {
        return registry;
    }
}
