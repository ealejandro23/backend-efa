package Proyecto_EFA.demo.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import Proyecto_EFA.demo.model.Colores;

public interface ColoresRepository extends JpaRepository<Colores, Integer> {
    
	@Query("SELECT c FROM Colores c WHERE c.nombre = :nombre")
	Optional<Colores> findByNombre(@Param("nombre") String nombre);
	// Variante tolerante a duplicados: devuelve el primer resultado en lugar de
	// fallar. Necesaria cuando varias replicas del servicio inicializan los
	// datos basicos a la vez (ver DataLoader).
	@Query("SELECT c FROM Colores c WHERE c.nombre = :nombre ORDER BY c.id ASC")
	Optional<Colores> findFirstByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT c FROM Colores c WHERE LOWER(c.nombre) LIKE LOWER(CONCAT('%', :nombre, '%'))")
	List<Colores> searchByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT c FROM Colores c ORDER BY c.nombre ASC")
	List<Colores> findAllOrderedByName();

}
