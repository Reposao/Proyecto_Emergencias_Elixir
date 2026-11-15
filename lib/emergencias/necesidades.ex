defmodule Emergencias.Necesidades do
  @moduledoc "Solicitudes, orden de prioridad y asignaciones sin doble consumo."
  alias Emergencias.{Necesidad, Datos, Reglas, Recursos}

  @tipos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]
  @prioridades [:critica, :alta, :media, :baja]

  @doc "Registra una necesidad y comprueba la entidad beneficiaria."
  def registrar(
        datos,
        usuario,
        id,
        tipo,
        cantidad,
        prioridad,
        zona,
        descripcion,
        destino_tipo,
        destino
      ) do
    tipo = Reglas.opcion(tipo, @tipos)
    prioridad = Reglas.opcion(prioridad, @prioridades)
    destino_tipo = Reglas.opcion(destino_tipo, [:persona, :familia, :albergue, :zona])

    cond do
      not Reglas.codigo?(id) or is_nil(tipo) or is_nil(prioridad) or
        not Reglas.positivo?(cantidad) or not Reglas.texto?(descripcion) ->
        {:error, :datos_necesidad_invalidos}

      Map.has_key?(datos.necesidades, id) ->
        {:error, :codigo_repetido}

      not Map.has_key?(datos.zonas, zona) ->
        {:error, :zona_no_existe}

      not destino_valido?(datos, destino_tipo, destino, zona) ->
        {:error, :destino_invalido}

      true ->
        n =
          Necesidad.crear(
            id,
            tipo,
            cantidad,
            zona,
            prioridad,
            usuario.usuario,
            descripcion,
            destino_tipo,
            destino
          )

        {:ok, n, %{datos | necesidades: Map.put(datos.necesidades, id, n)}}
    end
  end

  defp destino_valido?(d, :zona, id, zona), do: id == zona and Map.has_key?(d.zonas, id)
  defp destino_valido?(d, :persona, id, _), do: Map.has_key?(d.personas, id)

  defp destino_valido?(d, :albergue, id, zona),
    do: match?(%{zona: ^zona}, d.albergues[id])

  defp destino_valido?(_, :familia, id, _), do: Reglas.texto?(id)
  defp destino_valido?(_, _, _, _), do: false

  @doc "Ordenación recursiva por prioridad e identificador; conserva un criterio estable."
  def priorizar([]), do: []
  def priorizar([n | resto]), do: insertar(n, priorizar(resto))
  defp insertar(n, []), do: [n]

  defp insertar(n, [primero | resto]) do
    if orden(n) <= orden(primero), do: [n, primero | resto], else: [primero | insertar(n, resto)]
  end

  defp orden(n), do: {Enum.find_index(@prioridades, &(&1 == n.prioridad)), n.id}

  @doc "Obtiene necesidades filtradas y ordenadas, no solo rotuladas con prioridad."
  def listar(datos, filtros),
    do: datos.necesidades |> Map.values() |> Reglas.filtrar(filtros) |> priorizar()

  @doc "Asigna una cantidad, actualizando necesidad, saldo e historial conjuntamente."
  def asignar(datos, usuario, id, codigo, centro, cantidad) do
    n = datos.necesidades[id]
    recurso = datos.recursos[codigo]

    cond do
      is_nil(n) ->
        {:error, :necesidad_no_existe}

      is_nil(recurso) ->
        {:error, :recurso_no_existe}

      not Map.has_key?(datos.centros, centro) ->
        {:error, :centro_no_existe}

      not Reglas.positivo?(cantidad) ->
        {:error, :cantidad_invalida}

      n.estado not in [:pendiente, :asignada] ->
        {:error, :necesidad_no_asignable}

      recurso.categoria != to_string(n.tipo) ->
        {:error, :categoria_no_corresponde}

      cantidad > n.cantidad - n.asignada ->
        {:error, :supera_cantidad_requerida}

      cantidad > Recursos.saldo(datos, codigo, centro) ->
        {:error, :inventario_insuficiente}

      true ->
        actualizada = %{n | asignada: n.asignada + cantidad, estado: :asignada}
        {aid, nuevos} = Datos.siguiente(datos, "ASG")

        asignacion = %{
          id: aid,
          necesidad: id,
          codigo: codigo,
          centro: centro,
          cantidad: cantidad,
          devuelta: false,
          fecha: Datos.fecha()
        }

        nuevos =
          %{
            nuevos
            | necesidades: Map.put(nuevos.necesidades, id, actualizada),
              asignaciones: [asignacion | nuevos.asignaciones]
          }
          |> Recursos.poner(codigo, centro, Recursos.saldo(datos, codigo, centro) - cantidad)
          |> Recursos.movimiento(usuario.usuario, codigo, centro, "", :asignacion, cantidad, id)

        {:ok, actualizada, nuevos}
    end
  end

  @doc "Selecciona la primera solicitud de la categoría según su prioridad."
  def prioritaria(datos, usuario, codigo, centro) do
    case datos.recursos[codigo] do
      nil ->
        {:error, :recurso_no_existe}

      recurso ->
        n =
          listar(datos, %{})
          |> Enum.find(fn n ->
            n.estado in [:pendiente, :asignada] and to_string(n.tipo) == recurso.categoria and
              n.asignada < n.cantidad
          end)

        if is_nil(n),
          do: {:error, :sin_solicitudes_pendientes},
          else:
            asignar(
              datos,
              usuario,
              n.id,
              codigo,
              centro,
              min(n.cantidad - n.asignada, Recursos.saldo(datos, codigo, centro))
            )
    end
  end

  @doc "Controla transiciones; cancelar devuelve las reservas que aún no entraron en atención."
  def cambiar_estado(datos, usuario, id, estado) do
    n = datos.necesidades[id]
    estado = Reglas.opcion(estado, [:en_atencion, :atendida, :cancelada])

    cond do
      is_nil(n) ->
        {:error, :necesidad_no_existe}

      not (usuario.rol in [:administrador, :coordinador, :voluntario] or
               (usuario.usuario == n.responsable and estado == :cancelada)) ->
        {:error, :sin_permiso}

      not Reglas.transicion?(n.estado, estado, %{
        pendiente: [:cancelada],
        asignada: [:en_atencion, :cancelada],
        en_atencion: [:atendida],
        atendida: [],
        cancelada: []
      }) ->
        {:error, :transicion_invalida}

      estado == :en_atencion and n.asignada != n.cantidad ->
        {:error, :faltan_recursos_por_asignar}

      true ->
        nuevos = if estado == :cancelada, do: devolver(datos, usuario, id), else: datos
        n = %{n | estado: estado, asignada: if(estado == :cancelada, do: 0, else: n.asignada)}
        {:ok, n, %{nuevos | necesidades: Map.put(nuevos.necesidades, id, n)}}
    end
  end

  defp devolver(datos, usuario, id) do
    Enum.reduce(datos.asignaciones, datos, fn a, actual ->
      if a.necesidad == id and not a.devuelta do
        actual =
          actual
          |> Recursos.poner(
            a.codigo,
            a.centro,
            Recursos.saldo(actual, a.codigo, a.centro) + a.cantidad
          )
          |> Recursos.movimiento(
            usuario.usuario,
            a.codigo,
            "",
            a.centro,
            :devolucion,
            a.cantidad,
            id
          )

        %{
          actual
          | asignaciones:
              Enum.map(actual.asignaciones, fn registro ->
                if registro.id == a.id, do: %{registro | devuelta: true}, else: registro
              end)
        }
      else
        actual
      end
    end)
  end
end
