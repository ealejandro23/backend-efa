package Proyecto_EFA.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.util.List;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import Proyecto_EFA.demo.repository.ProductoVentaRepository;
import Proyecto_EFA.demo.service.ProductoVentaService;

/**
 * Tests unitarios de {@link ProductoVentaService} para los métodos de
 * ranking que ningún controlador expone (solo se alcanzan por código) y
 * para la normalización de totales nulos a cero.
 */
class ProductoVentaServiceTest {

    private ProductoVentaRepository repositorio;
    private ProductoVentaService servicio;

    @BeforeEach
    void prepararDobles() {
        repositorio = mock(ProductoVentaRepository.class);
        servicio = new ProductoVentaService();
        ReflectionTestUtils.setField(servicio, "productoVentaRepository", repositorio);
    }

    @Test
    void rankingsDiezYCincoMasVendidosDeleganEnElRepositorio() {
        List<Object[]> ranking = List.<Object[]>of(new Object[] { "Polera", 10L });
        when(repositorio.findTop10SellingProducts()).thenReturn(ranking);
        when(repositorio.findTop5SellingProducts()).thenReturn(ranking);

        assertEquals(ranking, servicio.getTop10SellingProducts());
        assertEquals(ranking, servicio.getTop5SellingProducts());
    }

    @Test
    void rankingConLimiteVariableRecortaLosResultados() {
        List<Object[]> ventas = List.<Object[]>of(new Object[] { "a", 1 }, new Object[] { "b", 2 },
                new Object[] { "c", 3 });
        when(repositorio.findAllSellingProducts()).thenReturn(ventas);

        assertEquals(2, servicio.getTopSellingProducts(2).size());
        assertEquals(3, servicio.getTopSellingProducts(10).size());
    }

    @Test
    void consultasSinResultadosSeTraducenEnCeros() {
        when(repositorio.getTotalQuantitySoldByProducto(7)).thenReturn(null);
        when(repositorio.getTotalRevenueByProducto(7)).thenReturn(null);
        when(repositorio.countItemsByVenta(9L)).thenReturn(null);

        assertEquals(0, servicio.getTotalQuantitySoldByProducto(7));
        assertEquals(0.0, servicio.getTotalRevenueByProducto(7));
        assertEquals(0, servicio.countItemsByVenta(9L));
    }

    @Test
    void consultasConResultadosSeRetornanTalCual() {
        when(repositorio.getTotalQuantitySoldByProducto(8)).thenReturn(5);
        when(repositorio.getTotalRevenueByProducto(8)).thenReturn(12500.0);
        when(repositorio.countItemsByVenta(10L)).thenReturn(3);

        assertEquals(5, servicio.getTotalQuantitySoldByProducto(8));
        assertEquals(12500.0, servicio.getTotalRevenueByProducto(8));
        assertEquals(3, servicio.countItemsByVenta(10L));
    }
}
