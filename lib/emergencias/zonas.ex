defmodule Emergencias.Zonas do
  @moduledoc "Registro y consultas recursivas sobre zona -> sectores -> puntos."

  alias Emergencias.{Zona, Reglas}

  @doc "Agrega una zona raíz o un hijo de un nodo existente."
  def registrar(datos, codigo, nombre, tipo, padre, nivel, afectados) do
    tipo = Reglas.opcion(tipo, [:zona, :sector, :punto])
    nivel = Reglas.opcion(nivel, [:critico, :alto, :medio, :bajo])

    cond do
      not Reglas.codigo?(codigo) or not Reglas.texto?(nombre) or
          not Reglas.natural?(afectados) or is_nil(tipo) or is_nil(nivel) ->
        {:error, :datos_zona_invalidos}

      Map.has_key?(datos.zonas, codigo) ->
        {:error, :codigo_repetido}

      not padre_valido?(datos, tipo, padre) ->
        {:error, :jerarquia_invalida}

      true ->
        zona = Zona.crear(codigo, nombre, tipo, padre, nivel, afectados)
        {:ok, zona, %{datos | zonas: Map.put(datos.zonas, codigo, zona)}}
    end
  end

  defp padre_valido?(_, :zona, ""), do: true
  defp padre_valido?(datos, :sector, padre), do: tipo?(datos, padre, :zona)
  defp padre_valido?(datos, :punto, padre), do: tipo?(datos, padre, :sector)
  defp padre_valido?(_, _, _), do: false

  defp tipo?(datos, codigo, tipo) do
    match?(%{tipo: ^tipo}, datos.zonas[codigo])
  end

  @doc "Construye recursivamente la estructura anidada que se utiliza en el resumen."
  def arbol(datos, codigo) do
    case Map.fetch(datos.zonas, codigo) do
      :error ->
        {:error, :zona_no_existe}

      {:ok, nodo} ->
        hijos =
          datos.zonas
          |> Map.values()
          |> Enum.filter(&(&1.padre == codigo))
          |> Enum.sort_by(& &1.codigo)
          |> Enum.map(fn hijo ->
            {:ok, rama} = arbol(datos, hijo.codigo)
            rama
          end)

        {:ok, %{nodo | hijos: hijos}}
    end
  end

  @doc "Suma recursivamente las estimaciones propias de cada nodo, sin duplicarlas."
  def total_afectados(%Zona{afectados: afectados, hijos: hijos}) do
    afectados + sumar_hijos(hijos)
  end

  defp sumar_hijos([]), do: 0

  defp sumar_hijos([hijo | resto]) do
    total_afectados(hijo) + sumar_hijos(resto)
  end

  @doc "Recoge recursivamente los códigos de un árbol y sus descendientes."
  def codigos(%Zona{codigo: codigo, hijos: hijos}) do
    [codigo | Enum.flat_map(hijos, &codigos/1)]
  end

  @doc "Consulta cifras de una zona incluyendo sus sectores y puntos."
  def resumen(datos, codigo) do
    case arbol(datos, codigo) do
      {:error, razon} ->
        {:error, razon}

      {:ok, raiz} ->
        zonas = MapSet.new(codigos(raiz))

        contar = fn tabla ->
          Enum.count(Map.values(tabla), &MapSet.member?(zonas, &1.zona))
        end

        pendientes =
          Enum.count(Map.values(datos.necesidades), fn n ->
            MapSet.member?(zonas, n.zona) and
              n.estado not in [:atendida, :cancelada]
          end)

        {:ok,
         %{
           zona: codigo,
           afectados_estimados: total_afectados(raiz),
           nodos: MapSet.size(zonas),
           necesidades_pendientes: pendientes,
           personas: contar.(datos.personas),
           mascotas: contar.(datos.mascotas),
           albergues: contar.(datos.albergues),
           centros: contar.(datos.centros)
         }}
    end
  end
end
