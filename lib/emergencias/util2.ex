defmodule Emergencias.Util2 do
  @moduledoc """
  Adaptación pequeña de la entrada y salida de Util2 del profesor.
  La consola interpreta los datos; las funciones de dominio no leen el teclado.
  """

  @doc "Lee una línea y reconoce fin de entrada sin lanzar una excepción."
  def ingresar(pregunta, :texto) do
    case IO.gets(pregunta) do
      :eof -> :fin
      nil -> :fin
      {:error, _} -> :fin
      linea -> {:ok, String.trim(linea)}
    end
  end

  @doc "Distingue salida normal y errores."
  def mostrar(mensaje, :mensaje), do: IO.puts(mensaje)
  def mostrar(mensaje, :error), do: IO.puts(:standard_error, mensaje)

  @doc "Presenta resultados sin imprimir trazas ni datos de credenciales."
  def resultado(resultado, accion \\ nil)

  def resultado({:ok, valor}, accion) do
    titulo = Emergencias.Salida.titulo(accion) |> String.upcase()
    contenido = Emergencias.Salida.formatear(valor)
    separador = String.duplicate("-", String.length(titulo))

    mostrar("\n#{titulo}\n#{separador}\n#{contenido}\n", :mensaje)
  end

  def resultado({:error, razon}, _accion) do
    mostrar(
      "\nNo se realizó la operación.\nMotivo: #{Emergencias.Salida.error(razon)}\n",
      :error
    )
  end
end
