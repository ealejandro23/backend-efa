# Proyecto EFA — Backend

API REST desarrollada con **Java 21 y Spring Boot 4.0.9** para una tienda de ropa online.

Permite gestionar productos, ventas, usuarios, categorías, colores, tallas, materiales, marcas, métodos de pago, métodos de envío e imágenes mediante Cloudinary.

Este repositorio incorpora prácticas y herramientas DevOps para automatizar la compilación, las pruebas, el análisis de calidad, la seguridad, la construcción de imágenes Docker y el despliegue automático en un entorno simulado.

## 1. Tecnologías utilizadas

| Tecnología | Función |
|---|---|
| Java 21 | Lenguaje de programación |
| Spring Boot 4.0.9 | Framework principal |
| Spring Data JPA / Hibernate | Persistencia de datos |
| Spring Security | Configuración de seguridad |
| Spring Validation | Validación de datos |
| PostgreSQL 16 | Base de datos relacional |
| H2 | Base de datos en memoria |
| Springdoc OpenAPI | Documentación Swagger |
| Cloudinary | Gestión de imágenes |
| Maven | Compilación y dependencias |
| JUnit 5 | Pruebas automatizadas |
| JaCoCo | Cobertura de código |
| SonarCloud | Análisis estático y calidad |
| Snyk | Detección de vulnerabilidades |
| Dependabot | Actualización de dependencias |
| Docker | Contenerización |
| Docker Compose | Orquestación de servicios |
| GitHub Actions | Automatización CI/CD |
| AWS ECR / EC2 | Integración prevista para producción |

## 2. Estructura del proyecto

```text
backend-efa/
├── .github/
│   ├── dependabot.yml
│   └── workflows/
│       ├── ci.yml
│       ├── main.yml
│       └── deploy.yml
├── demo/
│   ├── pom.xml
│   └── src/
│       ├── main/
│       │   ├── java/
│       │   │   └── Proyecto_EFA/
│       │   │       └── demo/
│       │   │           ├── config/
│       │   │           ├── controller/
│       │   │           ├── dto/
│       │   │           ├── model/
│       │   │           ├── repository/
│       │   │           └── service/
│       │   └── resources/
│       │       └── application.properties
│       └── test/
├── evidencias/
│   ├── backend-health.json
│   ├── docker-compose-estado.txt
│   └── docker-compose-servicios.txt
├── Dockerfile
├── docker-compose.yml
├── MODELS.md
└── README.md
```

## 3. Funcionalidades principales

- **Productos:** administración del catálogo, categorías, marcas, tallas, materiales y colores.
- **Ventas:** registro, procesamiento de ventas y cálculo de totales.
- **Usuarios y roles:** administración de usuarios y sus roles.
- **Ubicaciones:** gestión de regiones, comunas y direcciones.
- **Métodos de pago y envío:** administración de opciones disponibles.
- **Imágenes:** integración con Cloudinary.
- **Documentación:** endpoints documentados mediante Swagger y OpenAPI.

## 4. Configuración y ejecución local

### Requisitos

- Java JDK 21.
- Maven o Maven Wrapper.
- Docker y Docker Compose.
- Git.

### Ejecutar con Maven

Desde la raíz del repositorio:

```bash
cd demo
./mvnw spring-boot:run
```

En Windows:

```powershell
cd demo
.\mvnw.cmd spring-boot:run
```

La aplicación utiliza por defecto el puerto `8080`.

Cuando no se configura PostgreSQL, puede utilizar H2 según la configuración disponible.

### Swagger UI

```text
http://localhost:8080/doc/swagger-ui.html
```

### Variables de entorno

| Variable | Descripción |
|---|---|
| `PORT` | Puerto interno del backend |
| `SPRING_DATASOURCE_URL` | Conexión JDBC |
| `SPRING_DATASOURCE_USERNAME` | Usuario de base de datos |
| `SPRING_DATASOURCE_PASSWORD` | Contraseña de base de datos |
| `CLOUDINARY_URL` | Configuración de Cloudinary |
| `POSTGRES_DB` | Nombre de la base PostgreSQL |
| `POSTGRES_USER` | Usuario PostgreSQL |
| `POSTGRES_PASSWORD` | Contraseña obligatoria de PostgreSQL |
| `ECR_REGISTRY` | Registro de imágenes Docker |
| `ECR_REPOSITORY` | Repositorio de imágenes |
| `IMAGE_TAG` | Etiqueta de imagen |
| `BACKEND_PORT` | Puerto externo del backend |
| `POSTGRES_PORT` | Puerto externo de PostgreSQL |

