package Proyecto_EFA.demo;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
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

import com.fasterxml.jackson.databind.ObjectMapper;

import Proyecto_EFA.demo.service.MetodoEnvioService;

/**
 * Tests de integración de los métodos de pago y de envío, centrados en las
 * reglas de negocio: nombres duplicados, precios negativos, borrados
 * inexistentes y la consulta de existencia del servicio de envíos.
 */
@SpringBootTest
@AutoConfigureMockMvc
class MetodosPagoEnvioApiTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private MetodoEnvioService metodoEnvioService;

    private int crearEn(String ruta, String cuerpo) throws Exception {
        String respuesta = mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON).content(cuerpo))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(respuesta).get("id").asInt();
    }

    @Test
    void metodosDePagoValidanDuplicadosYActualizaciones() throws Exception {
        String ruta = "/api/v1/metodos-pago";
        int principal = crearEn(ruta, "{\"nombre\":\"PagoCobertura\",\"descripcion\":\"credito\"}");
        int secundario = crearEn(ruta, "{\"nombre\":\"PagoCoberturaB\",\"descripcion\":\"debito\"}");

        mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"PagoCobertura\"}"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get(ruta)).andExpect(status().isOk());
        mockMvc.perform(get(ruta + "/" + principal))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("PagoCobertura"));
        mockMvc.perform(get(ruta + "/nombre/PagoCoberturaB")).andExpect(status().isOk());
        mockMvc.perform(get(ruta + "/nombre/PagoInexistente")).andExpect(status().isNotFound());
        mockMvc.perform(get(ruta + "/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"PagoCoberturaV2\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("PagoCoberturaV2"));
        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"PagoCoberturaB\"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"descripcion\":\"solo cambia la descripcion\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(put(ruta + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(patch(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"PagoCoberturaV2\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(patch(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"PagoCoberturaB\"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(patch(ruta + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete(ruta + "/999999")).andExpect(status().isNoContent());
        mockMvc.perform(delete(ruta + "/" + principal)).andExpect(status().isNoContent());
        mockMvc.perform(delete(ruta + "/" + secundario)).andExpect(status().isNoContent());
        mockMvc.perform(get(ruta + "/" + principal)).andExpect(status().isNotFound());
    }

    @Test
    void metodosDeEnvioRechazanPreciosNegativosYNombresRepetidos() throws Exception {
        String ruta = "/api/v1/metodos-envio";
        int principal = crearEn(ruta, "{\"nombre\":\"EnvioCobertura\",\"descripcion\":\"courier\",\"precio\":1500.0}");
        int secundario = crearEn(ruta, "{\"nombre\":\"EnvioCoberturaB\",\"descripcion\":\"retiro\",\"precio\":0.0}");

        mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"EnvioCoberturaGratis\",\"precio\":-1.0}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(post(ruta).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"EnvioCobertura\",\"precio\":999.0}"))
                .andExpect(status().isBadRequest());

        assertTrue(metodoEnvioService.existsById(principal), "el envío recién creado debe existir");
        assertFalse(metodoEnvioService.existsById(999999), "un id inventado no debe existir");

        mockMvc.perform(get(ruta)).andExpect(status().isOk());
        mockMvc.perform(get(ruta + "/nombre/EnvioCobertura")).andExpect(status().isOk());
        mockMvc.perform(get(ruta + "/nombre/EnvioInexistente")).andExpect(status().isNotFound());
        mockMvc.perform(get(ruta + "/" + principal))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.precio").value(1500.0));
        mockMvc.perform(get(ruta + "/999999")).andExpect(status().isNotFound());

        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"EnvioCobertura\",\"descripcion\":\"express\",\"precio\":2500.0}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.precio").value(2500.0));
        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"precio\":-5.0}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(put(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"EnvioCoberturaB\"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(put(ruta + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(patch(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"EnvioCobertura\"}"))
                .andExpect(status().isOk());
        mockMvc.perform(patch(ruta + "/" + principal).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"precio\":-2.0}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(patch(ruta + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete(ruta + "/999999")).andExpect(status().isNoContent());
        mockMvc.perform(delete(ruta + "/" + principal)).andExpect(status().isNoContent());
        mockMvc.perform(delete(ruta + "/" + secundario)).andExpect(status().isNoContent());
        assertFalse(metodoEnvioService.existsById(principal), "tras el borrado ya no debe existir");
    }
}
