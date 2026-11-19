package Proyecto_EFA.demo.observability;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertSame;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.sql.Connection;
import java.sql.SQLException;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;

import javax.sql.DataSource;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import jakarta.servlet.FilterChain;
import jakarta.servlet.http.HttpServletResponse;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.slf4j.MDC;
import org.springframework.boot.actuate.info.Info;
import org.springframework.boot.health.contributor.Health;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

/**
 * Pruebas unitarias de los componentes de observabilidad (EP3).
 *
 * <p>Verifican que las metricas, el indicador de salud, los metadatos de
 * build y los filtros de correlacion y de metricas se comporten como lo
 * esperan los dashboards de Grafana y las reglas de alerta de Prometheus.
 */
class ObservabilityComponentsTest {

    private static FilterChain chainConStatus(int status) {
        return (req, res) -> ((HttpServletResponse) res).setStatus(status);
    }

    // =====================================================================
    // ApplicationMetrics
    // =====================================================================
    @Nested
    class ApplicationMetricsTest {

        private SimpleMeterRegistry registry;
        private ApplicationMetrics metrics;

        @BeforeEach
        void setUp() {
            registry = new SimpleMeterRegistry();
            metrics = new ApplicationMetrics(registry, "1.0.0", "abc1234", "test");
        }

        @Test
        void registraMetricasBaseAlCrearse() {
            assertNotNull(registry.find("efa.errors.total").counter());
            assertNotNull(registry.find("efa.request.duration").timer());
            assertEquals(1.0, registry.get("efa.availability.up").gauge().value());
            assertEquals(1.0, registry.get("efa.deploy.info")
                    .tag("version", "1.0.0")
                    .tag("commit", "abc1234")
                    .tag("environment", "test")
                    .gauge().value());
            assertTrue(registry.get("efa.build.timestamp").gauge().value() > 0);
        }

        @Test
        void registrarErrorIncrementaElContadorEtiquetado() {
            metrics.registrarError("http_5xx", "/api/productos");
            metrics.registrarError("http_5xx", "/api/productos");

            double total = registry.get("efa.errors.total")
                    .tag("tipo", "http_5xx")
                    .tag("endpoint", "/api/productos")
                    .counter().count();
            assertEquals(2.0, total);
        }

        @Test
        void registrarDuracionAlimentaTimerYContadorDeOperaciones() {
            metrics.registrarDuracion(150, "GET");

            assertEquals(1, registry.get("efa.request.duration").timer().count());
            assertEquals(1.0, registry.get("efa.business.operations")
                    .tag("operacion", "GET").counter().count());
        }

        @Test
        void disponibilidadCambiaEntreUnoYCero() {
            assertTrue(metrics.isDisponible());

            metrics.setDisponible(false);
            assertFalse(metrics.isDisponible());
            assertEquals(0.0, registry.get("efa.availability.up").gauge().value());

            metrics.setDisponible(true);
            assertTrue(metrics.isDisponible());
            assertEquals(1.0, registry.get("efa.availability.up").gauge().value());
        }

        @Test
        void exponeElRegistroUtilizado() {
            assertSame(registry, metrics.getRegistry());
        }
    }

    // =====================================================================
    // AvailabilityHealthIndicator
    // =====================================================================
    @Nested
    class AvailabilityHealthIndicatorTest {

        private DataSource dataSource;
        private ApplicationMetrics metrics;
        private AvailabilityHealthIndicator indicator;

        @BeforeEach
        void setUp() {
            dataSource = mock(DataSource.class);
            metrics = new ApplicationMetrics(new SimpleMeterRegistry(), "dev", "unknown", "test");
            indicator = new AvailabilityHealthIndicator(dataSource, metrics);
        }

        @Test
        void reportaUpCuandoLaConexionEsValida() throws SQLException {
            Connection connection = mock(Connection.class);
            when(dataSource.getConnection()).thenReturn(connection);
            when(connection.isValid(2)).thenReturn(true);

            Health health = indicator.health();

            assertEquals("UP", health.getStatus().getCode());
            assertEquals("base-de-datos", health.getDetails().get("componente"));
            assertTrue(metrics.isDisponible());
            verify(connection).close();
        }

        @Test
        void reportaDownCuandoLaConexionNoResponde() throws SQLException {
            Connection connection = mock(Connection.class);
            when(dataSource.getConnection()).thenReturn(connection);
            when(connection.isValid(2)).thenReturn(false);

            Health health = indicator.health();

            assertEquals("DOWN", health.getStatus().getCode());
            assertFalse(metrics.isDisponible());
            verify(connection).close();
        }

