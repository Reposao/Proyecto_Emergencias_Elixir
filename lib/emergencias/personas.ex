defmodule Emergencias.Personas do
  @moduledoc "Personas afectadas, historial y comunicación familiar."
  alias Emergencias.{Datos, Reglas}
  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @doc "Registra una persona con documento o referencia único."
  def registrar(datos, usuario, id, documento, nombre, edad, zona, estado) do
    estado = Reglas.opcion(estado, @estados)

    cond do
      not Reglas.codigo?(id) or not Reglas.texto?(documento) or
        not Reglas.texto?(nombre) or not Reglas.natural?(edad) or is_nil(estado) ->
        {:error, :datos_persona_invalidos}

      Map.has_key?(datos.personas, id) or
          Enum.any?(datos.personas, fn {_, p} ->
            p.documento == documento
          end) ->
        {:error, :persona_repetida}

      not Map.has_key?(datos.zonas, zona) ->
        {:error, :zona_no_existe}

      estado in [:en_albergue, :reunificada] ->
        {:error, :estado_inicial_invalido}

      true ->
        p = %{
          id: id,
          documento: documento,
          nombre: nombre,
          edad: edad,
          zona: zona,
          estado: estado,
          albergue: ""
        }

        nuevos =
          %{datos | personas: Map.put(datos.personas, id, p)}
          |> historial(usuario.usuario, id, :sin_registro, estado, "Registro inicial")

        {:ok, p, nuevos}
    end
  end

  @doc "Busca por nombre parcial y por los demás campos exactos."
  def listar(datos, filtros) do
    Enum.filter(Map.values(datos.personas), fn persona ->
      Enum.all?(filtros, fn
        {:nombre, texto} ->
          String.contains?(String.downcase(persona.nombre), String.downcase(to_string(texto)))

        {campo, valor} ->
          Map.has_key?(persona, campo) and
            to_string(Map.get(persona, campo)) == to_string(valor)
      end)
    end)
    |> Enum.sort_by(& &1.id)
  end

  @doc "Aplica transiciones válidas. El albergue controla sus propios ingresos y salidas."
  def estado(datos, usuario, id, nuevo, motivo) do
    p = datos.personas[id]
    nuevo = Reglas.opcion(nuevo, @estados)

    cond do
      is_nil(p) ->
        {:error, :persona_no_existe}

      not Reglas.texto?(motivo) ->
        {:error, :motivo_obligatorio}

      p.albergue != "" ->
        {:error, :registre_primero_la_salida_del_albergue}

      not Reglas.transicion?(p.estado, nuevo, %{
        sin_informacion: [:reportada, :localizada],
        reportada: [:localizada, :trasladada],
        localizada: [:trasladada, :reunificada],
        trasladada: [:localizada, :reunificada],
        reunificada: []
      }) ->
        {:error, :transicion_invalida}

      true ->
        {:ok, %{p | estado: nuevo},
         actualizar(datos, usuario.usuario, %{p | estado: nuevo}, motivo)}
    end
  end

  @doc "Actualiza la persona y agrega su cambio de estado en la misma operación."
  def actualizar(datos, usuario, nueva, motivo) do
    anterior = datos.personas[nueva.id]

    %{datos | personas: Map.put(datos.personas, nueva.id, nueva)}
    |> historial(usuario, nueva.id, anterior.estado, nueva.estado, motivo)
  end

  defp historial(datos, usuario, persona, anterior, nuevo, motivo) do
    {id, datos} = Datos.siguiente(datos, "HIS")

    h = %{
      id: id,
      persona: persona,
      anterior: anterior,
      nuevo: nuevo,
      motivo: motivo,
      usuario: usuario,
      fecha: Datos.fecha()
    }

    %{datos | historial_personas: [h | datos.historial_personas]}
  end

  @doc "Guarda un mensaje para una persona registrada o una familia identificada."
  def mensaje(datos, usuario, tipo, destinatario, contenido) do
    tipo = Reglas.opcion(tipo, [:persona, :familia])

    cond do
      is_nil(tipo) or not Reglas.texto?(destinatario) or not Reglas.texto?(contenido) ->
        {:error, :mensaje_invalido}

      tipo == :persona and not Map.has_key?(datos.personas, destinatario) ->
        {:error, :persona_no_existe}

      true ->
        {id, datos} = Datos.siguiente(datos, "MSG")

        m = %{
          id: id,
          tipo: tipo,
          destinatario: destinatario,
          contenido: contenido,
          remitente: usuario.usuario,
          fecha: Datos.fecha(),
          estado: :pendiente
        }

        {:ok, m, %{datos | mensajes: Map.put(datos.mensajes, id, m)}}
    end
  end

  @doc "Marca la entrega o vuelve a dejar el mensaje pendiente."
  def estado_mensaje(datos, id, estado) do
    estado = Reglas.opcion(estado, [:pendiente, :entregado])
    m = datos.mensajes[id]

    cond do
      is_nil(m) ->
        {:error, :mensaje_no_existe}

      is_nil(estado) or m.estado == estado ->
        {:error, :transicion_invalida}

      true ->
        nuevo = %{m | estado: estado}
        {:ok, nuevo, %{datos | mensajes: Map.put(datos.mensajes, id, nuevo)}}
    end
  end
end
