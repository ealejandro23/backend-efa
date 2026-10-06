package Proyecto_EFA.demo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.util.Map;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import com.cloudinary.Cloudinary;
import com.cloudinary.Uploader;

import Proyecto_EFA.demo.service.CloudinaryService;

/**
 * Tests unitarios de {@link CloudinaryService}: cubren el guard que exige
 * la configuración de CLOUDINARY_URL y la delegación correcta al SDK de
 * Cloudinary cuando sí está configurado.
 */
class CloudinaryServiceTest {

    @Test
    void sinConfiguracionLanzaErrorExplicativo() {
        CloudinaryService servicio = new CloudinaryService();
        MockMultipartFile archivo = new MockMultipartFile("imagen", "foto.png", "image/png", "datos".getBytes());

        IllegalStateException falloAlSubir = assertThrows(IllegalStateException.class,
                () -> servicio.uploadImage(archivo));
        assertTrue(falloAlSubir.getMessage().contains("CLOUDINARY_URL"));

        IllegalStateException falloAlBorrar = assertThrows(IllegalStateException.class,
                () -> servicio.deleteImage("publico-123"));
        assertTrue(falloAlBorrar.getMessage().contains("CLOUDINARY_URL"));
    }

    @Test
    void subeYBorraImagenesCuandoCloudinaryEstaConfigurado() throws Exception {
        Cloudinary cloudinary = mock(Cloudinary.class);
        Uploader cargador = mock(Uploader.class);
        when(cloudinary.uploader()).thenReturn(cargador);
        when(cargador.upload(any(), any())).thenReturn(Map.of("secure_url", "https://res.cloudinary.com/x.png"));
        when(cargador.destroy(eq("publico-123"), any())).thenReturn(Map.of("result", "ok"));

        CloudinaryService servicio = new CloudinaryService();
        ReflectionTestUtils.setField(servicio, "cloudinary", cloudinary);

        MockMultipartFile archivo = new MockMultipartFile("imagen", "foto.png", "image/png", "contenido".getBytes());
        Map<?, ?> resultado = servicio.uploadImage(archivo);
        assertEquals("https://res.cloudinary.com/x.png", resultado.get("secure_url"));
        verify(cargador).upload(any(), any());

        servicio.deleteImage("publico-123");
        verify(cargador).destroy(eq("publico-123"), any());
    }
}
