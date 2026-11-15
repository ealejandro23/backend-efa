package Proyecto_EFA.demo.repository;

import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;

import Proyecto_EFA.demo.model.Materiales;

public interface MaterialesRepository extends JpaRepository<Materiales, Integer> {
	Optional<Materiales> findByNombre(String nombre);

	// Variante tolerante a duplicados: devuelve el primer resultado en lugar de
	// fallar. Necesaria cuando varias replicas del servicio inicializan los
	// datos basicos a la vez (ver DataLoader).
	Optional<Materiales> findFirstByNombre(String nombre);
}
