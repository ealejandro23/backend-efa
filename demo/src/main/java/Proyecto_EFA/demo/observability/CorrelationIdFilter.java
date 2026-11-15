package Proyecto_EFA.demo.observability;

import java.io.IOException;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Filtro de correlacion de peticiones.
 *
 * <p>Cada peticion HTTP recibe un identificador de correlacion
 * ({@code X-Correlation-Id}). Si el cliente (por ejemplo el frontend React)
 * ya envio uno, se reutiliza; en caso contrario se genera uno. Ese
 * identificador se agrega al MDC, por lo que aparece automaticamente en
 * todas las lineas de log generadas durante la peticion, y se devuelve en la
 * respuesta HTTP para que el usuario pueda reportar un problema quoting el
 * identificador concreto.
 *
 * <p>Este es el mecanismo que une la observabilidad de logs (Loki) con la
 * observabilidad de metricas (Prometheus): las metricas de error indican
 * <em>que</em> fallo y los logs indican <em>por que</em>, y ambos se
 * correlacionan mediante este identificador.
 *
 * <p>Implementa la propagacion de W3C Trace Context de forma simplificada:
 * si la peticion trae {@code traceparent}, se extrae el identificador de
 * traza para mantener la continuidad con el navegador.
 */
@Component
@Order(1)
public class CorrelationIdFilter extends OncePerRequestFilter {

    /** Nombre de la cabecera con la que el cliente puede propagar el identificador. */
    public static final String CORRELATION_HEADER = "X-Correlation-Id";

    /** Clave bajo la que el identificador queda disponible en el MDC (y en los logs). */
    public static final String MDC_TRACE_ID = "traceId";

    private static final String TRACE_PARENT_HEADER = "traceparent";

    private static final Logger log = LoggerFactory.getLogger(CorrelationIdFilter.class);

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {

        String correlationId = resolveCorrelationId(request);
        String traceId = resolveTraceId(request);

        // MDC con herencia para que los hilos creados durante la peticion
        // (por ejemplo en @Async) conserven el identificador.
        MDC.put(MDC_TRACE_ID, correlationId);
        MDC.put("spanId", traceId);

        long start = System.nanoTime();

        try {
            filterChain.doFilter(request, response);
        } finally {
            long durationMs = (System.nanoTime() - start) / 1_000_000L;
            int status = response.getStatus();

            MDC.put("status", String.valueOf(status));
            MDC.put("durationMs", String.valueOf(durationMs));
            MDC.put("method", request.getMethod());
            MDC.put("path", request.getRequestURI());

            response.setHeader(CORRELATION_HEADER, correlationId);

            if (status >= 500) {
                // Los errores del servidor se registran en nivel ERROR para
                // que Loki los muestre en el panel de logs criticos.
                log.error("Peticion fallida {} {} -> {} ({} ms)",
                        request.getMethod(), request.getRequestURI(), status, durationMs);
            } else if (status >= 400) {
                log.warn("Peticion rechazada {} {} -> {} ({} ms)",
                        request.getMethod(), request.getRequestURI(), status, durationMs);
            } else {
                log.debug("Peticion {} {} -> {} ({} ms)",
                        request.getMethod(), request.getRequestURI(), status, durationMs);
            }

            MDC.remove(MDC_TRACE_ID);
            MDC.remove("spanId");
            MDC.remove("status");
            MDC.remove("durationMs");
            MDC.remove("method");
            MDC.remove("path");
        }
    }

    /**
     * Obtiene el identificador de correlacion de la peticion.
     *
     * @param request peticion entrante
     * @return identificador de correlacion no nulo
     */
    private String resolveCorrelationId(HttpServletRequest request) {
        String incoming = request.getHeader(CORRELATION_HEADER);
        if (incoming != null && !incoming.isBlank() && incoming.length() <= 128) {
            return incoming.trim();
        }
        return UUID.randomUUID().toString().replace("-", "");
    }

    /**
     * Extrae el identificador de traza de la cabecera W3C {@code traceparent}
     * si el cliente la envia.
     *
     * @param request peticion entrante
     * @return identificador de traza o un valor generado
     */
    private String resolveTraceId(HttpServletRequest request) {
        String traceparent = request.getHeader(TRACE_PARENT_HEADER);
        if (traceparent != null && traceparent.length() >= 35) {
            return traceparent.substring(3, 35);
        }
        return UUID.randomUUID().toString().replace("-", "").substring(0, 16);
    }
}
