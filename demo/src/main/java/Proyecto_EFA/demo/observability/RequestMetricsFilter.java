package Proyecto_EFA.demo.observability;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Filtro que alimenta las metricas de negocio del microservicio.
 *
 * <p>Complementa la instrumentacion por defecto de Micrometer con dos series
 * que el dashboard de observabilidad necesita de forma explicita:
 *
 * <ul>
 *   <li>{@code efa.errors.total}: cuenta los errores 5xx por endpoint. Es la
 *       serie directa del panel "Errores registrados".</li>
 *   <li>{@code efa.request.duration}: duracion de las peticiones servidas,
 *       con histograma de percentiles para el panel de latencia.</li>
 * </ul>
 *
 * <p>Las peticiones a los endpoints de gestion del actuator se excluyen: son
 * el mecanismo de observacion, no parte de la carga de negocio, e incluirlas
 * inflaria artificialmente las metricas de uso y de error.
 */
@Component
@Order(2)
public class RequestMetricsFilter extends OncePerRequestFilter {

    private static final String[] EXCLUDED_PREFIXES = {
        "/actuator", "/doc", "/swagger-ui", "/v3/api-docs"
    };

    private final ApplicationMetrics applicationMetrics;

    public RequestMetricsFilter(ApplicationMetrics applicationMetrics) {
        this.applicationMetrics = applicationMetrics;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        for (String prefix : EXCLUDED_PREFIXES) {
            if (path.startsWith(prefix)) {
                return true;
            }
        }
        return false;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {

        long start = System.nanoTime();
        try {
            filterChain.doFilter(request, response);
        } finally {
            long durationMs = (System.nanoTime() - start) / 1_000_000L;
            int status = response.getStatus();

            applicationMetrics.registrarDuracion(durationMs, request.getMethod());

            if (status >= 500) {
                applicationMetrics.registrarError("http_5xx", normalize(request.getRequestURI()));
            } else if (status == 429) {
                applicationMetrics.registrarError("http_429", normalize(request.getRequestURI()));
            }
        }
    }

    /**
     * Reduce la cardinalidad de la etiqueta de endpoint.
     *
     * <p>Registrar la ruta completa (que puede contener identificadores) como
     * valor de etiqueta generaria series inutilmente distintas y degradaria
     * el indice de Prometheus. Se conservan solo los dos primeros segmentos.
     *
     * @param path ruta de la peticion
     * @return etiqueta normalizada
     */
    private String normalize(String path) {
        if (path == null || path.isBlank()) {
            return "/";
        }
        String[] segments = path.split("/");
        if (segments.length <= 2) {
            return path;
        }
        return "/" + segments[1] + "/" + segments[2];
    }
}