Las credenciales reales deben proporcionarse mediante variables de entorno o secretos de GitHub Actions.

No se deben almacenar contraseñas ni tokens reales en el repositorio.

## 5. Contenerización con Docker

El proyecto utiliza un **Dockerfile multietapa** para separar la compilación de la ejecución.

### Etapa de compilación

- Maven 3.9.9.
- Eclipse Temurin Java 21.
- Descarga de dependencias.
- Compilación de la aplicación.
- Generación del archivo JAR.

### Etapa de ejecución

- Eclipse Temurin 21 JRE Alpine.
- Imagen de ejecución más ligera.
- Copia del JAR generado.
- Puerto interno `8080`.
- Ejecución mediante Java.
- Disponibilidad de `curl` para el healthcheck.

La utilización de Alpine permitió solucionar un problema de vulnerabilidades detectado durante el análisis de la imagen Docker anterior.

### Construir la imagen

```bash
docker build -t proyecto-efa-backend:local .
```

### Ejecutar manualmente

```bash
docker run --rm -p 8083:8080 proyecto-efa-backend:local
```

El servicio estará disponible en:

```text
http://localhost:8083
```

Esta ejecución independiente requiere una configuración compatible con la base de datos que se vaya a utilizar.

## 6. Orquestación con Docker Compose

El proyecto utiliza `docker-compose.yml` para administrar dos servicios:

1. Backend Spring Boot.
2. Base de datos PostgreSQL.

### PostgreSQL

- Imagen `postgres:16-alpine`.
- Volumen persistente `efa_pgdata`.
- Healthcheck mediante `pg_isready`.
- Límite de memoria de 512 MB.
- Puerto local predeterminado `5433`.

### Backend

- Aplicación Spring Boot con Java 21.
- Conexión a PostgreSQL por la red interna de Docker.
- Dependencia del estado saludable de la base de datos.
- Healthcheck mediante `/actuator/health`.
- Límite de memoria de 768 MB.
- Puerto interno `8080`.
- Puerto local predeterminado `8083`.

### Validar Docker Compose

Después de configurar las variables obligatorias:

```bash
docker compose config --quiet
```

### Levantar los servicios

```bash
docker compose up -d
```

Este comando requiere que la imagen indicada por `ECR_REGISTRY`, `ECR_REPOSITORY` e `IMAGE_TAG` exista o pueda descargarse, además de configurar la contraseña de PostgreSQL.

### Comprobar contenedores

```bash
docker compose ps
```

### Verificar el backend

```bash
curl http://localhost:8083/actuator/health
```

La respuesta de referencia obtenida durante las pruebas fue:

```json
{
  "groups": [
    "liveness",
    "readiness"
  ],
  "status": "UP"
}
```

### Resultado de las pruebas locales

Se ejecutó Docker Compose con el nombre de proyecto `efa-evaluacion`, utilizando una imagen local del backend.

Se comprobó que:

- PostgreSQL inició correctamente.
- El backend inició correctamente.
- Ambos contenedores alcanzaron el estado `healthy`.
- La aplicación realizó operaciones SQL mediante Hibernate.
- El endpoint `/actuator/health` respondió `UP`.
- Se crearon la red y el volumen de Docker Compose.

Los servicios utilizaron los puertos locales `8083` y `5433`, sin modificar los contenedores existentes de otros proyectos.

Las evidencias se encuentran en el directorio `evidencias/`.

## 7. Pruebas automatizadas con JUnit

El backend integra pruebas automatizadas mediante JUnit 5.

Las pruebas permiten verificar funcionalidades del sistema antes de incorporar cambios al proyecto.

Entre los casos probados se incluyen operaciones relacionadas con el modelo de ventas y el cálculo de totales.

