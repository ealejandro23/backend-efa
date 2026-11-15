package Proyecto_EFA.demo.repository;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import Proyecto_EFA.demo.model.Marca;

public interface MarcaRepository extends JpaRepository<Marca, Integer> {
	
	@Query("SELECT m FROM Marca m WHERE m.nombre = :nombre")
	Optional<Marca> findByNombre(@Param("nombre") String nombre);
	// Variante tolerante a duplicados: devuelve el primer resultado en lugar de
	// fallar. Necesaria cuando varias replicas del servicio inicializan los
	// datos basicos a la vez (ver DataLoader).
	@Query("SELECT m FROM Marca m WHERE m.nombre = :nombre ORDER BY m.id ASC")
	Optional<Marca> findFirstByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT m FROM Marca m WHERE LOWER(m.nombre) LIKE LOWER(CONCAT('%', :nombre, '%'))")
	List<Marca> searchByNombre(@Param("nombre") String nombre);
	
	@Query("SELECT m FROM Marca m ORDER BY m.nombre ASC")
	List<Marca> findAllOrderedByName();

}
