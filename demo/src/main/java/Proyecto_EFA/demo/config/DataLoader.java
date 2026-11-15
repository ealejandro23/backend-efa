package Proyecto_EFA.demo.config;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.CommandLineRunner;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import Proyecto_EFA.demo.model.*;
import Proyecto_EFA.demo.repository.*;

/**
 * Carga de los datos basicos del catalogo.
 *
 * <p>El cargador se ejecuta en cada arranque del servicio. En un entorno con
 * varias replicas (por ejemplo, un Deployment de Kubernetes con tres pods),
 * todas arrancan a la vez y pueden insertar la misma categoria, marca, talla,
 * color o material de forma simultanea.
 *
 * <p>Para que eso no provoque un fallo de arranque, la inicializacion es
 * idempotente y tolerante a la concurrencia:
 *
 * <ul>
 *   <li>La busqueda usa {@code findFirstByNombre}, que devuelve el primer
 *       resultado en lugar de fallar cuando ya existen duplicados.</li>
 *   <li>La insercion captura la violacion de integridad y vuelve a leer el
 *       registro que otra replica acaba de crear.</li>
 * </ul>
 *
 * <p>Sin estas medidas, el tercer pod que arrancaba fallaba con
 * {@code NonUniqueResultException: Query did not return a unique result}.
 */
@Component
public class DataLoader implements CommandLineRunner {

    @Autowired
    private ProductoRepository productoRepository;

    @Autowired
    private CategoriasRepository categoriasRepository;

    @Autowired
    private MarcaRepository marcaRepository;

    @Autowired
    private TallasRepository tallasRepository;

    @Autowired
    private ColoresRepository coloresRepository;

    @Autowired
    private MaterialesRepository materialesRepository;

    @Override
    public void run(String... args) throws Exception {
        crearDatosBasicos();
        crearProductos();
    }

    private void crearDatosBasicos() {
        crearCategoria("hombre");
        crearCategoria("mujer");
        crearCategoria("infantil");
        crearMarca("EFA");
        crearTalla("Única");
        crearColor("Variado");
        crearMaterial("Algodón");
    }

    /**
     * Obtiene la categoria por nombre o la crea si no existe.
     *
     * @param nombre nombre de la categoria
     * @return la categoria existente o la recien creada
     */
    private Categorias crearCategoria(String nombre) {
        return categoriasRepository.findFirstByNombre(nombre).orElseGet(() -> {
            Categorias categoria = new Categorias();
            categoria.setNombre(nombre);
            return guardarSiNoExiste(categoriasRepository.findFirstByNombre(nombre),
                    categoria, categoriasRepository::save);
        });
    }

    /**
     * Obtiene la marca por nombre o la crea si no existe.
     *
     * @param nombre nombre de la marca
     * @return la marca existente o la recien creada
     */
    private Marca crearMarca(String nombre) {
        return marcaRepository.findFirstByNombre(nombre).orElseGet(() -> {
            Marca marca = new Marca();
            marca.setNombre(nombre);
            return guardarSiNoExiste(marcaRepository.findFirstByNombre(nombre),
                    marca, marcaRepository::save);
        });
    }

    /**
     * Obtiene la talla por nombre o la crea si no existe.
     *
     * @param nombre nombre de la talla
     * @return la talla existente o la recien creada
     */
    private Tallas crearTalla(String nombre) {
        return tallasRepository.findFirstByNombre(nombre).orElseGet(() -> {
            Tallas talla = new Tallas();
            talla.setNombre(nombre);
            return guardarSiNoExiste(tallasRepository.findFirstByNombre(nombre),
                    talla, tallasRepository::save);
        });
    }

    /**
     * Obtiene el color por nombre o lo crea si no existe.
     *
     * @param nombre nombre del color
     * @return el color existente o el recien creado
     */
    private Colores crearColor(String nombre) {
        return coloresRepository.findFirstByNombre(nombre).orElseGet(() -> {
            Colores color = new Colores();
            color.setNombre(nombre);
            return guardarSiNoExiste(coloresRepository.findFirstByNombre(nombre),
                    color, coloresRepository::save);
        });
    }

