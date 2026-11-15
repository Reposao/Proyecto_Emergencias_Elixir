defmodule Emergencias.Mascotas do
  @moduledoc "Reportes de mascotas y coincidencias con un criterio de similitud explícito."
  alias Emergencias.{Datos, Reglas}

  @doc "Registra un reporte activo de mascota perdida o encontrada."
  def registrar(datos, id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto) do
    tipo = Reglas.opcion(tipo, [:perdida, :encontrada])
    textos = [especie, nombre, caracteristicas, color, tamano, contacto]

    cond do
      not Reglas.codigo?(id) or is_nil(tipo) or not Enum.all?(textos, &Reglas.texto?/1) ->
        {:error, :datos_mascota_invalidos}

      Map.has_key?(datos.mascotas, id) ->
        {:error, :codigo_repetido}

      not Map.has_key?(datos.zonas, zona) ->
        {:error, :zona_no_existe}

      true ->
        m = %{
          id: id,
          tipo: tipo,
          especie: especie,
          nombre: nombre,
          caracteristicas: caracteristicas,
          color: color,
          tamano: tamano,
          zona: zona,
          contacto: contacto,
          estado: :activa,
          pareja: ""
        }

        {:ok, m, %{datos | mascotas: Map.put(datos.mascotas, id, m)}}
    end
  end

  @doc "Suma recursivamente los pesos de atributos iguales y conocidos."
  def puntuar([]), do: 0

  def puntuar([{a, b, peso} | resto]) do
    iguales =
      normalizar(a) == normalizar(b) and
        normalizar(a) not in ["", "desconocido", "desconocida"]

    if(iguales, do: peso, else: 0) + puntuar(resto)
  end

  defp normalizar(texto), do: texto |> String.trim() |> String.downcase()

  @doc "Especie 3, color 2, tamaño 1, zona 2, nombre 1 y características 1."
  def similitud(a, b) do
    puntuar([
      {a.especie, b.especie, 3},
      {a.color, b.color, 2},
      {a.tamano, b.tamano, 1},
      {a.zona, b.zona, 2},
      {a.nombre, b.nombre, 1},
      {a.caracteristicas, b.caracteristicas, 1}
    ])
  end

  @doc "Compara varios atributos; exige igual especie y al menos 6 de 10 puntos."
  def candidatos(datos) do
    activos = datos.mascotas |> Map.values() |> Enum.reject(&(&1.estado == :resuelta))
    perdidos = Enum.filter(activos, &(&1.tipo == :perdida))
    encontrados = Enum.filter(activos, &(&1.tipo == :encontrada))

    Enum.flat_map(perdidos, fn a ->
      Enum.flat_map(encontrados, fn b ->
        puntos = similitud(a, b)

        if normalizar(a.especie) == normalizar(b.especie) and puntos >= 6,
          do: [%{perdida: a.id, encontrada: b.id, puntaje: puntos}],
          else: []
      end)
    end)
    |> Enum.sort_by(&{-&1.puntaje, &1.perdida, &1.encontrada})
  end

  @doc "Actualiza posibles coincidencias sin cerrar reportes automáticamente."
  def buscar(datos) do
    coincidencias = candidatos(datos)
    relacionados = Enum.flat_map(coincidencias, &[&1.perdida, &1.encontrada]) |> MapSet.new()

    mascotas =
      Map.new(datos.mascotas, fn {id, m} ->
        estado =
          cond do
            m.estado == :resuelta -> :resuelta
            MapSet.member?(relacionados, id) -> :posible_coincidencia
            true -> :activa
          end

        {id, %{m | estado: estado}}
      end)

    {:ok, coincidencias, %{datos | mascotas: mascotas}}
  end

  @doc "Cierra ambos reportes juntos y rechaza confirmar dos veces o reutilizar uno."
  def confirmar(datos, usuario, perdida, encontrada) do
    a = datos.mascotas[perdida]
    b = datos.mascotas[encontrada]

    cond do
      is_nil(a) or is_nil(b) ->
        {:error, :reporte_no_existe}

      a.estado == :resuelta or b.estado == :resuelta ->
        {:error, :reporte_ya_resuelto}

      a.tipo != :perdida or b.tipo != :encontrada or perdida == encontrada ->
        {:error, :tipos_no_corresponden}

      normalizar(a.especie) != normalizar(b.especie) or similitud(a, b) < 6 ->
        {:error, :similitud_insuficiente}

      true ->
        {id, datos} = Datos.siguiente(datos, "COI")

        registro = %{
          id: id,
          perdida: perdida,
          encontrada: encontrada,
          puntaje: similitud(a, b),
          usuario: usuario.usuario,
          fecha: Datos.fecha()
        }

        mascotas =
          datos.mascotas
          |> Map.put(perdida, %{a | estado: :resuelta, pareja: encontrada})
          |> Map.put(encontrada, %{b | estado: :resuelta, pareja: perdida})

        {:ok, registro,
         %{datos | mascotas: mascotas, coincidencias: [registro | datos.coincidencias]}}
    end
  end
end