        @Test
        void reportaDownCuandoNoHayConexion() throws SQLException {
            when(dataSource.getConnection()).thenReturn(null);

            Health health = indicator.health();

            assertEquals("DOWN", health.getStatus().getCode());
            assertFalse(metrics.isDisponible());
        }

        @Test
        void reportaDownCuandoLaBaseDeDatosLanzaExcepcion() throws SQLException {
            when(dataSource.getConnection()).thenThrow(new SQLException("sin conexion"));

            Health health = indicator.health();

            assertEquals("DOWN", health.getStatus().getCode());
            assertEquals("fallo al validar la conexion", health.getDetails().get("motivo"));
            assertFalse(metrics.isDisponible());
        }
    }

    // =====================================================================
    // BuildInfoContributor
    // =====================================================================
    @Nested
    class BuildInfoContributorTest {

        @Test
        void publicaLosMetadatosDeBuild() {
            BuildInfoContributor contributor = new BuildInfoContributor(
                    "Proyecto EFA API", "1.0.0", "abc1234", "main", "2026-11-19T00:00:00Z", "test");

            Info.Builder builder = new Info.Builder();
            contributor.contribute(builder);
            Map<String, Object> details = builder.build().getDetails();

            assertEquals("Proyecto EFA API", details.get("app"));
            assertEquals("1.0.0", details.get("version"));
            assertEquals("abc1234", details.get("commit"));
            assertEquals("main", details.get("branch"));
            assertEquals("2026-11-19T00:00:00Z", details.get("buildTime"));
            assertEquals("test", details.get("environment"));
        }
    }

    // =====================================================================
    // CorrelationIdFilter
    // =====================================================================
    @Nested
    class CorrelationIdFilterTest {

        private final CorrelationIdFilter filter = new CorrelationIdFilter();

        @Test
        void reutilizaElIdentificadorEnviadoPorElCliente() throws Exception {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/productos");
            request.addHeader(CorrelationIdFilter.CORRELATION_HEADER, "  id-del-cliente  ");
            MockHttpServletResponse response = new MockHttpServletResponse();
            AtomicReference<String> traceEnMdc = new AtomicReference<>();

            filter.doFilter(request, response,
                    (req, res) -> traceEnMdc.set(MDC.get(CorrelationIdFilter.MDC_TRACE_ID)));

            assertEquals("id-del-cliente", response.getHeader(CorrelationIdFilter.CORRELATION_HEADER));
            assertEquals("id-del-cliente", traceEnMdc.get());
            // El MDC se limpia al terminar la peticion.
            assertNull(MDC.get(CorrelationIdFilter.MDC_TRACE_ID));
            assertNull(MDC.get("spanId"));
        }

        @Test
        void generaIdentificadorCuandoNoLlegaONoEsValido() throws Exception {
            MockHttpServletRequest sinCabecera = new MockHttpServletRequest("GET", "/api/productos");
            MockHttpServletResponse r1 = new MockHttpServletResponse();
            filter.doFilter(sinCabecera, r1, chainConStatus(200));

            MockHttpServletRequest enBlanco = new MockHttpServletRequest("GET", "/api/productos");
            enBlanco.addHeader(CorrelationIdFilter.CORRELATION_HEADER, "   ");
            MockHttpServletResponse r2 = new MockHttpServletResponse();
            filter.doFilter(enBlanco, r2, chainConStatus(200));

            MockHttpServletRequest muyLargo = new MockHttpServletRequest("GET", "/api/productos");
            muyLargo.addHeader(CorrelationIdFilter.CORRELATION_HEADER, "x".repeat(200));
            MockHttpServletResponse r3 = new MockHttpServletResponse();
            filter.doFilter(muyLargo, r3, chainConStatus(200));

            for (MockHttpServletResponse r : new MockHttpServletResponse[] {r1, r2, r3}) {
                String id = r.getHeader(CorrelationIdFilter.CORRELATION_HEADER);
                assertNotNull(id);
                assertEquals(32, id.length());
            }
            assertNotEquals(r1.getHeader(CorrelationIdFilter.CORRELATION_HEADER),
                    r2.getHeader(CorrelationIdFilter.CORRELATION_HEADER));
        }

