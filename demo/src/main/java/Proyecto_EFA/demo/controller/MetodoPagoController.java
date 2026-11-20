package Proyecto_EFA.demo.controller;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import Proyecto_EFA.demo.model.MetodoPago;
import Proyecto_EFA.demo.service.MetodoPagoService;

@RestController
@RequestMapping("/api/v1/metodos-pago")
public class MetodoPagoController {

    @Autowired
    private MetodoPagoService metodoPagoService;

    @GetMapping
    public ResponseEntity<List<MetodoPago>> getAllMetodosPago() {
        return ResponseEntity.ok(metodoPagoService.getAllMetodosPago());
    }

    @GetMapping("/{id}")
    public ResponseEntity<MetodoPago> getMetodoPagoById(@PathVariable Integer id) {
        MetodoPago metodoPago = metodoPagoService.getMetodoPagoById(id);
        return metodoPago != null ? ResponseEntity.ok(metodoPago) : ResponseEntity.notFound().build();
    }

    @GetMapping("/nombre/{nombre}")
    public ResponseEntity<MetodoPago> getMetodoPagoByNombre(@PathVariable String nombre) {
        MetodoPago metodoPago = metodoPagoService.getMetodoPagoByNombre(nombre);
        return metodoPago != null ? ResponseEntity.ok(metodoPago) : ResponseEntity.notFound().build();
    }

    @PostMapping
    public ResponseEntity<?> createMetodoPago(@RequestBody MetodoPago metodoPago) {
        try {
            MetodoPago created = metodoPagoService.createMetodoPago(metodoPago);
            return ResponseEntity.status(201).body(created);
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PutMapping("/{id}")
    public ResponseEntity<?> updateMetodoPago(@PathVariable Integer id, @RequestBody MetodoPago metodoPagoDetails) {
        try {
            MetodoPago updated = metodoPagoService.updateMetodoPago(id, metodoPagoDetails);
            return updated != null ? ResponseEntity.ok(updated) : ResponseEntity.notFound().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @PatchMapping("/{id}")
    public ResponseEntity<?> partialUpdateMetodoPago(@PathVariable Integer id, @RequestBody MetodoPago metodoPagoDetails) {
        try {
            MetodoPago updated = metodoPagoService.partialUpdateMetodoPago(id, metodoPagoDetails);
            return updated != null ? ResponseEntity.ok(updated) : ResponseEntity.notFound().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<?> deleteMetodoPago(@PathVariable Integer id) {
        try {
            metodoPagoService.deleteMetodoPago(id);
            return ResponseEntity.noContent().build();
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(e.getMessage());
        }
    }
}
