defmodule Emergencias.Comandos do
  @moduledoc "Interpreta los comandos de texto y valida cantidades y filtros antes de enviarlos."
  @doc "Separa palabras y admite textos entre comillas dobles."
  def separar(texto), do: separar(String.graphemes(texto), false, [], [], false)
  defp separar([], true, _, _, _), do: {:error, :faltan_comillas_de_cierre}

  defp separar([], false, actual, lista, iniciado),
    do: {:ok, Enum.reverse(agregar(actual, lista, iniciado))}

  defp separar(["\"" | resto], dentro, actual, lista, _),
    do: separar(resto, not dentro, actual, lista, true)

  defp separar([c | resto], false, actual, lista, iniciado) when c in [" ", "\t", "\r", "\n"],
    do: separar(resto, false, [], agregar(actual, lista, iniciado), false)

  defp separar([c | resto], dentro, actual, lista, _),
    do: separar(resto, dentro, [c | actual], lista, true)

  defp agregar(_, lista, false), do: lista
  defp agregar(actual, lista, true), do: [actual |> Enum.reverse() |> Enum.join() | lista]

  @doc "Convierte una línea en una operación. Ningún comando evalúa código Elixir."
  def interpretar(linea) do
    case separar(linea) do
      {:ok, palabras} -> comando(palabras)
      error -> error
    end
  end

  defp comando([]), do: {:ok, :vacio}
  defp comando(["help"]), do: {:ok, :ayuda}
  defp comando(["ayuda"]), do: {:ok, :ayuda}
  defp comando(["exit"]), do: {:ok, :salir}
  defp comando(["salir"]), do: {:ok, :salir}
  defp comando(["disconnect"]), do: {:ok, :disconnect}
  defp comando(["connect", u, p]), do: {:ok, {:connect, u, p, u, :ciudadano, "general"}}

  defp comando(["connect", u, p, rol, zona, nombre]),
    do: {:ok, {:connect, u, p, nombre, rol, zona}}

  defp comando(["connect", u, p, rol, zona]), do: {:ok, {:connect, u, p, u, rol, zona}}
  defp comando(["set_role", u, rol]), do: preparar(:cambiar_rol, [u, rol], [])
  defp comando(["list_users"]), do: {:ok, :listar_usuarios}

  defp comando(["register_zone", c, n, nivel]),
    do: preparar(:registrar_zona, [c, n, "zona", "", nivel, "0"], [5])

  defp comando(["register_zone", c, n, nivel, a]),
    do: preparar(:registrar_zona, [c, n, "zona", "", nivel, a], [5])

  defp comando(["register_sector", c, n, padre, nivel, a]),
    do: preparar(:registrar_zona, [c, n, "sector", padre, nivel, a], [5])

  defp comando(["register_point", c, n, padre, nivel, a]),
    do: preparar(:registrar_zona, [c, n, "punto", padre, nivel, a], [5])

  defp comando(["list_zones"]), do: {:ok, :listar_zonas}
  defp comando(["zone_tree", c]), do: preparar(:arbol_zona, [c], [])
  defp comando(["zone_summary", c]), do: preparar(:resumen_zona, [c], [])

  defp comando(["register_center", c, n, z]),
    do: preparar(:registrar_centro, [c, n, z, "acopio", ""], [])

  defp comando(["register_center", c, n, z, tipo, referencia]),
    do: preparar(:registrar_centro, [c, n, z, tipo, referencia], [])

  defp comando(["list_centers"]), do: {:ok, :listar_centros}

  defp comando(["register_resource", c, n, cant, uni, cen]),
    do: preparar(:registrar_recurso, [c, n, n, cant, uni, cen], [3])

  defp comando(["register_resource", c, n, cat, cant, uni, cen]),
    do: preparar(:registrar_recurso, [c, n, cat, cant, uni, cen], [3])

  defp comando(["stock", c, cen, t, cant, detalle]),
    do: preparar(:mover_recurso, [c, cen, t, cant, detalle], [3])

  defp comando(["transfer_resource", c, origen, destino, cant]),
    do: preparar(:transferir, [c, origen, destino, cant], [3])

  defp comando(["movements"]), do: preparar(:historial_movimientos, [""], [])
  defp comando(["movements", c]), do: preparar(:historial_movimientos, [c], [])

  defp comando(["register_need", id, tipo, cant, p, z, desc]),
    do: preparar(:registrar_necesidad, [id, tipo, cant, p, z, desc, "zona", z], [2])

  defp comando(["register_need", id, tipo, cant, p, z, desc, dt, dest]),
    do: preparar(:registrar_necesidad, [id, tipo, cant, p, z, desc, dt, dest], [2])

  defp comando(["assign_resource", id, recurso, centro, cant]),
    do: preparar(:asignar, [id, recurso, centro, cant], [3])

  defp comando(["assign_priority", recurso, centro]),
    do: preparar(:asignar_prioritaria, [recurso, centro], [])

  defp comando(["need_state", id, estado]), do: preparar(:estado_necesidad, [id, estado], [])
  defp comando(["pending_needs"]), do: {:ok, :pendientes}

  defp comando(["report_person", id, doc, n, edad, z, e]),
    do: preparar(:registrar_persona, [id, doc, n, edad, z, e], [3])

  defp comando(["find_person", doc]), do: {:ok, {:listar_personas, %{documento: doc}}}

  defp comando(["person_state", id, e, motivo]),
    do: preparar(:estado_persona, [id, e, motivo], [])

  defp comando(["person_history", id]), do: preparar(:historial_persona, [id], [])

  defp comando(["send_family_message", id, c]),
    do: preparar(:enviar_mensaje, ["persona", id, c], [])

  defp comando(["send_family_message", t, id, c]), do: preparar(:enviar_mensaje, [t, id, c], [])
  defp comando(["message_state", id, e]), do: preparar(:estado_mensaje, [id, e], [])

  defp comando(["report_pet", id, tipo, esp, n, car, color, tam, z, contacto]) do
    tipo =
      case tipo do
        "lost" -> "perdida"
        "found" -> "encontrada"
        otro -> otro
      end

    preparar(:registrar_mascota, [id, tipo, esp, n, car, color, tam, z, contacto], [])
  end

  defp comando(["match_pets"]), do: {:ok, :coincidir_mascotas}
  defp comando(["pet_candidates"]), do: {:ok, :coincidencias}

  defp comando(["confirm_pets", perdida, encontrada]),
    do: preparar(:confirmar_mascotas, [perdida, encontrada], [])

  defp comando(["register_shelter", c, n, z, cap]),
    do: preparar(:registrar_albergue, [c, n, z, cap], [3])

  defp comando(["list_shelters"]), do: {:ok, :listar_albergues}
  defp comando(["check_shelter", c]), do: preparar(:consultar_albergue, [c], [])
  defp comando(["register_entry", c, p]), do: preparar(:ingreso, [c, p], [])
  defp comando(["register_exit", c, p]), do: preparar(:salida, [c, p], [])
  defp comando(["shelter_occupancy"]), do: {:ok, :ocupacion}
  defp comando(["summary"]), do: {:ok, :resumen}
  defp comando(["critical_resources"]), do: preparar(:criticos, ["5"], [0])
  defp comando(["critical_resources", n]), do: preparar(:criticos, [n], [0])
  defp comando(["activity", u]), do: preparar(:actividades, [u], [])

  defp comando(["list_resources" | filtros]),
    do: filtros(:listar_recursos, filtros, ~w(codigo categoria centro zona))

  defp comando(["list_needs" | filtros]),
    do:
      filtros(
        :listar_necesidades,
        filtros,
        ~w(id tipo zona prioridad estado responsable destino_tipo destino)
      )

  defp comando(["list_people" | filtros]),
    do: filtros(:listar_personas, filtros, ~w(id nombre documento zona estado))

  defp comando(["list_family_messages" | filtros]),
    do: filtros(:listar_mensajes, filtros, ~w(destinatario estado tipo remitente))

  defp comando(["list_pets" | filtros]),
    do: filtros(:listar_mascotas, filtros, ~w(id especie zona estado tipo))

  defp comando(_), do: {:error, :comando_o_numero_de_argumentos_invalido_use_help}

  defp preparar(accion, argumentos, enteros) do
    resultados =
      argumentos
      |> Enum.with_index()
      |> Enum.map(fn {valor, indice} ->
        if indice in enteros do
          case Integer.parse(valor) do
            {numero, ""} -> {:ok, numero}
            _ -> {:error, :se_esperaba_un_entero}
          end
        else
          {:ok, valor}
        end
      end)

    case Enum.find(resultados, &match?({:error, _}, &1)) do
      nil -> {:ok, List.to_tuple([accion | Enum.map(resultados, fn {:ok, v} -> v end)])}
      error -> error
    end
  end

  defp filtros(accion, elementos, admitidos) do
    # Las claves proceden de una lista fija del programa, nunca de String.to_atom.
    claves = %{
      "id" => :id,
      "nombre" => :nombre,
      "documento" => :documento,
      "codigo" => :codigo,
      "categoria" => :categoria,
      "centro" => :centro,
      "zona" => :zona,
      "tipo" => :tipo,
      "prioridad" => :prioridad,
      "estado" => :estado,
      "especie" => :especie,
      "responsable" => :responsable,
      "destino_tipo" => :destino_tipo,
      "destino" => :destino,
      "destinatario" => :destinatario,
      "remitente" => :remitente
    }

    resultado =
      Enum.reduce_while(elementos, {:ok, %{}}, fn elemento, {:ok, mapa} ->
        case String.split(elemento, "=", parts: 2) do
          [campo, valor] ->
            if campo in admitidos and valor != "" and not Map.has_key?(mapa, claves[campo]),
              do: {:cont, {:ok, Map.put(mapa, claves[campo], valor)}},
              else: {:halt, {:error, :filtro_invalido_o_repetido}}

          _ ->
            {:halt, {:error, :use_filtros_campo_igual_valor}}
        end
      end)

    case resultado do
      {:ok, mapa} -> {:ok, {accion, mapa}}
      error -> error
    end
  end
end
