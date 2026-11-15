package Proyecto_EFA.demo.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import Proyecto_EFA.demo.model.Categorias;

public interface CategoriasRepository extends JpaRepository<Categorias, Integer> {
    
	@Query("SELECT c FROM Categorias c WHERE c.nombre = :nombre")
	Optional<Categorias> findByNombre(@Param("nombre") String nombre);
	// Variante tolerante a duplicados: devuelve el primer resultado en lugar de
	// fallar. Necesaria cuando varias replicas del servicio inicializan los
	// datos basicos a la vez (ver DataLoader).
	@Query("SELECT c FROM Categorias c WHERE c.nombre = :nombre ORDER BY c.id ASC")
	Optional<Categorias> findFirstByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT c FROM Categorias c WHERE LOWER(c.nombre) LIKE LOWER(CONCAT('%', :nombre, '%'))")
	List<Categorias> searchByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT c FROM Categorias c ORDER BY c.nombre ASC")
	List<Categorias> findAllOrderedByName();

}
