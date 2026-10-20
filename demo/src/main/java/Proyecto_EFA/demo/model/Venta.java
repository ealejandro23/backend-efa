
package Proyecto_EFA.demo.model;

import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Data
@AllArgsConstructor
@NoArgsConstructor
public class Venta {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String numeroVenta;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "usuario_id", nullable = false)
    @JsonIgnoreProperties({
        "ventas",
        "hibernateLazyInitializer",
        "handler"
    })
    private Usuario usuario;

    @ManyToOne
    @JoinColumn(name = "estado_id")
    @JsonIgnoreProperties("ventas")
    private Estado estado;

    @ManyToOne
    @JoinColumn(name = "metodo_pago_id")
    @JsonIgnoreProperties("ventas")
    private MetodoPago metodoPago;

    @ManyToOne
    @JoinColumn(name = "metodo_envio_id")
    @JsonIgnoreProperties("ventas")
    private MetodoEnvio metodoEnvio;

    @Column(nullable = false)
    private Double total;

    @OneToMany(
        mappedBy = "venta",
        cascade = CascadeType.ALL,
        orphanRemoval = true
    )
    @JsonIgnore
    private List<ProductoVenta> items = new ArrayList<>();

    @PrePersist
    @PreUpdate
    public void calcularTotal() {

        // Evitar NullPointerException cuando la lista no existe
        if (items == null || items.isEmpty()) {
            this.total = 0.0;
            return;
        }

        // Calcular el total de los productos existentes
        this.total = items.stream()
            .filter(item -> item != null)
            .mapToDouble(item ->
                item.getSubtotal() != null
                    ? item.getSubtotal()
                    : 0.0
            )
            .sum();
    }
}
