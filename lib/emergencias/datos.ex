defmodule Emergencias.Datos do
  @moduledoc """
  Estado inmutable del dominio. Los mapas indexan registros por su identificador.
  Las listas conservan los historiales; los residentes de un albergue son MapSet.
  Las sesiones y los PID no se guardan en disco.
  """

  @doc "Construye los datos de una instalación nueva."
  def nuevo do
    %{
      usuarios: %{},
      zonas: %{},
      centros: %{},
      necesidades: %{},
      recursos: %{},
      existencias: %{},
      personas: %{},
      mensajes: %{},
      mascotas: %{},
      albergues: %{},
      movimientos: [],
      actividades: [],
      historial_personas: [],
      asignaciones: [],
      coincidencias: [],
      secuencia: 0
    }
  end

  @doc "Entrega un identificador y los datos con el consecutivo actualizado."
  def siguiente(datos, prefijo) do
    numero = datos.secuencia + 1

    {prefijo <> String.pad_leading(Integer.to_string(numero), 5, "0"),
     %{datos | secuencia: numero}}
  end

  @doc "Registra una actividad sin almacenar contraseñas ni contenido de mensajes."
  def actividad(datos, usuario, accion, resultado) do
    {id, datos} = siguiente(datos, "ACT")

    registro = %{
      id: id,
      usuario: usuario,
      accion: to_string(accion),
      resultado: resultado,
      fecha: fecha()
    }

    %{datos | actividades: [registro | datos.actividades]}
  end

  @doc "Devuelve una fecha UTC legible, también usada por la persistencia."
  def fecha, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
