package Proyecto_EFA.demo.controller;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import Proyecto_EFA.demo.model.MetodoEnvio;
import Proyecto_EFA.demo.service.MetodoEnvioService;

@RestController
@RequestMapping("/api/v1/metodos-envio")
public class MetodoEnvioController {

    @Autowired
    private MetodoEnvioService metodoEnvioService;

    @GetMapping
    public ResponseEntity<List<MetodoEnvio>> getAllMetodosEnvio() {
        return ResponseEntity.ok(metodoEnvioService.getAllMetodosEnvio());
    }

    @GetMapping("/{id}")
    public ResponseEntity<MetodoEnvio> getMetodoEnvioById(@PathVariable Integer id) {
        MetodoEnvio metodoEnvio = metodoEnvioService.getMetodoEnvioById(id);
        return metodoEnvio != null ? ResponseEntity.ok(metodoEnvio) : ResponseEntity.notFound().build();
    }

    @GetMapping("/nombre/{nombre}")
    public ResponseEntity<MetodoEnvio> getMetodoEnvioByNombre(@PathVariable String nombre) {
        MetodoEnvio metodoEnvio = metodoEnvioService.getMetodoEnvioByNombre(nombre);
        return metodoEnvio != null ? ResponseEntity.ok(metodoEnvio) : ResponseEntity.notFound().build();
    }

    @PostMapping
    public ResponseEntity<?> createMetodoEnvio(@RequestBody MetodoEnvio metodoEnvio) {
        try {
            MetodoEnvio created = metodoEnvioService.createMetodoEnvio(metodoEnvio);
            return ResponseEntity.status(201).body(created);
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> updateMetodoEnvio(@PathVariable Integer id, @RequestBody MetodoEnvio metodoEnvioDetails) {
        try {
            MetodoEnvio updated = metodoEnvioService.updateMetodoEnvio(id, metodoEnvioDetails);
            return updated != null ? ResponseEntity.ok(updated) : ResponseEntity.notFound().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PatchMapping("/{id}")
    public ResponseEntity<?> partialUpdateMetodoEnvio(@PathVariable Integer id, @RequestBody MetodoEnvio metodoEnvioDetails) {
        try {
            MetodoEnvio updated = metodoEnvioService.partialUpdateMetodoEnvio(id, metodoEnvioDetails);
            return updated != null ? ResponseEntity.ok(updated) : ResponseEntity.notFound().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteMetodoEnvio(@PathVariable Integer id) {
        try {
            metodoEnvioService.deleteMetodoEnvio(id);
            return ResponseEntity.noContent().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
