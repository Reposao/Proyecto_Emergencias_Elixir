defmodule Emergencias.Usuarios do
  @moduledoc """
  Registro, credenciales y permisos. La primera cuenta debe ser administradora.
  Las siguientes altas automáticas son ciudadanas; solo un administrador cambia roles.
  Las contraseñas se guardan como un resumen con sal, sin conservar la clave en texto plano.
  """

  alias Emergencias.Reglas

  @roles [:ciudadano, :voluntario, :coordinador, :administrador]

  @doc "Valida una cuenta existente o registra una nueva sin permitir elevar su rol."
  def conectar(datos, usuario, clave, nombre, rol, zona) do
    rol = Reglas.opcion(rol, @roles)

    cond do
      not Reglas.codigo?(usuario) or not Reglas.texto?(clave) ->
        {:error, :credenciales_invalidas}

      Map.has_key?(datos.usuarios, usuario) ->
        validar_existente(datos, usuario, clave)

      not Reglas.texto?(nombre) or not Reglas.codigo?(zona) or is_nil(rol) ->
        {:error, :datos_usuario_invalidos}

      map_size(datos.usuarios) == 0 and rol != :administrador ->
        {:error, :primero_cree_un_administrador}

      map_size(datos.usuarios) > 0 and rol != :ciudadano ->
        {:error, :las_altas_nuevas_son_ciudadanas}

      String.length(clave) < 4 ->
        {:error, :clave_minimo_cuatro_caracteres}

      true ->
        sal = :crypto.strong_rand_bytes(16) |> Base.encode16()

        registro = %{
          usuario: usuario,
          nombre: nombre,
          rol: rol,
          zona: zona,
          sal: sal,
          clave_hash: resumen(sal, clave)
        }

        {:ok, registro, %{datos | usuarios: Map.put(datos.usuarios, usuario, registro)}}
    end
  end

  defp validar_existente(datos, usuario, clave) do
    registro = datos.usuarios[usuario]

    if registro.clave_hash == resumen(registro.sal, clave) do
      {:ok, registro, datos}
    else
      {:error, :clave_incorrecta}
    end
  end

  defp resumen(sal, clave) do
    :crypto.hash(:sha256, sal <> clave)
    |> Base.encode16()
  end

  @doc "Cambia un rol; conserva al menos un administrador."
  def cambiar_rol(datos, usuario, rol) do
    rol = Reglas.opcion(rol, @roles)
    actual = datos.usuarios[usuario]

    administradores =
      Enum.count(datos.usuarios, fn {_, u} ->
        u.rol == :administrador
      end)

    cond do
      is_nil(actual) ->
        {:error, :usuario_no_existe}

      is_nil(rol) ->
        {:error, :rol_invalido}

      actual.rol == :administrador and rol != :administrador and administradores == 1 ->
        {:error, :debe_quedar_un_administrador}

      true ->
        nuevo = %{actual | rol: rol}

        {:ok, publico(nuevo), %{datos | usuarios: Map.put(datos.usuarios, usuario, nuevo)}}
    end
  end

  @doc "Proyección pública de la cuenta, sin sal ni resumen de contraseña."
  def publico(usuario) do
    Map.take(usuario, [:usuario, :nombre, :rol, :zona])
  end

  @doc "Indica si un rol puede realizar la acción solicitada."
  def permite?(:administrador, _), do: true

  def permite?(_, accion)
      when accion in [
             :listar_zonas,
             :arbol_zona,
             :resumen_zona,
             :listar_centros,
             :listar_recursos,
             :historial_movimientos,
             :listar_necesidades,
             :pendientes,
             :listar_personas,
             :historial_persona,
             :listar_mensajes,
             :listar_mascotas,
             :coincidencias,
             :listar_albergues,
             :consultar_albergue,
             :ocupacion,
             :resumen,
             :criticos,
             :registrar_necesidad,
             :registrar_persona,
             :enviar_mensaje,
             :registrar_mascota,
             :estado_necesidad,
             :actividades
           ],
      do: true

  def permite?(rol, accion)
      when rol in [:voluntario, :coordinador] and
             accion in [
               :estado_persona,
               :estado_mensaje,
               :ingreso,
               :salida,
               :coincidir_mascotas,
               :confirmar_mascotas,
               :estado_necesidad,
               :asignar,
               :asignar_prioritaria
             ],
      do: true

  def permite?(:coordinador, accion)
      when accion in [
             :registrar_zona,
             :registrar_centro,
             :registrar_recurso,
             :mover_recurso,
             :transferir,
             :registrar_albergue
           ],
      do: true

  def permite?(_, _), do: false
end
