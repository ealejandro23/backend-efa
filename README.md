# Proyecto EFA — Backend

API REST desarrollada con **Java 21 y Spring Boot 4.0.8** para una tienda de ropa online. Permite gestionar productos, ventas, usuarios, categorías, colores, tallas, materiales, marcas, métodos de pago, métodos de envío e imágenes mediante Cloudinary.

Este repositorio también incorpora herramientas y prácticas DevOps para automatizar la compilación, las pruebas, el análisis de calidad, la seguridad y la construcción de imágenes Docker.

## 1. Tecnologías utilizadas

| Tecnología | Función |
|---|---|
| Java 21 | Lenguaje de programación |
| Spring Boot 4.0.8 | Framework principal del backend |
| Spring Data JPA / Hibernate | Persistencia de datos |
| Spring Security | Configuración de seguridad |
| Spring Validation | Validación de datos |
| PostgreSQL 16 | Base de datos relacional |
| H2 | Base de datos en memoria para desarrollo |
| Springdoc OpenAPI | Documentación Swagger |
| Cloudinary | Gestión y almacenamiento de imágenes |
| Maven | Gestión de dependencias y compilación |
| JUnit 5 | Pruebas automatizadas |
| JaCoCo | Cobertura de código |
| SonarCloud | Análisis estático y calidad |
| Snyk | Detección de vulnerabilidades |
| Dependabot | Actualización automatizada de dependencias |
| Docker | Construcción y ejecución de contenedores |
| Docker Compose | Orquestación de servicios |
| GitHub Actions | Automatización de CI/CD |
| AWS ECR / EC2 | Servicios previstos para publicación y despliegue |

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
├── Dockerfile
├── docker-compose.yml
├── MODELS.md
└── README.md
```

## 3. Funcionalidades principales

- **Productos:** administración del catálogo, categorías, marcas, tallas, materiales y colores.
- **Ventas:** registro y procesamiento de ventas, productos asociados y cálculo de totales.
- **Usuarios y roles:** gestión de información de usuarios y roles.
- **Ubicaciones:** administración de regiones, comunas y direcciones.
- **Métodos de pago y envío:** administración de las opciones disponibles.
- **Imágenes:** integración con Cloudinary.
- **Documentación de API:** Swagger UI y OpenAPI.

## 4. Configuración y ejecución local

### Requisitos

- JDK 21.
- Maven o Maven Wrapper.
- Docker y Docker Compose, cuando se utilicen contenedores.
- Git.

### Ejecutar con Maven

Desde la raíz del repositorio:

```bash
cd demo
./mvnw spring-boot:run
```

En Windows también puede utilizarse:

```powershell
cd demo
.\mvnw.cmd spring-boot:run
```

La API utiliza por defecto el puerto `8080` y puede funcionar con H2 en memoria cuando no se configura una base de datos externa.

Swagger UI:

```text
http://localhost:8080/doc/swagger-ui.html
```

### Variables de entorno

| Variable | Descripción |
|---|---|
| `PORT` | Puerto interno del backend, por defecto 8080 |
| `SPRING_DATASOURCE_URL` | URL JDBC de la base de datos |
| `SPRING_DATASOURCE_USERNAME` | Usuario de la base de datos |
| `SPRING_DATASOURCE_PASSWORD` | Contraseña de la base de datos |
| `CLOUDINARY_URL` | Configuración de Cloudinary |
| `POSTGRES_DB` | Nombre de la base PostgreSQL |
| `POSTGRES_USER` | Usuario PostgreSQL |
| `POSTGRES_PASSWORD` | Contraseña obligatoria para Docker Compose |
| `ECR_REGISTRY` | Registro de imágenes Docker |
| `ECR_REPOSITORY` | Repositorio de imágenes |
| `IMAGE_TAG` | Etiqueta de la imagen, por defecto `latest` |
| `BACKEND_PORT` | Puerto externo local del backend, por defecto 8083 |
| `POSTGRES_PORT` | Puerto externo local de PostgreSQL, por defecto 5433 |

Las credenciales reales deben proporcionarse mediante variables de entorno o secretos, evitando incluirlas en los commits.

## 5. Docker

El proyecto utiliza un Dockerfile con construcción multietapa.

**Etapa de compilación:**

- Imagen base Maven 3.9.9 con Eclipse Temurin 21.
- Compilación y empaquetado de la aplicación.
- Generación del archivo JAR.

**Etapa de ejecución:**

- Imagen Eclipse Temurin 21 JRE.
- Copia del JAR compilado.
- Exposición del puerto interno 8080.
- Ejecución del backend mediante Java.

### Construir imagen manualmente

```bash
docker build -t proyecto-efa-backend:local .
```

### Ejecutar el contenedor sin PostgreSQL externo

Cuando se utiliza la configuración local con H2:

```bash
docker run --rm -p 8083:8080 proyecto-efa-backend:local
```

La API quedará accesible desde `http://localhost:8083`, siempre que ese puerto esté disponible.

