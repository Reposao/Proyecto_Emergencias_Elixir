defmodule Emergencias.Dominio do
  @moduledoc "Dirige cada solicitud al módulo de dominio, sin leer teclado ni archivos."
  alias Emergencias.{
    Usuarios,
    Zonas,
    Recursos,
    Necesidades,
    Personas,
    Mascotas,
    Albergues,
    Reglas
  }

  @doc "Comprueba el rol y ejecuta la operación solicitada."
  def ejecutar(datos, usuario, operacion) do
    accion = accion(operacion)

    if Usuarios.permite?(usuario.rol, accion),
      do: atender(datos, usuario, operacion),
      else: {:error, :sin_permiso}
  end

  @doc "Nombre de una acción para permisos y auditoría."
  def accion(operacion)
      when is_tuple(operacion) and tuple_size(operacion) > 0 and
             is_atom(elem(operacion, 0)),
      do: elem(operacion, 0)

  def accion(operacion) when is_atom(operacion), do: operacion
  def accion(_), do: :comando_invalido

  defp atender(d, u, op) do
    case op do
      {:cambiar_rol, usuario, rol} ->
        Usuarios.cambiar_rol(d, usuario, rol)

      :listar_usuarios ->
        ok(d, Enum.map(Map.values(d.usuarios), &Usuarios.publico/1))

      {:registrar_zona, c, n, t, p, nivel, a} ->
        Zonas.registrar(d, c, n, t, p, nivel, a)

      :listar_zonas ->
        ok(d, d.zonas |> Map.values() |> Enum.sort_by(& &1.codigo))

      {:arbol_zona, c} ->
        consulta(d, Zonas.arbol(d, c))

      {:resumen_zona, c} ->
        consulta(d, Zonas.resumen(d, c))

      {:registrar_centro, c, n, z, t, r} ->
        Recursos.centro(d, c, n, z, t, r)

      :listar_centros ->
        ok(d, d.centros |> Map.values() |> Enum.sort_by(& &1.codigo))

      {:registrar_recurso, c, n, cat, cant, unidad, centro} ->
        Recursos.registrar(d, u.usuario, c, n, cat, cant, unidad, centro)

      {:listar_recursos, f} when is_map(f) ->
        ok(d, Recursos.listar(d, f))

      {:mover_recurso, c, centro, tipo, cant, detalle} ->
        Recursos.mover(d, u.usuario, c, centro, tipo, cant, detalle)

      {:transferir, c, origen, destino, cant} ->
        Recursos.transferir(d, u.usuario, c, origen, destino, cant)

      {:historial_movimientos, c} ->
        ok(d, d.movimientos |> Enum.filter(&(c == "" or &1.codigo == c)) |> Enum.reverse())

      {:registrar_necesidad, id, t, cant, p, z, desc, dt, dest} ->
        Necesidades.registrar(d, u, id, t, cant, p, z, desc, dt, dest)

      {:listar_necesidades, f} when is_map(f) ->
        ok(d, Necesidades.listar(d, f))

      :pendientes ->
        ok(d, Necesidades.listar(d, %{}) |> Enum.reject(&(&1.estado in [:atendida, :cancelada])))

      {:asignar, n, r, c, cant} ->
        Necesidades.asignar(d, u, n, r, c, cant)

      {:asignar_prioritaria, r, c} ->
        Necesidades.prioritaria(d, u, r, c)

      {:estado_necesidad, n, e} ->
        Necesidades.cambiar_estado(d, u, n, e)

      {:registrar_persona, id, doc, n, edad, z, e} ->
        Personas.registrar(d, u, id, doc, n, edad, z, e)

      {:listar_personas, f} when is_map(f) ->
        ok(d, Personas.listar(d, f))

      {:estado_persona, id, e, motivo} ->
        Personas.estado(d, u, id, e, motivo)

      {:historial_persona, id} ->
        if Map.has_key?(d.personas, id),
          do: ok(d, d.historial_personas |> Enum.filter(&(&1.persona == id)) |> Enum.reverse()),
          else: {:error, :persona_no_existe}

      {:enviar_mensaje, t, dest, c} ->
        Personas.mensaje(d, u, t, dest, c)

      {:listar_mensajes, f} when is_map(f) ->
        ok(d, Reglas.filtrar(Map.values(d.mensajes), f) |> Enum.sort_by(& &1.id))

      {:estado_mensaje, id, e} ->
        Personas.estado_mensaje(d, id, e)

      {:registrar_mascota, id, t, esp, n, car, color, tam, z, contacto} ->
        Mascotas.registrar(d, id, t, esp, n, car, color, tam, z, contacto)

      {:listar_mascotas, f} when is_map(f) ->
        ok(d, Reglas.filtrar(Map.values(d.mascotas), f) |> Enum.sort_by(& &1.id))

      :coincidir_mascotas ->
        Mascotas.buscar(d)

      :coincidencias ->
        ok(d, Mascotas.candidatos(d))

      {:confirmar_mascotas, p, e} ->
        Mascotas.confirmar(d, u, p, e)

      {:registrar_albergue, c, n, z, cap} ->
        Albergues.registrar(d, c, n, z, cap)

      :listar_albergues ->
        ok(d, Albergues.ocupacion(d))

      {:consultar_albergue, c} ->
        consultar_albergue(d, c)

      {:ingreso, c, p} ->
        Albergues.ingreso(d, u, c, p)

      {:salida, c, p} ->
        Albergues.salida(d, u, c, p)

      :ocupacion ->
        ok(d, Albergues.ocupacion(d))

      {:criticos, umbral} when is_integer(umbral) and umbral >= 0 ->
        ok(d, Recursos.listar(d, %{}) |> Enum.filter(&(&1.cantidad <= umbral)))

      {:actividades, nombre} ->
        if nombre == u.usuario or u.rol in [:coordinador, :administrador] do
          ok(
            d,
            d.actividades
            |> Enum.filter(&(nombre == "" or &1.usuario == nombre))
            |> Enum.reverse()
          )
        else
          {:error, :sin_permiso}
        end

      :resumen ->
        ok(d, %{
          usuarios: map_size(d.usuarios),
          zonas: map_size(d.zonas),
          personas: map_size(d.personas),
          personas_localizadas:
            Enum.count(d.personas, fn {_, p} ->
              p.estado in [:localizada, :en_albergue, :reunificada]
            end),
          necesidades_pendientes:
            Enum.count(d.necesidades, fn {_, n} -> n.estado not in [:atendida, :cancelada] end),
          mascotas_activas: Enum.count(d.mascotas, fn {_, m} -> m.estado != :resuelta end),
          mensajes_pendientes: Enum.count(d.mensajes, fn {_, m} -> m.estado == :pendiente end),
          albergues: Albergues.ocupacion(d),
          inventario: Recursos.listar(d, %{})
        })

      _ ->
        {:error, :comando_o_argumentos_invalidos}
    end
  end

  defp consultar_albergue(d, c) do
    case d.albergues[c] do
      nil ->
        {:error, :albergue_no_existe}

      a ->
        centros =
          d.centros |> Map.values() |> Enum.filter(&(&1.tipo == :albergue and &1.referencia == c))

        codigos = Enum.map(centros, & &1.codigo)
        recursos = Recursos.listar(d, %{}) |> Enum.filter(&(&1.centro in codigos))
        necesidades = Necesidades.listar(d, %{destino_tipo: :albergue, destino: c})
        ok(d, %{albergue: Albergues.informacion(a), recursos: recursos, necesidades: necesidades})
    end
  end

  defp ok(datos, respuesta), do: {:ok, respuesta, datos}
  defp consulta(datos, {:ok, respuesta}), do: ok(datos, respuesta)
  defp consulta(_, error), do: error
end