    /**
     * Obtiene el material por nombre o lo crea si no existe.
     *
     * @param nombre nombre del material
     * @return el material existente o el recien creado
     */
    private Materiales crearMaterial(String nombre) {
        return materialesRepository.findFirstByNombre(nombre).orElseGet(() -> {
            Materiales material = new Materiales();
            material.setNombre(nombre);
            return guardarSiNoExiste(materialesRepository.findFirstByNombre(nombre),
                    material, materialesRepository::save);
        });
    }

    /**
     * Guarda la entidad tolerando la condicion de carrera entre replicas.
     *
     * <p>Si otra replica inserto el mismo registro entre la consulta y el
     * guardado, la base de datos rechaza la insercion. En ese caso se
     * devuelve el registro que ya existe en lugar de propagar el error.
     *
     * @param relectura funcion que vuelve a leer la entidad por nombre
     * @param entidad   entidad a guardar
     * @param guardar   funcion de guardado
     * @param <T>       tipo de la entidad
     * @return la entidad guardada o la que ya existia
     */
    private <T> T guardarSiNoExiste(
            java.util.Optional<T> relectura,
            T entidad,
            java.util.function.Function<T, T> guardar) {

        try {
            return guardar.apply(entidad);
        } catch (DataIntegrityViolationException e) {
            // Otra replica inserto el mismo registro entre la lectura y la
            // escritura: se devuelve el registro existente.
            return relectura.orElseThrow(() -> e);
        }
    }