## 6. Docker Compose

El archivo `docker-compose.yml` define dos servicios principales:

**PostgreSQL:**

- Imagen PostgreSQL 16 Alpine.
- Volumen persistente `efa_pgdata`.
- Healthcheck mediante `pg_isready`.
- Límite de memoria de 512 MB.
- Puerto externo configurable, por defecto `127.0.0.1:5433`.

**Backend:**

- Imagen definida mediante las variables del registro Docker.
- Dependencia del estado saludable de PostgreSQL.
- Healthcheck HTTP en `/actuator/health`.
- Límite de memoria de 768 MB.
- Puerto interno 8080.
- Puerto externo configurable, por defecto `127.0.0.1:8083`.

El uso de `127.0.0.1` restringe el acceso directo desde otros equipos. Para exponer el backend públicamente se necesita configurar una entrada segura, como un proxy inverso con HTTPS.

### Validar la configuración

Con las variables necesarias definidas:

```bash
docker compose config --quiet
```

### Levantar los servicios

Una vez configuradas las credenciales y la imagen:

```bash
docker compose up -d
```

Este comando modifica el estado de los servicios y debe ejecutarse únicamente en un entorno preparado para ello.

## 7. Pruebas automatizadas

Se utiliza **JUnit 5** para comprobar el comportamiento del backend.

Entre las pruebas incorporadas se encuentran casos relacionados con el modelo de ventas y el cálculo de totales.

### Ejecutar las pruebas

Desde `demo/`:

```bash
mvn clean verify
```

La ejecución de referencia realizada durante el desarrollo obtuvo **34 pruebas aprobadas**.

Esta cifra corresponde a una ejecución concreta y puede cambiar a medida que se incorporan nuevas pruebas.

## 8. Cobertura de código con JaCoCo

JaCoCo permite medir qué partes del código son ejercitadas por las pruebas automatizadas.

Durante `mvn clean verify` se genera un informe que puede consultarse en:

```text
demo/target/site/jacoco/index.html
```

En el pipeline se conserva el reporte como artifact de GitHub Actions.

La cobertura permite detectar áreas que requieren nuevas pruebas, aunque una cobertura elevada no garantiza por sí sola la ausencia de defectos.

## 9. Calidad de código con SonarCloud

El workflow principal realiza un análisis estático utilizando SonarCloud.

Se revisan aspectos relacionados con:

- Calidad del código.
- Mantenibilidad.
- Posibles defectos.
- Riesgos de seguridad.
- Cobertura de pruebas.

El análisis utiliza el reporte XML generado por JaCoCo.

El pipeline espera el resultado del Quality Gate mediante `sonar.qualitygate.wait=true`.

**Si SonarCloud rechaza el Quality Gate, el workflow de CI falla y el despliegue automatizado queda bloqueado.**

El resultado de aprobación debe comprobarse en cada ejecución de GitHub Actions.

## 10. Seguridad con Snyk

Snyk se incorpora en dos etapas del workflow principal:

### Análisis de dependencias

Examina las dependencias Maven declaradas por el proyecto para detectar vulnerabilidades conocidas.

### Análisis de imagen Docker