### Ejecutar pruebas

Desde el directorio `demo`:

```bash
mvn clean verify
```

### Resultado obtenido

Durante las ejecuciones de referencia del proyecto:

- Se ejecutaron 34 pruebas.
- Las 34 pruebas aprobaron.
- La compilación Maven terminó correctamente.
- Se generó el reporte de JaCoCo.

Las pruebas están integradas al pipeline de GitHub Actions.

Una falla en las pruebas provoca que el CI no apruebe.

## 8. Cobertura de código con JaCoCo

JaCoCo permite medir las partes del código que son ejecutadas durante las pruebas automatizadas.

El reporte se genera mediante:

```bash
mvn clean verify
```

### Ubicación del reporte

```text
demo/target/site/jacoco/index.html
```

El pipeline guarda el reporte como artifact de GitHub Actions.

La cobertura permite identificar áreas del backend que necesitan pruebas adicionales.

Una cobertura elevada no garantiza por sí sola la ausencia de errores.

## 9. Calidad de código con SonarCloud

El proyecto incorpora análisis estático mediante SonarCloud.

Este análisis permite revisar:

- Calidad del código.
- Mantenibilidad.
- Posibles defectos.
- Riesgos de seguridad.
- Cobertura de pruebas.

SonarCloud recibe los resultados de cobertura generados por JaCoCo.

El análisis utiliza:

```text
sonar.qualitygate.wait=true
```

Esto hace que el pipeline espere el resultado del Quality Gate.

### Control de calidad

Si el Quality Gate falla, el CI se marca como fallido.

El despliegue automático depende de la aprobación del CI, por lo que no se inicia para un push que no supere las verificaciones.

## 10. Seguridad mediante Snyk

Snyk se utiliza para detectar vulnerabilidades conocidas.

El pipeline incorpora dos análisis.

### Análisis de dependencias

```bash
snyk test \
  --file=pom.xml \
  --package-manager=maven \
  --severity-threshold=high
```

Revisa las dependencias Maven utilizadas por el backend.

### Análisis de imagen Docker

```bash
snyk container test proyecto-efa-backend:latest \
  --file=Dockerfile \
  --severity-threshold=high
```

Revisa la imagen Docker y sus componentes.

### Bloqueo de seguridad

Los análisis forman parte del pipeline principal.

Si un análisis obligatorio devuelve un error, el CI falla y el CD queda bloqueado.

Durante el desarrollo se corrigieron vulnerabilidades detectadas en dependencias y en la imagen Docker.

La versión actual del backend utiliza Spring Boot 4.0.9, Tomcat 11.0.27 y Eclipse Temurin 21 JRE Alpine.

## 11. Gestión de dependencias con Dependabot

El archivo `.github/dependabot.yml` configura revisiones semanales para:

- Dependencias Maven.
- Imágenes Docker.
- Acciones de GitHub Actions.

Dependabot genera Pull Requests con propuestas de actualización.

### Validación de actualizaciones

Las actualizaciones deben revisarse antes de fusionarse.

El pipeline complementario utiliza Java 21 para mantener compatibilidad con el backend.

En los Pull Requests creados por Dependabot, los pasos de SonarCloud y Snyk que necesitan secretos se omiten debido a restricciones de acceso a credenciales.

Por esta razón, los Pull Requests automatizados requieren revisión antes de integrarse.

En los pushes a `main`, se ejecutan las verificaciones completas de seguridad y calidad.

## 12. Integración continua y despliegue continuo

La automatización del proyecto se implementa mediante GitHub Actions.

Se utilizan tres workflows principales.

### 12.1. `main.yml` — Integración continua

Nombre:

**CI — Tests, Calidad y Seguridad**

Se activa mediante:

- Push a `main`.
- Pull Request hacia `main`.
- Ejecución manual.

### Etapas

1. Checkout del repositorio.
2. Configuración de Java 21.
3. Configuración de Node.js.
4. Ejecución de pruebas JUnit y JaCoCo.
5. Publicación del reporte de cobertura.
6. Análisis SonarCloud.
7. Escaneo de dependencias con Snyk.
8. Construcción de la imagen Docker.
9. Escaneo de imagen Docker con Snyk.
10. Verificación de la imagen construida.

