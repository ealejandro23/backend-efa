package Proyecto_EFA.demo.service;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import jakarta.transaction.Transactional;
import Proyecto_EFA.demo.model.Venta;
import Proyecto_EFA.demo.repository.VentaRepository;

@Service
@Transactional
public class VentaService {

    @Autowired
    private VentaRepository ventaRepository;

    // CRUD básico
    public List<Venta> getAllVentas() {
        return ventaRepository.findAll();
    }

    public Venta getVentaById(Long id) {
        return ventaRepository.findById(id).orElse(null);
    }

    public Venta createVenta(Venta venta) {
        return ventaRepository.save(venta);
    }

    public Venta updateVenta(Long id, Venta ventaDetails) {
        Venta venta = ventaRepository.findById(id).orElse(null);
        if (venta != null) {
            if (ventaDetails.getNumeroVenta() != null) {
                venta.setNumeroVenta(ventaDetails.getNumeroVenta());
            }
            if (ventaDetails.getUsuario() != null) {
                venta.setUsuario(ventaDetails.getUsuario());
            }
            if (ventaDetails.getEstado() != null) {
                venta.setEstado(ventaDetails.getEstado());
            }
            if (ventaDetails.getMetodoPago() != null) {
                venta.setMetodoPago(ventaDetails.getMetodoPago());
            }
            if (ventaDetails.getMetodoEnvio() != null) {
                venta.setMetodoEnvio(ventaDetails.getMetodoEnvio());
            }
            // items tiene orphanRemoval y es @JsonIgnore: nunca viene en el JSON y
            // reemplazar la colección rompía Hibernate ("collection with orphan deletion
            // was no longer referenced") en todo PUT/PATCH. Los ítems se gestionan
            // desde /api/v1/producto-ventas.
            return ventaRepository.save(venta);
        }
        return null;
    }

    public void deleteVenta(Long id) {
        ventaRepository.deleteById(id);
    }
    
    // Métodos de búsqueda avanzados
    public List<Venta> getVentasByUsuario(Integer usuarioId) {
        return ventaRepository.findByUsuarioId(usuarioId);
    }
    
    public List<Venta> getVentasByEstado(Integer estadoId) {
        return ventaRepository.findByEstadoId(estadoId);
    }
    
    public List<Venta> getVentasByMetodoPago(Integer metodoPagoId) {
        return ventaRepository.findByMetodoPagoId(metodoPagoId);
    }
    
    public List<Venta> getVentasByMetodoEnvio(Integer metodoEnvioId) {
        return ventaRepository.findByMetodoEnvioId(metodoEnvioId);
    }
    
    public Venta getVentaByNumeroVenta(String numeroVenta) {
        return ventaRepository.findByNumeroVenta(numeroVenta);
    }
    
    public List<Venta> getPendingVentas() {
        return ventaRepository.findPendingVentas();
    }
    
    public List<Venta> getDeliveredVentas() {
        return ventaRepository.findDeliveredVentas();
    }
    
    public int countVentasByUsuario(Integer usuarioId) {
        return ventaRepository.countVentasByUsuario(usuarioId);
    }
    
    public List<Venta> getVentasByUsuarioAndEstado(Integer usuarioId, Integer estadoId) {
        return ventaRepository.findByUsuarioIdAndEstadoId(usuarioId, estadoId);
    }

}
