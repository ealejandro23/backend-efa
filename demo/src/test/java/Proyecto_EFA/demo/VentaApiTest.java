package Proyecto_EFA.demo;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * Tests de integración del flujo de ventas: creación de una venta completa
 * con sus ítems, todas las consultas de filtrado, validaciones de datos
 * inválidos, y la protección de borrado de métodos de pago/envío asociados a
 * ventas. Incluye también los endpoints de producto-venta (ítems de venta).
 */
@SpringBootTest
@AutoConfigureMockMvc
class VentaApiTest {

    private static final String VENTAS = "/api/v1/ventas";
    private static final String ITEMS = "/api/v1/producto-ventas";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    private int crearEn(String ruta, String cuerpo) throws Exception {
        String respuesta = mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON).content(cuerpo))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(respuesta).get("id").asInt();
    }

    @Test
    void flujoCompletoDeVentaConItemsConsultasYProteccionDeBorrado() throws Exception {
        int estadoId = crearEn("/api/v1/estados", "{\"nombre\":\"Estado Cobertura Venta\"}");
        int pagoId = crearEn("/api/v1/metodos-pago", "{\"nombre\":\"PagoCoberturaVenta\",\"descripcion\":\"web\"}");
        int envioId = crearEn("/api/v1/metodos-envio",
                "{\"nombre\":\"EnvioCoberturaVenta\",\"descripcion\":\"courier\",\"precio\":2000.0}");
        int usuarioId = crearEn("/api/v1/usuarios",
                "{\"nombre\":\"cobertura_venta\",\"correo\":\"cobertura_venta@demo.cl\",\"contrasena\":\"ClaveVenta1\"}");
        int productoId = crearEn("/api/v1/productos",
                "{\"nombre\":\"Producto Cobertura Venta\",\"precio\":5000.0,\"stock\":10,\"codigo\":\"COB-VENTA-001\"}");

        String ventaJson = "{\"usuarioId\":" + usuarioId + ",\"estadoId\":" + estadoId
                + ",\"metodoPagoId\":" + pagoId + ",\"metodoEnvioId\":" + envioId
                + ",\"items\":[{\"productoId\":" + productoId + ",\"cantidad\":2,\"precio\":5000.0}]}";
        String creada = mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON).content(ventaJson))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.total").value(10000.0))
                .andExpect(jsonPath("$.usuario.nombre").value("cobertura_venta"))
                .andReturn().getResponse().getContentAsString();

        JsonNode cuerpoVenta = objectMapper.readTree(creada);
        long ventaId = cuerpoVenta.get("id").asLong();
        String numeroVenta = cuerpoVenta.get("numeroVenta").asText();

        mockMvc.perform(get(VENTAS)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/" + ventaId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/999999")).andExpect(status().isNotFound());
        mockMvc.perform(get(VENTAS + "/usuario/" + usuarioId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/estado/" + estadoId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/metodo-pago/" + pagoId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/metodo-envio/" + envioId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/numero/" + numeroVenta)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/pendientes")).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/entregadas")).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/usuario/" + usuarioId + "/estado/" + estadoId)).andExpect(status().isOk());
        mockMvc.perform(get(VENTAS + "/contar/usuario/" + usuarioId))
                .andExpect(status().isOk())
                .andExpect(content().string("1"));
        mockMvc.perform(get(VENTAS + "/totales")).andExpect(status().isOk());

        mockMvc.perform(put(VENTAS + "/" + ventaId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"numeroVenta\":\"VEN-COB-EDITADA\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.numeroVenta").value("VEN-COB-EDITADA"));
        mockMvc.perform(patch(VENTAS + "/" + ventaId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"estado\":{\"id\":" + estadoId + "}}"))
                .andExpect(status().isOk());
        mockMvc.perform(put(VENTAS + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"numeroVenta\":\"x\"}"))
                .andExpect(status().isNotFound());
        mockMvc.perform(patch(VENTAS + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"numeroVenta\":\"x\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(get(ITEMS)).andExpect(status().isOk());
        String itemsDeLaVenta = mockMvc.perform(get(ITEMS + "/venta/" + ventaId))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        JsonNode primerItem = objectMapper.readTree(itemsDeLaVenta).get(0);
        long itemId = primerItem.get("id").asLong();

        mockMvc.perform(get(ITEMS + "/" + itemId)).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/venta/" + ventaId + "/producto/" + productoId)).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/producto/" + productoId)).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/producto/" + productoId + "/cantidad-vendida"))
                .andExpect(status().isOk())
                .andExpect(content().string("2"));
        mockMvc.perform(get(ITEMS + "/producto/" + productoId + "/ingresos")).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/venta/" + ventaId + "/contar-items"))
                .andExpect(status().isOk())
                .andExpect(content().string("1"));
        mockMvc.perform(get(ITEMS + "/top-vendidos?limit=3")).andExpect(status().isOk());

        mockMvc.perform(put(ITEMS + "/" + itemId).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"cantidad\":3,\"precioUnitario\":5000.0,\"subtotal\":15000.0}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.cantidad").value(3));
        mockMvc.perform(put(ITEMS + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"cantidad\":1}"))
                .andExpect(status().isNotFound());
        mockMvc.perform(post(ITEMS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"venta\":{\"id\":" + ventaId + "},\"producto\":{\"id\":" + productoId + "},"
                                + "\"cantidad\":1,\"precioUnitario\":100.0,\"subtotal\":100.0}"))
                .andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/999999")).andExpect(status().isNotFound());
        mockMvc.perform(get(ITEMS + "/venta/999999/producto/999999")).andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/metodos-envio/" + envioId))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("ventas asociadas")));
        mockMvc.perform(delete("/api/v1/metodos-pago/" + pagoId))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("ventas asociadas")));

        mockMvc.perform(delete(VENTAS + "/" + ventaId)).andExpect(status().isNoContent());
        mockMvc.perform(get(ITEMS + "/" + itemId)).andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/metodos-envio/" + envioId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/metodos-pago/" + pagoId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/estados/" + estadoId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/usuarios/" + usuarioId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/productos/" + productoId)).andExpect(status().isNoContent());
    }

    @Test
    void validacionesDeVentaRechazanDatosIncompletos() throws Exception {
        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("al menos un producto")));

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":999999,\"estadoId\":1,\"metodoPagoId\":1,\"metodoEnvioId\":1,"
                                + "\"items\":[{\"productoId\":1,\"cantidad\":1,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Usuario no encontrado")));

        int estadoId = crearEn("/api/v1/estados", "{\"nombre\":\"Estado Cobertura Validacion\"}");
        int pagoId = crearEn("/api/v1/metodos-pago", "{\"nombre\":\"PagoCoberturaValidacion\"}");
        int envioId = crearEn("/api/v1/metodos-envio", "{\"nombre\":\"EnvioCoberturaValidacion\",\"precio\":1000.0}");
        int usuarioId = crearEn("/api/v1/usuarios",
                "{\"nombre\":\"cobertura_validacion\",\"correo\":\"cobertura_validacion@demo.cl\",\"contrasena\":\"ClaveValid1\"}");

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":" + usuarioId + ",\"estadoId\":999999,\"metodoPagoId\":" + pagoId
                                + ",\"metodoEnvioId\":" + envioId
                                + ",\"items\":[{\"productoId\":1,\"cantidad\":1,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Estado no encontrado")));

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":" + usuarioId + ",\"estadoId\":" + estadoId
                                + ",\"metodoPagoId\":999999,\"metodoEnvioId\":" + envioId
                                + ",\"items\":[{\"productoId\":1,\"cantidad\":1,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Método de pago no encontrado")));

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":" + usuarioId + ",\"estadoId\":" + estadoId
                                + ",\"metodoPagoId\":" + pagoId + ",\"metodoEnvioId\":999999,"
                                + "\"items\":[{\"productoId\":1,\"cantidad\":1,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Método de envío no encontrado")));

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":" + usuarioId + ",\"estadoId\":" + estadoId
                                + ",\"metodoPagoId\":" + pagoId + ",\"metodoEnvioId\":" + envioId
                                + ",\"items\":[{\"productoId\":1,\"cantidad\":0,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("cantidad de cada producto")));

        mockMvc.perform(post(VENTAS).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"usuarioId\":" + usuarioId + ",\"estadoId\":" + estadoId
                                + ",\"metodoPagoId\":" + pagoId + ",\"metodoEnvioId\":" + envioId
                                + ",\"items\":[{\"productoId\":999999,\"cantidad\":1,\"precio\":100.0}]}"))
                .andExpect(status().isBadRequest())
                .andExpect(content().string(org.hamcrest.Matchers.containsString("Producto no encontrado")));

        String original = mockMvc.perform(post(VENTAS + "/original").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"numeroVenta\":\"VEN-ORIGINAL-COB\",\"usuario\":{\"id\":" + usuarioId + "}}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        long originalId = objectMapper.readTree(original).get("id").asLong();

        mockMvc.perform(delete(VENTAS + "/" + originalId)).andExpect(status().isNoContent());
        mockMvc.perform(delete(VENTAS + "/999999")).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/usuarios/" + usuarioId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/metodos-envio/" + envioId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/metodos-pago/" + pagoId)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/estados/" + estadoId)).andExpect(status().isNoContent());
    }

    @Test
    void consultasDeItemsDeVentaSinDatosDevuelvenCeros() throws Exception {
        mockMvc.perform(get(ITEMS + "/producto/999999/cantidad-vendida"))
                .andExpect(status().isOk())
                .andExpect(content().string("0"));
        mockMvc.perform(get(ITEMS + "/producto/999999/ingresos"))
                .andExpect(status().isOk())
                .andExpect(content().string("0.0"));
        mockMvc.perform(get(ITEMS + "/venta/999999/contar-items"))
                .andExpect(status().isOk())
                .andExpect(content().string("0"));
        mockMvc.perform(get(ITEMS + "/venta/999999")).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/producto/999999")).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/top-vendidos")).andExpect(status().isOk());
        mockMvc.perform(get(ITEMS + "/999999")).andExpect(status().isNotFound());
    }
}
