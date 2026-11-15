package Proyecto_EFA.demo.observability;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.info.Info;
import org.springframework.boot.actuate.info.InfoContributor;
import org.springframework.stereotype.Component;

/**
 * Publica los metadatos de build en el endpoint {@code /actuator/info}.
 *
 * <p>Estos datos son los que permiten, desde el panel de observabilidad,
 * saber exactamente que commit y que version estan en ejecucion. Es el
 * insumo de la trazabilidad "del desarrollo a la produccion simulada"
 * exigida por la pauta: la metrica y el log se pueden correlacionar con el
 * commit que los produjo.
 */
@Component
public class BuildInfoContributor implements InfoContributor {

    private final String appName;
    private final String version;
    private final String commit;
    private final String branch;
    private final String buildTime;
    private final String environment;

    public BuildInfoContributor(@Value("${info.app.name:Proyecto EFA API}") String appName,
                                @Value("${info.app.version:dev}") String version,
                                @Value("${info.app.commit:unknown}") String commit,
                                @Value("${info.app.branch:unknown}") String branch,
                                @Value("${info.app.buildTime:unknown}") String buildTime,
                                @Value("${info.app.environment:dev}") String environment) {
        this.appName = appName;
        this.version = version;
        this.commit = commit;
        this.branch = branch;
        this.buildTime = buildTime;
        this.environment = environment;
    }

    @Override
    public void contribute(Info.Builder builder) {
        builder.withDetail("app", appName)
                .withDetail("version", version)
                .withDetail("commit", commit)
                .withDetail("branch", branch)
                .withDetail("buildTime", buildTime)
                .withDetail("environment", environment);
    }
}