### Evidencia del CI aprobado

**Workflow:** CI — Tests, Calidad y Seguridad.

**Commit:** `3ed8092`.

**Resultado:** Success.

**Enlace:**

https://github.com/ealejandro23/backend-efa/actions/runs/40418414558

La ejecución confirmó que las verificaciones configuradas para la rama `main` terminaron correctamente.

### 12.2. `ci.yml` — Integración continua complementaria

Este workflow se ejecuta ante:

- Push a `develop`.
- Pull Requests hacia `main`.

Sus etapas incluyen:

1. Checkout del código.
2. Configuración de Java 21.
3. Compilación Maven.
4. Ejecución de pruebas JUnit.
5. Empaquetado de la aplicación.

Se actualizó a Java 21 para evitar errores de incompatibilidad con la versión utilizada por el backend.

### 12.3. `deploy.yml` — Despliegue continuo

Nombre:

**Build, push y deploy backend (AWS EC2 + ECR)**

Se activa automáticamente mediante `workflow_run` cuando finaliza el CI principal.

Para iniciar el proceso de despliegue se comprueba que:

- El CI haya terminado correctamente.
- El evento original sea un push.
- La rama de origen sea `main`.

El workflow utiliza el identificador del commit aprobado:

```text
github.event.workflow_run.head_sha
```

Esto permite construir y desplegar exactamente el código que superó las pruebas.

### Flujo CI/CD

```text
Push a main
     |
     v
GitHub Actions - CI
     |
     +-- Compilación Maven
     |
     +-- Pruebas JUnit
     |
     +-- Cobertura JaCoCo
     |
     +-- SonarCloud
     |
     +-- Snyk dependencias
     |
     +-- Docker Build
     |
     +-- Snyk imagen Docker
     |
     v
¿CI aprobado?
     |
     +-- NO --> Despliegue bloqueado
     |
     +-- SÍ
          |
          v
     Workflow CD
          |
          v
     Construcción de imagen
          |
          v
     Almacenamiento de artifact
          |
          v
     Etapa de publicación
          |
          v
     Docker Compose
          |
          +-- PostgreSQL
          |
          +-- Backend Spring Boot
          |
          v
     Healthchecks
          |
          v
     HTTP /actuator/health
          |
          v
     Despliegue aprobado
```

## 13. Modo demostración — DEMO_MODE

La variable de GitHub Actions `DEMO_MODE` permite ejecutar el pipeline sin requerir un entorno AWS real.

### Configuración

```text
DEMO_MODE=true
```

### Comportamiento

Cuando el modo demostración está activo:

1. El CI ejecuta las pruebas y análisis configurados.
2. El CD construye una imagen Docker del commit aprobado.
3. La imagen se guarda como artifact.
4. Se simula la publicación en Amazon ECR.
5. El trabajo de despliegue recupera la imagen Docker.
6. Se descarga la imagen oficial de PostgreSQL.
7. Se genera una contraseña temporal para PostgreSQL.
8. Se configura el entorno de Docker Compose.
9. Se levantan los contenedores en un runner temporal de GitHub Actions.
10. Se espera a que los contenedores estén saludables.
11. Se consulta el endpoint HTTP `/actuator/health`.
12. El despliegue aprueba si las verificaciones terminan correctamente.

### Diferencia entre simulación y despliegue real

**En modo demostración no se publica realmente la imagen en Amazon ECR ni se utiliza una instancia EC2.**

Sin embargo, sí se ejecuta un despliegue funcional de PostgreSQL y Spring Boot mediante Docker Compose dentro del runner de GitHub Actions.

Por lo tanto:

- La publicación a ECR es simulada.
- La ejecución de Docker Compose es real.
- Las verificaciones de salud son reales.
- Los contenedores son temporales.
- El entorno se elimina cuando finaliza el trabajo de GitHub Actions.

Este comportamiento permite demostrar automatización y orquestación en un entorno cloud simulado.

### Evidencia del CD aprobado

**Workflow:** Build, push y deploy backend (AWS EC2 + ECR).

