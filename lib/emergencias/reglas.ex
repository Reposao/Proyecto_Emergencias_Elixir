defmodule Emergencias.Reglas do
  @moduledoc "Validaciones compartidas. Los errores esperados se representan con tuplas."

  @doc "Comprueba un texto obligatorio."
  def texto?(valor), do: is_binary(valor) and String.trim(valor) != ""

  @doc "Identificadores sencillos para comandos y archivos de texto."
  def codigo?(valor) when is_binary(valor) do
    texto?(valor) and String.length(valor) <= 80 and
      String.match?(valor, ~r/^[\p{L}\p{N}_-]+$/u)
  end

  def codigo?(_), do: false

  @doc "Valida cantidades enteras no negativas."
  def natural?(valor), do: is_integer(valor) and valor >= 0

  @doc "Valida cantidades enteras positivas."
  def positivo?(valor), do: is_integer(valor) and valor > 0

  @doc "Normaliza una opción sin crear átomos a partir de texto del usuario."
  def opcion(valor, opciones) do
    Enum.find(opciones, fn opcion ->
      valor == opcion or valor == to_string(opcion)
    end)
  end

  @doc "Obtiene registros que cumplen todos los filtros indicados."
  def filtrar(registros, filtros) when is_map(filtros) do
    Enum.filter(registros, fn registro ->
      Enum.all?(filtros, fn {campo, valor} ->
        Map.has_key?(registro, campo) and
          to_string(Map.get(registro, campo)) == to_string(valor)
      end)
    end)
  end

  @doc "Comprueba una transición y rechaza también repetir el mismo estado."
  def transicion?(actual, nuevo, reglas) do
    nuevo in Map.get(reglas, actual, [])
  end
end