Examina la imagen generada y sus componentes para identificar vulnerabilidades de seguridad.

Ambos análisis utilizan un umbral de severidad `high`.

Los comandos de Snyk forman parte del CI y no están configurados para ignorar errores mediante `continue-on-error`.

Por lo tanto, los hallazgos que provoquen un código de salida de error detienen el pipeline y evitan el despliegue dependiente.

## 11. Actualización de dependencias con Dependabot

El archivo `.github/dependabot.yml` configura revisiones semanales, los días lunes, para:

- Dependencias Maven dentro de `/demo`.
- Imágenes y referencias de Docker.
- Acciones utilizadas en GitHub Actions.

Dependabot puede abrir Pull Requests con propuestas de actualización.

Las actualizaciones deben revisarse y pasar las verificaciones del CI antes de integrarse.

## 12. Integración continua y despliegue continuo

La automatización se implementa mediante GitHub Actions.

### `main.yml` — Integración continua principal

Nombre del workflow:

**CI — Tests, Calidad y Seguridad**

Se activa mediante:

- Push a `main`.
- Pull Request hacia `main`.
- Ejecución manual.

Sus etapas principales son:

1. Checkout del repositorio.
2. Configuración de Java 21.
3. Configuración de Node.js para Snyk.
4. Ejecución de pruebas JUnit mediante Maven.
5. Generación y publicación del reporte JaCoCo.
6. Análisis de calidad con SonarCloud.
7. Análisis de dependencias mediante Snyk.
8. Construcción de la imagen Docker.
9. Análisis de la imagen Docker con Snyk.
10. Inspección de la imagen generada.

### `ci.yml` — Workflow complementario

Existe también un workflow complementario de integración continua que se ejecuta en las condiciones definidas en su propio archivo, incluyendo pushes a `develop` y Pull Requests hacia `main`.

Su configuración debe mantenerse alineada con la versión de Java utilizada por el proyecto.

### `deploy.yml` — Pipeline de despliegue

El workflow de despliegue utiliza el evento `workflow_run`.

Esto permite ejecutar la cadena de construcción y despliegue después de la finalización del workflow principal de CI.

La etapa inicial verifica que:

- El CI haya concluido exitosamente.
- El evento original sea un push.
- La rama de origen sea `main`.

El proceso utiliza `github.event.workflow_run.head_sha` para construir exactamente el commit que superó las verificaciones.

El flujo previsto es:

```text
Push a main
     |
     v
CI - Tests, Calidad y Seguridad
     |
     +---- Fallo ----> Despliegue bloqueado
     |
     v
CI aprobado
     |
     v
Build de imagen Docker
     |
     v
Push a Amazon ECR o simulación
     |
     v
Despliegue con Docker Compose o simulación
```

### Modo demostración (`DEMO_MODE`)

La variable de GitHub Actions `DEMO_MODE` permite distinguir un pipeline demostrativo de uno con integración AWS.

Cuando su valor es `true`:

- Se construye la imagen Docker.
- Se omite la publicación real en Amazon ECR.
- Se omite el despliegue real.
- Se generan mensajes de simulación en el workflow.

Por lo tanto, una ejecución exitosa en modo demostración **no constituye evidencia de un despliegue real en EC2**.

### Integración con AWS

El workflow conserva pasos para autenticar con AWS, publicar imágenes en Amazon ECR y ejecutar Docker Compose.

Sin embargo, el trabajo de despliegue utiliza actualmente `ubuntu-latest`.

Para desplegar efectivamente dentro de una instancia EC2 se necesita incorporar un mecanismo remoto, como un runner self-hosted instalado en EC2, SSH o AWS Systems Manager.

La configuración actual no debe presentarse como despliegue real en EC2 hasta implementar y validar ese mecanismo.

## 13. Seguridad, estabilidad y escalabilidad

Se han incorporado distintas prácticas de calidad operacional:

