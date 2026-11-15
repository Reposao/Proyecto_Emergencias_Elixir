defmodule Emergencias.Albergues do
  @moduledoc "Cupos y residentes. MapSet impide duplicar el ingreso de una persona."
  alias Emergencias.{Reglas, Personas, Recursos}

  @doc "Crea el albergue vacío y su centro de inventario con el mismo código."
  def registrar(datos, codigo, nombre, zona, capacidad) do
    cond do
      not Reglas.codigo?(codigo) or not Reglas.texto?(nombre) or not Reglas.natural?(capacidad) ->
        {:error, :datos_albergue_invalidos}

      Map.has_key?(datos.albergues, codigo) or Map.has_key?(datos.centros, codigo) ->
        {:error, :codigo_repetido}

      not Map.has_key?(datos.zonas, zona) ->
        {:error, :zona_no_existe}

      true ->
        a = %{
          codigo: codigo,
          nombre: nombre,
          zona: zona,
          capacidad: capacidad,
          residentes: MapSet.new()
        }

        datos = %{datos | albergues: Map.put(datos.albergues, codigo, a)}
        {:ok, _, nuevos} = Recursos.centro(datos, codigo, nombre, zona, :albergue, codigo)
        {:ok, informacion(a), nuevos}
    end
  end

  @doc "Información pública calculada a partir del conjunto de residentes."
  def informacion(a) do
    ocupacion = MapSet.size(a.residentes)

    Map.merge(a, %{
      ocupacion: ocupacion,
      cupos: a.capacidad - ocupacion,
      porcentaje: if(a.capacidad == 0, do: 0.0, else: ocupacion * 100.0 / a.capacidad)
    })
  end

  @doc "Ingresa una persona y cambia su estado, sin superar la capacidad."
  def ingreso(datos, usuario, codigo, persona) do
    a = datos.albergues[codigo]
    p = datos.personas[persona]

    cond do
      is_nil(a) ->
        {:error, :albergue_no_existe}

      is_nil(p) ->
        {:error, :persona_no_existe}

      p.albergue != "" ->
        {:error, :persona_ya_alojada}

      p.estado == :reunificada ->
        {:error, :persona_ya_reunificada}

      MapSet.size(a.residentes) >= a.capacidad ->
        {:error, :albergue_lleno}

      true ->
        a = %{a | residentes: MapSet.put(a.residentes, persona)}

        nuevos =
          %{datos | albergues: Map.put(datos.albergues, codigo, a)}
          |> Personas.actualizar(
            usuario.usuario,
            %{p | estado: :en_albergue, albergue: codigo, zona: a.zona},
            "Ingreso a " <> codigo
          )

        {:ok, informacion(a), nuevos}
    end
  end

  @doc "Retira una persona alojada y registra el cambio de estado."
  def salida(datos, usuario, codigo, persona) do
    a = datos.albergues[codigo]
    p = datos.personas[persona]

    cond do
      is_nil(a) ->
        {:error, :albergue_no_existe}

      is_nil(p) ->
        {:error, :persona_no_existe}

      p.albergue != codigo or not MapSet.member?(a.residentes, persona) ->
        {:error, :persona_no_alojada_aqui}

      true ->
        a = %{a | residentes: MapSet.delete(a.residentes, persona)}

        nuevos =
          %{datos | albergues: Map.put(datos.albergues, codigo, a)}
          |> Personas.actualizar(
            usuario.usuario,
            %{p | estado: :localizada, albergue: ""},
            "Salida de " <> codigo
          )

        {:ok, informacion(a), nuevos}
    end
  end

  @doc "Ordena los albergues por porcentaje de ocupación descendente."
  def ocupacion(datos) do
    datos.albergues
    |> Map.values()
    |> Enum.map(&informacion/1)
    |> Enum.sort_by(&{-&1.porcentaje, &1.codigo})
  end
end
