package Proyecto_EFA.demo.config;

import com.cloudinary.Cloudinary;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnExpression;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Configuracion del cliente de Cloudinary.
 *
 * <p>Cloudinary es una dependencia <strong>opcional</strong>: solo se usa
 * para la carga de imagenes del catalogo. Si no hay URL configurada, el bean
 * no se crea y la aplicacion arranca con normalidad (el servicio de
 * imagenes ya contempla la ausencia del bean).
 *
 * <p>Esto es necesario en los entornos orquestados, donde la credencial
 * llega desde un Secret que puede no existir: la aplicacion no debe
 * impedir que el resto del servicio funcione por una funcionalidad
 * opcional.
 */
@Configuration
@ConditionalOnExpression("!'${cloudinary.url:}'.isEmpty()")
public class CloudinaryConfig {

    private static final Logger log = LoggerFactory.getLogger(CloudinaryConfig.class);

    @Bean
    public Cloudinary cloudinary(@Value("${cloudinary.url}") String cloudinaryUrl) {
        // Se valida el formato antes de construir el cliente: sin esta
        // comprobacion, la libreria lanza una excepcion cuyo mensaje no
        // indica que variable ni que valor es el incorrecto.
        if (cloudinaryUrl == null || !cloudinaryUrl.startsWith("cloudinary://")) {
            log.warn("CLOUDINARY_URL no tiene el formato esperado (cloudinary://...). "
                    + "La carga de imagenes no estara disponible.");
            throw new IllegalStateException(
                    "CLOUDINARY_URL debe tener el formato 'cloudinary://<api_key>:<api_secret>@<cloud_name>'. "
                    + "Revise el Secret 'efa-secrets' del namespace.");
        }

        log.info("Cliente de Cloudinary configurado.");
        return new Cloudinary(cloudinaryUrl);
    }
}
