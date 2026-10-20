package Proyecto_EFA.demo;

import Proyecto_EFA.demo.model.ProductoVenta;
import Proyecto_EFA.demo.model.Venta;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;

class VentaModelTest {

    @Test
    void calcularTotalConListaNulaDebeSerCero() {
        Venta venta = new Venta();
        venta.setItems(null);

        venta.calcularTotal();

        assertEquals(0.0, venta.getTotal());
    }

    @Test
    void calcularTotalConListaVaciaDebeSerCero() {
        Venta venta = new Venta();
        venta.setItems(new ArrayList<>());

        venta.calcularTotal();

        assertEquals(0.0, venta.getTotal());
    }

    @Test
    void calcularTotalConElementoNuloDebeIgnorarlo() {
        Venta venta = new Venta();
        venta.setItems(Arrays.asList((ProductoVenta) null));

        venta.calcularTotal();

        assertEquals(0.0, venta.getTotal());
    }

    @Test
    void calcularTotalConSubtotalNuloDebeSerCero() {
        Venta venta = new Venta();

        ProductoVenta item = new ProductoVenta();
        item.setSubtotal(null);

        venta.setItems(Arrays.asList(item));

        venta.calcularTotal();

        assertEquals(0.0, venta.getTotal());
    }

    @Test
    void calcularTotalConSubtotalesValidosDebeSumarlos() {
        Venta venta = new Venta();

        ProductoVenta item1 = new ProductoVenta();
        item1.setSubtotal(5000.0);

        ProductoVenta item2 = new ProductoVenta();
        item2.setSubtotal(3000.0);

        venta.setItems(Arrays.asList(item1, item2));

        venta.calcularTotal();

        assertEquals(8000.0, venta.getTotal());
    }
}
