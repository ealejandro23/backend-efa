package Proyecto_EFA.demo.service;

import java.util.List;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import jakarta.transaction.Transactional;
import Proyecto_EFA.demo.model.Producto;
import Proyecto_EFA.demo.repository.ProductoRepository;

@Service
@Transactional
public class ProductoService {

    @Autowired
    private ProductoRepository productoRepository;

    public List<Producto> getAllProductos() {
        return productoRepository.findAll();
    }

    public Producto getProductoById(Integer id) {
        return productoRepository.findById(id).orElse(null);
    }

    public Producto createProducto(Producto producto) {
        return productoRepository.save(producto);
    }

    public Producto updateProducto(Integer id, Producto productoDetails) {
        Optional<Producto> productoOpt = productoRepository.findById(id);
        if (productoOpt.isPresent()) {
            Producto producto = productoOpt.get();
            
            if (productoDetails.getNombre() != null) {
                producto.setNombre(productoDetails.getNombre());
            }
            if (productoDetails.getDescripcion() != null) {
                producto.setDescripcion(productoDetails.getDescripcion());
            }
            if (productoDetails.getPrecio() != null) {
                producto.setPrecio(productoDetails.getPrecio());
            }
            if (productoDetails.getStock() != null) {
                producto.setStock(productoDetails.getStock());
            }
            if (productoDetails.getMarca() != null) {
                producto.setMarca(productoDetails.getMarca());
            }
            if (productoDetails.getCategorias() != null) {
                producto.setCategorias(productoDetails.getCategorias());
            }
            if (productoDetails.getColores() != null) {
                producto.setColores(productoDetails.getColores());
            }
            if (productoDetails.getMateriales() != null) {
                producto.setMateriales(productoDetails.getMateriales());
            }
            if (productoDetails.getTallas() != null) {
                producto.setTallas(productoDetails.getTallas());
            }
            // imagenes tiene orphanRemoval y es @JsonIgnore: nunca viene en el JSON y
            // reemplazar la colección rompía Hibernate ("collection with orphan deletion
            // was no longer referenced") en todo PUT/PATCH. Se gestiona desde ImagenService.
            if (productoDetails.getImagenUrl() != null) {
                producto.setImagenUrl(productoDetails.getImagenUrl());
            }
            if (productoDetails.getCodigo() != null) {
                producto.setCodigo(productoDetails.getCodigo());
            }
            return productoRepository.save(producto);
        }
        return null;
    }

    public void deleteProducto(Integer id) {
        productoRepository.deleteById(id);
    }
    
    public List<Producto> getProductosByMarca(Integer marcaId) {
        return productoRepository.findByMarcaId(marcaId);
    }
    
    public List<Producto> getProductosByCategoria(Integer categoriaId) {
        return productoRepository.findByCategoriaId(categoriaId);
    }
    
    public List<Producto> getProductosByPriceRange(Double precioMin, Double precioMax) {
        return productoRepository.findByPriceRange(precioMin, precioMax);
    }
    
    public List<Producto> searchProductosByNombre(String nombre) {
        return productoRepository.searchByNombre(nombre);
    }
    
    public List<Producto> getProductosByColor(Integer colorId) {
        return productoRepository.findByColorId(colorId);
    }
    
    public List<Producto> getProductosByMaterial(Integer materialId) {
        return productoRepository.findByMaterialId(materialId);
    }
    
    public List<Producto> getProductosByTalla(Integer tallaId) {
        return productoRepository.findByTallaId(tallaId);
    }
    
    public List<Producto> getProductosByMarcaAndCategoria(Integer marcaId, Integer categoriaId) {
        return productoRepository.findByMarcaIdAndCategoriaId(marcaId, categoriaId);
    }

    public List<Producto> getTop10MostExpensiveProducts() {
        return productoRepository.findTop10ByOrderByPrecioDesc();
    }
    
    public List<Producto> getTop10CheapestProducts() {
        return productoRepository.findTop10ByOrderByPrecioAsc();
    }
 
    public List<Producto> searchByNombreContaining(String nombre) {
        return productoRepository.findByNombreContainingIgnoreCase(nombre);
    }
    
    public List<Producto> getProductosConStock() {
        return productoRepository.findByStockGreaterThan(0);
    }
    
    public Optional<Producto> getProductoByCodigo(String codigo) {
        return productoRepository.findByCodigo(codigo);
    }
}