        @Test
        void extraeElTraceIdDeLaCabeceraTraceparent() throws Exception {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/productos");
            request.addHeader("traceparent", "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01");
            MockHttpServletResponse response = new MockHttpServletResponse();
            AtomicReference<String> spanEnMdc = new AtomicReference<>();

            filter.doFilter(request, response, (req, res) -> spanEnMdc.set(MDC.get("spanId")));

            assertEquals("4bf92f3577b34da6a3ce929d0e0e4736", spanEnMdc.get());
        }

        @Test
        void generaSpanIdCuandoTraceparentEsInvalido() throws Exception {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/productos");
            request.addHeader("traceparent", "corto");
            MockHttpServletResponse response = new MockHttpServletResponse();
            AtomicReference<String> spanEnMdc = new AtomicReference<>();

            filter.doFilter(request, response, (req, res) -> spanEnMdc.set(MDC.get("spanId")));

            assertNotNull(spanEnMdc.get());
            assertEquals(16, spanEnMdc.get().length());
        }

        @Test
        void registraPeticionesConErrorDelServidorYDelCliente() throws Exception {
            MockHttpServletResponse error500 = new MockHttpServletResponse();
            filter.doFilter(new MockHttpServletRequest("POST", "/api/ventas"), error500, chainConStatus(500));

            MockHttpServletResponse error404 = new MockHttpServletResponse();
            filter.doFilter(new MockHttpServletRequest("GET", "/api/nada"), error404, chainConStatus(404));

            assertEquals(500, error500.getStatus());
            assertEquals(404, error404.getStatus());
            assertNotNull(error500.getHeader(CorrelationIdFilter.CORRELATION_HEADER));
            assertNotNull(error404.getHeader(CorrelationIdFilter.CORRELATION_HEADER));
            assertNull(MDC.get("status"));
        }
    }

    // =====================================================================
    // RequestMetricsFilter
    // =====================================================================
    @Nested
    class RequestMetricsFilterTest {

        private SimpleMeterRegistry registry;
        private RequestMetricsFilter filter;

        @BeforeEach
        void setUp() {
            registry = new SimpleMeterRegistry();
            filter = new RequestMetricsFilter(new ApplicationMetrics(registry, "dev", "unknown", "test"));
        }

        private double errores(String tipo, String endpoint) {
            var counter = registry.find("efa.errors.total").tag("tipo", tipo).tag("endpoint", endpoint).counter();
            return counter == null ? 0.0 : counter.count();
        }

        @Test
        void registraDuracionEnPeticionesExitosasSinContarErrores() throws Exception {
            filter.doFilter(new MockHttpServletRequest("GET", "/api/productos"),
                    new MockHttpServletResponse(), chainConStatus(200));

            assertEquals(1, registry.get("efa.request.duration").timer().count());
            assertEquals(1.0, registry.get("efa.business.operations").tag("operacion", "GET").counter().count());
            assertNull(registry.find("efa.errors.total").tag("tipo", "http_5xx").counter());
        }

        @Test
        void cuentaErrores5xxNormalizandoElEndpoint() throws Exception {
            filter.doFilter(new MockHttpServletRequest("GET", "/api/productos/15"),
                    new MockHttpServletResponse(), chainConStatus(500));

            assertEquals(1.0, errores("http_5xx", "/api/productos"));
        }

        @Test
        void cuentaErrores429ConRutaCorta() throws Exception {
            filter.doFilter(new MockHttpServletRequest("POST", "/ventas"),
                    new MockHttpServletResponse(), chainConStatus(429));

            assertEquals(1.0, errores("http_429", "/ventas"));
        }

        @Test
        void normalizaRutaVaciaComoRaiz() throws Exception {
            filter.doFilter(new MockHttpServletRequest("GET", ""),
                    new MockHttpServletResponse(), chainConStatus(503));

            assertEquals(1.0, errores("http_5xx", "/"));
        }

        @Test
        void ignoraLosEndpointsDeGestion() throws Exception {
            for (String path : new String[] {"/actuator/health", "/doc", "/swagger-ui/index.html", "/v3/api-docs"}) {
                filter.doFilter(new MockHttpServletRequest("GET", path),
                        new MockHttpServletResponse(), chainConStatus(500));
            }

            assertEquals(0, registry.get("efa.request.duration").timer().count());
            assertNull(registry.find("efa.business.operations").counter());
            assertNull(registry.find("efa.errors.total").tag("tipo", "http_5xx").counter());
        }
    }
}