**Commit:** `3ed8092`.

**Resultado:** Success.

**Enlace:**

https://github.com/ealejandro23/backend-efa/actions/runs/40418765261

En esta ejecución finalizaron correctamente:

- Build de la imagen Docker.
- Etapa de publicación simulada.
- Descarga del artifact.
- Despliegue con Docker Compose en entorno simulado.
- Verificación del estado de Docker Compose.

### Integración prevista con AWS

El workflow conserva pasos para:

- Autenticación con AWS.
- Publicación de imágenes en Amazon ECR.
- Descarga de imágenes desde ECR.
- Ejecución de Docker Compose.

Sin embargo, el trabajo de despliegue utiliza `ubuntu-latest`.

Para desplegar realmente dentro de una instancia EC2 sería necesario implementar un mecanismo remoto, como un runner self-hosted en EC2, SSH o AWS Systems Manager.

No se presenta la ejecución actual como un despliegue real en EC2.

## 14. Seguridad, estabilidad y escalabilidad

Se incorporaron las siguientes medidas:

- Healthcheck de PostgreSQL con `pg_isready`.
- Healthcheck HTTP del backend con Spring Boot Actuator.
- Dependencia de inicio del backend respecto a PostgreSQL.
- Límites de memoria para los contenedores.
- Variables de entorno para configurar servicios.
- Volumen persistente para PostgreSQL.
- Red interna de Docker Compose.
- Escaneos automáticos de seguridad.
- Control de calidad mediante SonarCloud.
- Bloqueo de despliegues cuando falla el CI.
- Identificación de las versiones desplegadas mediante commits Git.

### Límites de memoria

| Servicio | Límite |
|---|---|
| PostgreSQL | 512 MB |
| Backend | 768 MB |

Estas medidas permiten controlar el consumo de recursos en el entorno configurado.

No se implementó escalado horizontal automático.

### Limitaciones de seguridad conocidas

La configuración de `SecurityConfig.java` contiene:

```java
.anyRequest().permitAll()
```

Esto implica que las rutas no tienen una política restrictiva de autorización aplicada mediante esa configuración.

Antes de utilizar el backend en producción se deben revisar:

- Autenticación.
- Autorización por roles.
- Protección de endpoints.
- Manejo seguro de contraseñas.
- Configuración CORS.
- Seguridad del despliegue público.

El proyecto se ha validado como entorno académico y de demostración.

## 15. Trazabilidad y evidencias

La trazabilidad del proyecto se garantiza mediante:

- Historial de commits Git.
- Identificadores de ejecución de GitHub Actions.
- Asociación entre CI y CD.
- Referencia al commit aprobado.
- Resultados de pruebas JUnit.
- Reportes de cobertura JaCoCo.
- Quality Gate de SonarCloud.
- Resultados de Snyk.
- Evidencias de Docker Compose.
- Resultados de comprobaciones HTTP.

### Evidencias oficiales de GitHub Actions

