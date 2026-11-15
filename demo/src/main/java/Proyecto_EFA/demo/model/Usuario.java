package Proyecto_EFA.demo.model;

import java.util.ArrayList;
import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonProperty;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@AllArgsConstructor

@Entity
// Jackson no puede construir la subclase proxy que Hibernate genera para
// esta entidad cuando otra prueba la ha cargado: "Cannot construct
// instance of Usuario (no delegate- or property-based Creator)".
// Esta anotacion hace que Jackson trate la entidad como su clase base
// e ignore los campos del proxy, en lugar de intentar construirlo.
@JsonIgnoreProperties({"hibernateLazyInitializer", "handler"})
public class Usuario {
    @JsonCreator
    public Usuario() { }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Integer id;

    @Column(name = "nombreUsuario", length = 50, nullable = false)
    private String nombre;

    @Column(name = "correoUsuario", length = 50, nullable = false)
    private String correo;

    @Column(name = "contrasenaUsuario", length = 100, nullable = false)
    @JsonProperty(access = JsonProperty.Access.WRITE_ONLY)
    private String contrasena;

    @ManyToOne
    @JoinColumn(name = "rol_id")
    @JsonIgnoreProperties("usuarios")
    private Rol rol;

    @ManyToOne
    @JoinColumn(name = "direccion_id")
    @JsonIgnoreProperties("usuarios")
    private Direccion direccion;

    @OneToMany(mappedBy = "usuario")
    @JsonIgnore
    private List<Venta> ventas = new ArrayList<>();
}