- Verificación de estado de PostgreSQL mediante `pg_isready`.
- Verificación del backend mediante Spring Boot Actuator.
- Dependencia del backend respecto del estado saludable de la base de datos.
- Límites de memoria para reducir el consumo descontrolado.
- Variables de entorno para separar configuración y código.
- Escaneos de seguridad automatizados.
- Persistencia de los datos en un volumen Docker.
- Bloqueo del despliegue cuando no se aprueba el CI.

Estas medidas mejoran la estabilidad de la aplicación, pero no implementan escalado horizontal automático.

Para soportar múltiples réplicas en producción habría que revisar las restricciones de `container_name`, puertos fijos, gestión de sesiones y configuración de base de datos, además de incorporar un balanceador u orquestador apropiado.

### Limitaciones de seguridad conocidas

La configuración actual de `SecurityConfig.java` utiliza:

```java
.anyRequest().permitAll()
```

Por ello, las rutas no cuentan con una política de autorización restrictiva implementada en esa cadena de seguridad.

Además, `application.properties` incluye valores predeterminados de usuario y contraseña de Spring Security.

Antes de publicar la aplicación en producción deben revisarse la autenticación, autorización, protección de endpoints, manejo seguro de credenciales y configuración de CORS.

## 14. Trazabilidad y evidencias

GitHub y GitHub Actions permiten relacionar cambios de código con las ejecuciones automáticas.

Para respaldar la evaluación DevOps se recomienda conservar:

- Historial de commits y Pull Requests.
- Ejecuciones exitosas y fallidas de GitHub Actions.
- Resultados de pruebas JUnit.
- Reportes JaCoCo.
- Estado del Quality Gate de SonarCloud.
- Resultados de Snyk.
- Archivo de configuración de Dependabot.
- Evidencia de construcción de la imagen Docker.
- Validación del archivo Docker Compose.
- Resultados del despliegue simulado o real, claramente diferenciados.

No deben presentarse como realizadas verificaciones para las cuales todavía no existen registros de ejecución.

## 15. Control de versiones y GitFlow

El proyecto contempla una estrategia GitFlow para organizar el desarrollo y mantener trazabilidad.

### Ramas

| Rama | Propósito |
|---|---|
| `main` | Versión estable y referencia para integración principal |
| `develop` | Integración de funcionalidades en desarrollo |
| `feature/<nombre>` | Desarrollo aislado de nuevas funcionalidades |
| `hotfix/<nombre>` | Correcciones urgentes |

### Convenciones de commits

Se utiliza una convención basada en Conventional Commits:

```text
feat(catalogo): agregar filtro por talla
fix(ventas): corregir calculo de totales
test(venta): agregar pruebas de calculo
ci(actions): validar seguridad antes del deploy
docs(readme): actualizar documentacion DevOps
chore(deps): actualizar dependencias
```

### Revisión de cambios

Como política de trabajo se recomienda:

1. Crear una rama de desarrollo para cada modificación.
2. Realizar commits con mensajes descriptivos.
3. Crear Pull Requests.
4. Revisar los cambios de código.
5. Comprobar el resultado del pipeline.
6. Integrar únicamente cambios aprobados.

Esta sección describe la estrategia de colaboración propuesta; su cumplimiento efectivo debe comprobarse mediante el historial del repositorio y las reglas de protección de ramas.

## 16. Documentación adicional

El archivo `MODELS.md` contiene información sobre el modelo de datos del proyecto.

La documentación Swagger de la API se encuentra en:

```text
http://localhost:8080/doc/swagger-ui.html
```

Cuando el backend se publica mediante Docker Compose con el puerto local predeterminado, la dirección correspondiente es:

```text
http://localhost:8083/doc/swagger-ui.html
```

## 17. Uso responsable de inteligencia artificial

Durante el desarrollo se utilizaron herramientas de inteligencia artificial como apoyo para la documentación, la revisión técnica y la preparación de configuraciones DevOps.

La validación de los cambios debe realizarse mediante herramientas y evidencias verificables, como Maven, Docker, actionlint y GitHub Actions.

La responsabilidad de comprobar el comportamiento de la aplicación, revisar las recomendaciones generadas y justificar las decisiones técnicas corresponde a los integrantes del equipo.