    private void crearProductos() {
        Categorias hombre = categoriasRepository.findFirstByNombre("hombre")
                .orElseThrow(() -> new RuntimeException("Categoría hombre no encontrada"));
        Categorias mujer = categoriasRepository.findFirstByNombre("mujer")
                .orElseThrow(() -> new RuntimeException("Categoría mujer no encontrada"));
        Categorias infantil = categoriasRepository.findFirstByNombre("infantil")
                .orElseThrow(() -> new RuntimeException("Categoría infantil no encontrada"));

        Marca marca = marcaRepository.findFirstByNombre("EFA")
                .orElseThrow(() -> new RuntimeException("Marca EFA no encontrada"));

        Tallas talla = tallasRepository.findFirstByNombre("Única")
                .orElseThrow(() -> new RuntimeException("Talla no encontrada"));

        Colores color = coloresRepository.findFirstByNombre("Variado")
                .orElseThrow(() -> new RuntimeException("Color no encontrada"));

        Materiales material = materialesRepository.findFirstByNombre("Algodón")
                .orElseThrow(() -> new RuntimeException("Material no encontrado"));

        // --- Ropa Hombre ---
        crearProducto("Polera básica blanca", "Polera básica de algodón 100%", 6990.0, 15, "POL-BLAN-001", hombre, marca, talla, color, material, "/img/5.webp");
        crearProducto("Polera oversize negra", "Polera oversize con corte moderno", 12990.0, 10, "POL-NEG-002", hombre, marca, talla, color, material, "/img/6.webp");
        crearProducto("Jeans Baggy Negro", "Jeans baggy de tendencia urbana", 10990.0, 8, "JEANS-BAG-003", hombre, marca, talla, color, material, "/img/baggy.webp");
        crearProducto("Jogger Morado", "Jogger deportivo color morado", 9990.0, 12, "JOG-MOR-004", hombre, marca, talla, color, material, "/img/morado.webp");
        crearProducto("Chaqueta jean clásica", "Chaqueta de jean clásica y versátil", 19990.0, 6, "CHAQ-JEAN-005", hombre, marca, talla, color, material, "/img/chaquetah.webp");
        crearProducto("Short AND1", "Short deportivo marca AND1", 15990.0, 20, "SHORT-AND1-006", hombre, marca, talla, color, material, "/img/and1.webp");
        crearProducto("Short AND1 Premium", "Short deportivo modelo premium AND1", 17990.0, 15, "SHORT-AND1-007", hombre, marca, talla, color, material, "/img/and.webp");

        // --- Ropa Mujer ---
        crearProducto("Polera deportiva Azul", "Polera deportiva color azul para mujer", 8990.0, 18, "POL-AZU-008", mujer, marca, talla, color, material, "/img/mujer3.webp");
        crearProducto("Polera oversize Roja", "Polera oversize roja de estilo urbano", 12990.0, 9, "POL-ROJ-009", mujer, marca, talla, color, material, "/img/mujer1.webp");
        crearProducto("Polera deportiva sin mangas", "Polera deportiva sin mangas para entrenamiento", 6990.0, 14, "POL-SIN-010", mujer, marca, talla, color, material, "/img/mujer2.webp");
        crearProducto("Pantalón cargo beige", "Pantalón cargo beige con múltiples bolsillos", 14990.0, 7, "PAN-CAR-011", mujer, marca, talla, color, material, "/img/pan1.webp");
        crearProducto("Pantalón skinny negro", "Pantalón skinny negro ajustado", 13990.0, 11, "PAN-SKI-012", mujer, marca, talla, color, material, "/img/pan2.webp");
        crearProducto("Chaqueta jean clásica", "Chaqueta de jean clásica para mujer", 19990.0, 8, "CHAQ-JEAN-013", mujer, marca, talla, color, material, "/img/chaqueta.webp");
        crearProducto("Chaqueta negra", "Chaqueta negra elegante para mujer", 15990.0, 10, "CHAQ-NEG-014", mujer, marca, talla, color, material, "/img/44.webp");
        crearProducto("Chaqueta deportiva", "Chaqueta deportiva para actividades al aire libre", 17990.0, 12, "CHAQ-DEP-015", mujer, marca, talla, color, material, "/img/mujer_chaqueta2.webp");

        // --- Ropa Infantil ---
        crearProducto("Polera infantil estampada", "Polera infantil con divertidos estampados", 7990.0, 25, "POL-INF-016", infantil, marca, talla, color, material, "/img/IN.webp");
        crearProducto("Polera con dibujos", "Polera infantil con coloridos dibujos", 8490.0, 20, "POL-DIB-017", infantil, marca, talla, color, material, "/img/infantil1.webp");
        crearProducto("Pantalón jeans infantil", "Pantalón jeans resistente para niños", 12990.0, 15, "PAN-JEI-018", infantil, marca, talla, color, material, "/img/infantil3.webp");
        crearProducto("Chaqueta infantil", "Chaqueta infantil abrigadora", 15990.0, 8, "CHAQ-INF-019", infantil, marca, talla, color, material, "/img/infantil4.webp");
        crearProducto("Chaqueta con capucha", "Chaqueta infantil con capucha incorporada", 17990.0, 10, "CHAQ-CAP-020", infantil, marca, talla, color, material, "/img/parka.webp");
    }

    private void crearProducto(String nombre, String descripcion, Double precio, Integer stock,
                              String codigo, Categorias categoria, Marca marca, Tallas talla,
                              Colores color, Materiales material, String imagenUrl) {
        Producto producto = new Producto();
        producto.setNombre(nombre);
        producto.setDescripcion(descripcion);
        producto.setPrecio(precio);
        producto.setStock(stock);
        producto.setCodigo(codigo);
        producto.setCategorias(categoria);
        producto.setMarca(marca);
        producto.setTallas(talla);
        producto.setColores(color);
        producto.setMateriales(material);
        producto.setImagenUrl(imagenUrl);

        // La comprobacion se hace sobre el codigo, que es unico por producto.
        // Dos replicas pueden insertar el mismo producto simultaneamente; en
        // ese caso la violacion de integridad se ignora, porque el producto
        // ya existe y es equivalente.
        if (productoRepository.findByCodigo(codigo).isEmpty()) {
            try {
                productoRepository.save(producto);
            } catch (DataIntegrityViolationException e) {
                // Otra replica inserto el mismo codigo: no hay nada que hacer.
            }
        }
    }
}
