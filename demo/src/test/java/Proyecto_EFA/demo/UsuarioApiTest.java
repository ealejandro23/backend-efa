package Proyecto_EFA.demo;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.hamcrest.Matchers.startsWith;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
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

import com.fasterxml.jackson.databind.ObjectMapper;

import Proyecto_EFA.demo.model.Usuario;
import Proyecto_EFA.demo.service.UsuarioService;

/**
 * Tests de integración del módulo de usuarios: alta con contraseña
 * encriptada, autenticación por correo o nombre de usuario, búsqueda,
 * actualización (PUT/PATCH), contadores por rol y bajas.
 */
@SpringBootTest
@AutoConfigureMockMvc
class UsuarioApiTest {

    private static final String RUTA = "/api/v1/usuarios";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private UsuarioService usuarioService;

    private int crearRol(String nombre) throws Exception {
        String respuesta = mockMvc.perform(post("/api/v1/roles").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"" + nombre + "\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(respuesta).get("id").asInt();
    }

    private int crearUsuario(String nombre, String correo, String clave, int rolId) throws Exception {
        String json = "{\"nombre\":\"" + nombre + "\",\"correo\":\"" + correo + "\",\"contrasena\":\"" + clave
                + "\",\"rol\":{\"id\":" + rolId + "}}";
        String respuesta = mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON).content(json))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(respuesta).get("id").asInt();
    }

    @Test
    void altaDeUsuarioEncriptaLaContrasenaAntesDeGuardarla() throws Exception {
        int rolId = crearRol("ROL_ALTA");
        String cuerpo = "{\"nombre\":\"cobertura_alta\",\"correo\":\"cobertura_alta@demo.cl\","
                + "\"contrasena\":\"Secreto123\",\"rol\":{\"id\":" + rolId + "}}";

        String creado = mockMvc.perform(post(RUTA).contentType(MediaType.APPLICATION_JSON).content(cuerpo))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.nombre").value("cobertura_alta"))
                .andExpect(jsonPath("$.contrasena").doesNotExist())
                .andReturn().getResponse().getContentAsString();
        int id = objectMapper.readTree(creado).get("id").asInt();

        mockMvc.perform(get(RUTA)).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.correo").value("cobertura_alta@demo.cl"));
        mockMvc.perform(get(RUTA + "/999999")).andExpect(status().isNotFound());

        Usuario guardado = usuarioService.getUsuarioById(id);
        assertNotNull(guardado, "el usuario recién creado debe existir");
        assertTrue(guardado.getContrasena().startsWith("$2"),
                "la contraseña debe guardarse encriptada con BCrypt y nunca en claro");

        mockMvc.perform(delete(RUTA + "/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/roles/" + rolId)).andExpect(status().isNoContent());
    }

    @Test
    void loginAceptaCorreoONombreYRechazaCredencialesInvalidas() throws Exception {
        int rolId = crearRol("ROL_LOGIN");
        int porCorreo = crearUsuario("cobertura_login_correo", "login_correo@demo.cl", "ClaveUno123", rolId);
        int porNombre = crearUsuario("cobertura_login_nombre", "login_nombre@demo.cl", "ClaveDos123", rolId);
        int conCorreoVacio = crearUsuario("cobertura_login_vacio", "login_vacio@demo.cl", "ClaveTres123", rolId);

        mockMvc.perform(post(RUTA + "/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"correo\":\"login_correo@demo.cl\",\"contrasena\":\"ClaveUno123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("cobertura_login_correo"));

        mockMvc.perform(post(RUTA + "/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"cobertura_login_nombre\",\"contrasena\":\"ClaveDos123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("cobertura_login_nombre"));

        mockMvc.perform(post(RUTA + "/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"cobertura_login_vacio\",\"correo\":\"\",\"contrasena\":\"ClaveTres123\"}"))
                .andExpect(status().isOk());

        mockMvc.perform(post(RUTA + "/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"correo\":\"login_correo@demo.cl\",\"contrasena\":\"clave-mala\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post(RUTA + "/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"correo\":\"nadie@demo.cl\",\"contrasena\":\"otra-clave\"}"))
                .andExpect(status().isUnauthorized());

        mockMvc.perform(delete(RUTA + "/" + porCorreo)).andExpect(status().isNoContent());
        mockMvc.perform(delete(RUTA + "/" + porNombre)).andExpect(status().isNoContent());
        mockMvc.perform(delete(RUTA + "/" + conCorreoVacio)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/roles/" + rolId)).andExpect(status().isNoContent());
    }

    @Test
    void busquedaActualizacionContadoresYBajaDeUsuarios() throws Exception {
        int rolId = crearRol("ROL_CONSULTA");
        int id = crearUsuario("cobertura_consulta", "cobertura_consulta@demo.cl", "ClaveConsulta1", rolId);

        mockMvc.perform(get(RUTA + "/search?nombre=cobertura_consulta"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(1)));
        mockMvc.perform(get(RUTA + "/search?nombre=sin_coincidencia_zz")).andExpect(status().isNoContent());

        mockMvc.perform(put(RUTA + "/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"cobertura_consulta_v2\",\"correo\":\"cobertura_v2@demo.cl\","
                                + "\"rol\":{\"id\":" + rolId + "}}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.nombre").value("cobertura_consulta_v2"));

        mockMvc.perform(patch(RUTA + "/" + id).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"contrasena\":\"NuevaClave456\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.correo").value("cobertura_v2@demo.cl"));
        mockMvc.perform(patch(RUTA + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"contrasena\":\"x\"}"))
                .andExpect(status().isNotFound());
        mockMvc.perform(put(RUTA + "/999999").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"nombre\":\"fantasma\"}"))
                .andExpect(status().isNotFound());

        mockMvc.perform(get(RUTA + "/rol/" + rolId))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(greaterThanOrEqualTo(1)));
        mockMvc.perform(get(RUTA + "/comuna/1")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/region/1")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/administradores")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/clientes")).andExpect(status().isOk());
        mockMvc.perform(get(RUTA + "/contar/rol/" + rolId))
                .andExpect(status().isOk())
                .andExpect(content().string("1"));

        mockMvc.perform(delete(RUTA + "/" + id)).andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/v1/roles/" + rolId)).andExpect(status().isNoContent());
    }
}