| Evidencia | Resultado | Enlace |
|---|---|---|
| CI — Pruebas, calidad y seguridad | Aprobado | [Ver CI](https://github.com/ealejandro23/backend-efa/actions/runs/40418414558) |
| CD — Docker Compose automático | Aprobado | [Ver CD](https://github.com/ealejandro23/backend-efa/actions/runs/40418765261) |

### Evidencias locales

El repositorio incluye el directorio:

```text
evidencias/
```

Con los archivos:

#### `docker-compose-estado.txt`

Muestra el estado de los contenedores del entorno local.

Se comprobó que tanto PostgreSQL como el backend estaban saludables.

#### `docker-compose-servicios.txt`

Muestra los servicios reconocidos por Docker Compose:

```text
db
backend
```

#### `backend-health.json`

Contiene la respuesta del backend:

```json
{
  "groups": [
    "liveness",
    "readiness"
  ],
  "status": "UP"
}
```

### Resultado del proyecto

Se cuenta con evidencia de:

- Pruebas automatizadas aprobadas.
- Análisis de calidad y seguridad aprobados.
- Construcción automática de imagen Docker.
- Activación del CD después de un CI exitoso.
- Orquestación local de backend y PostgreSQL.
- Despliegue automático mediante Docker Compose en GitHub Actions.
- Comprobación de salud del servicio.

## 16. Control de versiones y GitFlow

El proyecto contempla una estrategia GitFlow para organizar el trabajo.

### Ramas

| Rama | Propósito |
|---|---|
| `main` | Código estable |
| `develop` | Integración de cambios en desarrollo |
| `feature/<nombre>` | Desarrollo de funcionalidades |
| `hotfix/<nombre>` | Correcciones urgentes |

### Convenciones de commits

Se utiliza una convención basada en Conventional Commits.

Ejemplos:

```text
feat(catalogo): agregar filtro por talla
fix(ventas): corregir calculo de totales
test(venta): agregar pruebas de calculo
ci(actions): validar seguridad antes del deploy
docs(readme): actualizar documentacion DevOps
chore(deps): actualizar dependencias
```

### Revisión de cambios

Se recomienda:

1. Crear ramas para nuevas funcionalidades.
2. Realizar commits descriptivos.
3. Crear Pull Requests.
4. Revisar los cambios.
5. Ejecutar las verificaciones automáticas.
6. Integrar únicamente cambios aprobados.

El cumplimiento de estas prácticas debe comprobarse mediante el historial real de Git.

## 17. Documentación adicional

El archivo `MODELS.md` documenta los modelos de datos utilizados por el proyecto.

### Swagger UI

Puerto habitual de ejecución local:

```text
http://localhost:8080/doc/swagger-ui.html
```

Con Docker Compose y la configuración local de referencia:

```text
http://localhost:8083/doc/swagger-ui.html
```

## 18. Correspondencia con la pauta de Ingeniería DevOps

La Evaluación Parcial 2 de Ingeniería DevOps considera cinco indicadores, cada uno con una ponderación del 20%.

| Indicador | Implementación del proyecto | Estado técnico |
|---|---|---|
| IE1 — Contenedores | Dockerfile multietapa e imagen Alpine | Implementado |
| IE2 — Pruebas automatizadas | JUnit, Maven y JaCoCo en CI | Implementado |
| IE3 — Seguridad y escalabilidad | SonarCloud, Snyk, Dependabot, healthchecks y límites de recursos | Implementado |
| IE4 — Despliegue automático | GitHub Actions y Docker Compose en entorno simulado | Implementado |
| IE5 — Orquestación | Backend y PostgreSQL gestionados por Docker Compose | Implementado |

Los cinco indicadores cuentan con una implementación técnica y evidencias asociadas.

La calificación final depende de la revisión y criterios del docente.

## 19. Uso responsable de inteligencia artificial

Durante el desarrollo se utilizaron herramientas de inteligencia artificial como apoyo para:

- Preparación y revisión de configuraciones DevOps.
- Identificación y corrección de errores en pipelines.
- Apoyo en la documentación técnica.
- Revisión de comandos y herramientas.
- Organización de evidencias para la evaluación.

Las recomendaciones y configuraciones propuestas se contrastaron con ejecuciones verificables mediante:

- Maven.
- Docker.
- Docker Compose.
- actionlint.
- GitHub Actions.
- SonarCloud.
- Snyk.

La responsabilidad de validar los cambios, comprender el funcionamiento del proyecto y justificar las decisiones técnicas corresponde a los integrantes del equipo.

Las reflexiones personales exigidas por la pauta deben redactarse individualmente y sin apoyo de inteligencia artificial.

---

## 20. Repositorio y estado final

**Repositorio GitHub:**

https://github.com/ealejandro23/backend-efa

**Último despliegue automatizado validado:**

https://github.com/ealejandro23/backend-efa/actions/runs/40418765261

**Entorno validado:**

- Java 21.
- Spring Boot 4.0.9.
- PostgreSQL 16.
- Docker.
- Docker Compose.
- GitHub Actions.
- JUnit y JaCoCo.
- SonarCloud.
- Snyk.
- Dependabot.

**Estado:** pipeline CI/CD funcional, pruebas y controles de seguridad automatizados, contenedores orquestados y despliegue exitoso en un entorno simulado.

---
