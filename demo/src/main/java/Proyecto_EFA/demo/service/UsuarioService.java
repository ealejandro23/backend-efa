package Proyecto_EFA.demo.service;

import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import jakarta.transaction.Transactional;
import Proyecto_EFA.demo.model.Usuario;
import Proyecto_EFA.demo.repository.UsuarioRepository;

@Service
@Transactional
@SuppressWarnings("null")
public class UsuarioService {
    
    @Autowired
    private UsuarioRepository usuarioRepository;
    @Autowired
    private PasswordEncoder passwordEncoder;

    // NOTA: nunca se anula la contraseña en estos métodos de lectura. La columna
    // contrasenaUsuario es NOT NULL y, al hacerlo dentro de la transacción, Hibernate
    // intentaba persistir NULL y respondía 500. Además, el campo ya está marcado con
    // @JsonProperty(WRITE_ONLY) en el modelo, por lo que jamás se serializa en las
    // respuestas JSON (la protección se mantiene sin tocar la base de datos).

    // CRUD básico
    public List<Usuario> getAllUsers() {
        return usuarioRepository.findAll();
    }

    public Usuario findById(Integer id) {
        return usuarioRepository.findById(id).orElse(null);
    }      

    public Usuario login(String nombreUsuario, String contrasena) {
        Usuario usuario = usuarioRepository.findByNombre(nombreUsuario);
        if (usuario == null) {
            usuario = usuarioRepository.findByCorreo(nombreUsuario);
        }
        if (usuario != null && passwordEncoder.matches(contrasena, usuario.getContrasena())) {
            return usuario;
        }
        return null;
    }

    public List<Usuario> searchByNombre(String nombre) {
        return usuarioRepository.findByNombreContainingIgnoreCase(nombre);
    }

    public Usuario updateUsuario(Usuario usuario) {
        // Sustitución completa (PUT). La columna contrasenaUsuario es NOT NULL, por lo
        // que si el cuerpo no trae contraseña debemos conservar la guardada (antes el
        // PUT respondía 500). Si el id no existe, devolvemos null para que el
        // controlador responda 404 (rama que ya existía).
        if (usuario.getId() == null) {
            return save(usuario);
        }
        Usuario existente = usuarioRepository.findById(usuario.getId()).orElse(null);
        if (existente == null) {
            return null;
        }
        if (usuario.getContrasena() == null) {
            usuario.setContrasena(existente.getContrasena());
        }
        return save(usuario);
    }

    public Usuario save(Usuario usuario) {
        if (usuario.getContrasena() != null) {
            String encodedPassword = passwordEncoder.encode(usuario.getContrasena());
            usuario.setContrasena(encodedPassword);
        }
        return usuarioRepository.save(usuario);
    }

    public Usuario partialUpdateUsuario(Integer id, Usuario usuarioDetails) {
        Usuario usuario = usuarioRepository.findById(id).orElse(null);
        if (usuario != null) {
            if (usuarioDetails.getNombre() != null) {
                usuario.setNombre(usuarioDetails.getNombre());
            }
            if (usuarioDetails.getCorreo() != null) {
                usuario.setCorreo(usuarioDetails.getCorreo());
            }
            if (usuarioDetails.getContrasena() != null) {
                String encodedPassword = passwordEncoder.encode(usuarioDetails.getContrasena());
                usuario.setContrasena(encodedPassword);
            }
            if (usuarioDetails.getRol() != null) {
                usuario.setRol(usuarioDetails.getRol());
            }
            if (usuarioDetails.getDireccion() != null) {
                usuario.setDireccion(usuarioDetails.getDireccion());
            }
            return usuarioRepository.save(usuario);
        }
        return null;
    }

    public void deleteUsuario(Integer id) {
        usuarioRepository.deleteById(id);
    }
    
    // Métodos de búsqueda avanzados
    public List<Usuario> getUsuariosByRol(Integer rolId) {
        return usuarioRepository.findByRolId(rolId);
    }
    
    public List<Usuario> getUsuariosByComuna(Integer comunaId) {
        return usuarioRepository.findByComunaId(comunaId);
    }
    
    public List<Usuario> getUsuariosByRegion(Integer regionId) {
        return usuarioRepository.findByRegionId(regionId);
    }
    
    public List<Usuario> getAllAdmins() {
        return usuarioRepository.findAllAdmins();
    }
    
    public List<Usuario> getAllCustomers() {
        return usuarioRepository.findAllCustomers();
    }
    
    public int countByRol(Integer rolId) {
        return usuarioRepository.countByRol(rolId);
    }

    public Usuario getUsuarioById(Integer id) {
        return usuarioRepository.findById(id).orElse(null);
    }
}
