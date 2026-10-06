package Proyecto_EFA.demo;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
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

/**
 * Tests de integración HTTP para los controladores del catálogo base:
 * categorías, colores, marcas, tallas, materiales, estados, roles e imágenes.
 * Al correr contra el contexto completo (H2 en memoria) también ejercitan los
 * servicios y repositorios correspondientes de extremo a extremo.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CatalogoApiTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    private int crearYDevolverId(String ruta, String cuerpo) throws Exception {
        String respuesta = mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON).content(cuerpo))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        JsonNode nodo = objectMapper.readTree(respuesta);
        return nodo.get("id").asInt();
    }

    @Test
    void categoriasSePuedenCrearConsultarEditarYEliminar() throws Exception {
        int id = crearYDevolverId("/api/v1/categorias",
                "{\"nombre\":\"Categoria Cobertura\",\"descripcion\":\"generada por los tests\"}");

        mockMvc.perform(get("/api/v1/categorias")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/categorias/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Categoria Cobertura"));
        mockMvc.perform(get("/api/v1/categorias/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put("/api/v1/categorias/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Categoria Cobertura Editada\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Categoria Cobertura Editada"));

        mockMvc.perform(put("/api/v1/categorias/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Inexistente\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/categorias/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void coloresSeEditanInclusoConCuerpoVacioYSeEliminan() throws Exception {
        int id = crearYDevolverId("/api/v1/colores", "{\"nombre\":\"Color Cobertura\"}");

        mockMvc.perform(get("/api/v1/colores")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/colores/" + id)).andExpect(status().isOk());

        mockMvc.perform(put("/api/v1/colores/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Color Cobertura Azul\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Color Cobertura Azul"));

        mockMvc.perform(put("/api/v1/colores/" + id).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Color Cobertura Azul"));

        mockMvc.perform(get("/api/v1/colores/999999")).andExpect(status().isNotFound());
        mockMvc.perform(delete("/api/v1/colores/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/colores/" + id)).andExpect(status().isNotFound());
    }

    @Test
    void marcasSeRecuperanTrasSerEditadas() throws Exception {
        int id = crearYDevolverId("/api/v1/marcas", "{\"nombre\":\"Marca Cobertura\"}");

        mockMvc.perform(get("/api/v1/marcas/" + id)).andExpect(status().isOk());
        mockMvc.perform(put("/api/v1/marcas/" + id).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Marca Cobertura"));
        mockMvc.perform(put("/api/v1/marcas/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Marca Cobertura 2\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Marca Cobertura 2"));

        mockMvc.perform(delete("/api/v1/marcas/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/marcas/" + id)).andExpect(status().isNotFound());
        mockMvc.perform(delete("/api/v1/marcas/999999")).andExpect(status().isNoContent());
    }

    @Test
    void tallasSeCreaEditaYBorra() throws Exception {
        int id = crearYDevolverId("/api/v1/tallas",
                "{\"nombre\":\"Talla Cobertura\",\"descripcion\":\"unitalla de prueba\"}");

        mockMvc.perform(get("/api/v1/tallas/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.descripcion").value("unitalla de prueba"));

        mockMvc.perform(put("/api/v1/tallas/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Talla Cobertura XL\",\"descripcion\":\"redimensionada\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Talla Cobertura XL"));
        mockMvc.perform(put("/api/v1/tallas/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/tallas/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/tallas")).andExpect(status().isOk());
    }

    @Test
    void materialesSeEditanPorId() throws Exception {
        int id = crearYDevolverId("/api/v1/materiales",
                "{\"nombre\":\"Material Cobertura\",\"descripcion\":\"poliester\"}");

        mockMvc.perform(get("/api/v1/materiales/" + id)).andExpect(status().isOk());
        mockMvc.perform(put("/api/v1/materiales/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Material Cobertura Plus\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Material Cobertura Plus"));
        mockMvc.perform(get("/api/v1/materiales/999999")).andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/materiales/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void estadosSeDanDeAltaSeConsultanYSeBoran() throws Exception {
        int id = crearYDevolverId("/api/v1/estados", "{\"nombre\":\"Estado Cobertura\"}");

        mockMvc.perform(get("/api/v1/estados")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/estados/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Estado Cobertura"));
        mockMvc.perform(get("/api/v1/estados/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put("/api/v1/estados/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"Estado Cobertura Enviado\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("Estado Cobertura Enviado"));
        mockMvc.perform(put("/api/v1/estados/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/estados/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/estados/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void rolesSeGestionanDesdeElApi() throws Exception {
        int id = crearYDevolverId("/api/v1/roles", "{\"nombre\":\"ROL_COBERTURA\"}");

        mockMvc.perform(get("/api/v1/roles")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/roles/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("ROL_COBERTURA"));
        mockMvc.perform(get("/api/v1/roles/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put("/api/v1/roles/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"ROL_COBERTURA_EDITADO\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("ROL_COBERTURA_EDITADO"));
        mockMvc.perform(put("/api/v1/roles/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/roles/" + id)).andExpect(status().isNoContent());
    }

    @Test
    void imagenesSeCreanSeEditanYSeEliminan() throws Exception {
        int id = crearYDevolverId("/api/v1/imagenes",
                "{\"url\":\"https://img.cobertura.test/original.png\"}");

        mockMvc.perform(get("/api/v1/imagenes/" + id)).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/imagenes/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put("/api/v1/imagenes/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"https://img.cobertura.test/editada.png\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.url").value("https://img.cobertura.test/editada.png"));
        mockMvc.perform(put("/api/v1/imagenes/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"url\":\"nada.png\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/v1/imagenes/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(get("/api/v1/imagenes/" + id)).andExpect(status().isNotFound());
    }
}
