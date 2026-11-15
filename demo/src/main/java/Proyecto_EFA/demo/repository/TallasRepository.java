package Proyecto_EFA.demo.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import Proyecto_EFA.demo.model.Tallas;

public interface TallasRepository extends JpaRepository<Tallas, Integer> {

	Optional<Tallas> findByNombre(String nombre);

	// Variante tolerante a duplicados: devuelve el primer resultado en lugar de
	// fallar. Necesaria cuando varias replicas del servicio inicializan los
	// datos basicos a la vez (ver DataLoader).
	Optional<Tallas> findFirstByNombre(String nombre);
}
