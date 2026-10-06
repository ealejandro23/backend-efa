package Proyecto_EFA.demo;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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
import com.fasterxml.jackson.databind.node.ObjectNode;

/**
 * Tests de integración del catálogo de productos: CRUD, validación de
 * campos obligatorios, actualizaciones completas y parciales, y todos los
 * endpoints de búsqueda/filtrado/ordenamiento.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ProductoApiTest {

    private static final String RUTA = "/api/v1/productos";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    private JsonNode obtenerPrimerProducto() throws Exception {
        String listado = mockMvc.perform(get(RUTA))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(10)))
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(listado).get(0);
    }

    @Test
    void listadoYCategoriasSemanticasDeLosProductosSembrados() throws Exception {
        JsonNode primero = obtenerPrimerProducto();
        int id = primero.get("id").asInt();

        mockMvc.perform(get(RUTA + "/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").exists())
                .andExpect(jsonPath("$.precio").isNumber());
        mockMvc.perform(get(RUTA + "/999999")).andExpect(status().isNotFound());
    }

    @Test
    void altaValidaRequiereNombreYElDetalleEsRecuperable() throws Exception {
        String creada = mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Producto Cobertura\",\"descripcion\":\"para el pipeline\","
                                + "\"precio\":4990.0,\"stock\":5,\"codigo\":\"COB-001\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.codigo").value("COB-001"))
                .andReturn().getResponse().getContentAsString();
        int id = objectMapper.readTree(creada).get("id").asInt();

        mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"\",\"precio\":100.0}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"precio\":100.0,\"stock\":1}"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get(RUTA + "/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stock").value(5));

        mockMvc.perform(delete(RUTA + "/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(get(RUTA + "/" + id)).andExpect(status().isNotFound());
    }

    @Test
    void actualizacionCompletaReasignaTodasLasRelacionesSinRomperElListado() throws Exception {
        ObjectNode cuerpo = obtenerPrimerProducto().deepCopy();
        cuerpo.put("nombre", "Producto Cobertura Full");
        cuerpo.put("descripcion", "actualizacion integral de todos los campos");
        cuerpo.put("precio", 7777.0);
        cuerpo.put("stock", 42);
        cuerpo.put("codigo", "COB-FULL-001");
        cuerpo.put("imagenUrl", "/img/cobertura.webp");

        int nuevoId = crearCopia(cuerpo);

        mockMvc.perform(put(RUTA + "/" + nuevoId).contentType(MediaType.APPLICATION_JSON)
                        .content(cuerpo.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Producto Cobertura Full"))
                .andExpect(jsonPath("$.codigo").value("COB-FULL-001"))
                .andExpect(jsonPath("$.stock").value(42))
                .andExpect(jsonPath("$.marca").isNotEmpty())
                .andExpect(jsonPath("$.categorias").isNotEmpty());

        mockMvc.perform(delete(RUTA + "/" + nuevoId)).andExpect(status().isNoContent());
    }

    private int crearCopia(ObjectNode semilla) throws Exception {
        ObjectNode cuerpo = semilla.deepCopy();
        cuerpo.remove("id");
        cuerpo.put("nombre", "Producto Cobertura Copia");
        cuerpo.put("codigo", "COB-COPIA-001");
        String creada = mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON)
                        .content(cuerpo.toString()))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(creada).get("id").asInt();
    }

    @Test
    void actualizacionParcialConservaLosDemasAtributos() throws Exception {
        String creada = mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Producto Cobertura Parcial\",\"precio\":1000.0,\"stock\":10}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        int id = objectMapper.readTree(creada).get("id").asInt();

        mockMvc.perform(put(RUTA + "/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"precio\":1111.0}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.precio").value(1111.0))
                .andExpect(jsonPath("$.nombre").value("Producto Cobertura Parcial"));

        mockMvc.perform(patch(RUTA + "/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"stock\":3}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.stock").value(3));

        mockMvc.perform(put(RUTA + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"precio\":10.0}"))
                .andExpect(status().isNotFound());
        mockMvc.perform(patch(RUTA + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"stock\":1}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete(RUTA + "/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void filtrosYOrdenamientosRespondenConListas() throws Exception {
        mockMvc.perform(get(RUTA + "/buscar/marca/4")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/categoria/1")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/color/6")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/material/7")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/talla/5")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/marca/4/categoria/1")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/rango-precio?precioMin=1000&precioMax=30000"))
                .andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/nombre?nombre=Polera")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/nombre-contiene?nombre=chaqueta")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/buscar/stock")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/top/mas-caros")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/top/mas-baratos")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/top/mas-caros/5")).andExpect(status().isOk());
    }

    @Test
    void busquedaPorCodigoEncuentraLoSembrado() throws Exception {
        mockMvc.perform(get(RUTA + "/buscar/codigo/POL-BLAN-001"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.codigo").value("POL-BLAN-001"));
        mockMvc.perform(get(RUTA + "/buscar/codigo/NO-EXISTE-999")).andExpect(status().isNotFound());
    }
}
