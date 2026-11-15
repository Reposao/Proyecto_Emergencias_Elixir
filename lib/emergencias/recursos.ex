defmodule Emergencias.Recursos do
  @moduledoc """
  Catálogo e inventario por centro. Una operación devuelve todos los cambios juntos.
  El GenServer comprueba y confirma ese resultado sin intercalar otra solicitud.
  """

  alias Emergencias.{Datos, Reglas}

  @doc "Registra un centro asociado a una zona existente."
  def centro(datos, codigo, nombre, zona, tipo, referencia) do
    tipo = Reglas.opcion(tipo, [:acopio, :albergue, :punto])

    cond do
      not Reglas.codigo?(codigo) or not Reglas.texto?(nombre) or is_nil(tipo) ->
        {:error, :datos_centro_invalidos}

      Map.has_key?(datos.centros, codigo) ->
        {:error, :codigo_repetido}

      not Map.has_key?(datos.zonas, zona) ->
        {:error, :zona_no_existe}

      tipo == :albergue and not Map.has_key?(datos.albergues, referencia) ->
        {:error, :albergue_no_existe}

      tipo == :albergue and datos.albergues[referencia].zona != zona ->
        {:error, :zona_distinta_del_albergue}

      tipo == :punto and datos.zonas[zona].tipo != :punto ->
        {:error, :se_esperaba_un_punto}

      true ->
        centro = %{
          codigo: codigo,
          nombre: nombre,
          zona: zona,
          tipo: tipo,
          referencia: referencia
        }

        {:ok, centro, %{datos | centros: Map.put(datos.centros, codigo, centro)}}
    end
  end

  @doc "Crea un código de recurso y registra la entrada inicial de inventario."
  def registrar(datos, usuario, codigo, nombre, categoria, cantidad, unidad, centro) do
    cond do
      not Reglas.codigo?(codigo) or not Reglas.texto?(nombre) or
          not Reglas.texto?(to_string(categoria)) or not Reglas.texto?(unidad) or
          not Reglas.natural?(cantidad) ->
        {:error, :datos_recurso_invalidos}

      Map.has_key?(datos.recursos, codigo) ->
        {:error, :codigo_repetido}

      not Map.has_key?(datos.centros, centro) ->
        {:error, :centro_no_existe}

      true ->
        recurso = %{
          codigo: codigo,
          nombre: nombre,
          categoria: to_string(categoria),
          unidad: unidad
        }

        nuevos =
          %{datos | recursos: Map.put(datos.recursos, codigo, recurso)}
          |> poner(codigo, centro, cantidad)
          |> movimiento(usuario, codigo, "", centro, :registro, cantidad, "Inventario inicial")

        {:ok, recurso, nuevos}
    end
  end

  @doc "Consulta el saldo de un recurso en un centro."
  def saldo(datos, codigo, centro) do
    Map.get(datos.existencias, llave(codigo, centro), %{cantidad: 0}).cantidad
  end

  @doc "Actualiza una existencia, llamada únicamente después de validar las cantidades."
  def poner(datos, codigo, centro, cantidad) do
    id = llave(codigo, centro)

    existencia = %{
      id: id,
      codigo: codigo,
      centro: centro,
      cantidad: cantidad
    }

    %{datos | existencias: Map.put(datos.existencias, id, existencia)}
  end

  defp llave(codigo, centro), do: codigo <> "@" <> centro

  @doc "Aplica una entrada o salida e incluye el movimiento correspondiente."
  def mover(datos, usuario, codigo, centro, tipo, cantidad, detalle) do
    tipo = Reglas.opcion(tipo, [:entrada, :salida])

    cond do
      not Map.has_key?(datos.recursos, codigo) ->
        {:error, :recurso_no_existe}

      not Map.has_key?(datos.centros, centro) ->
        {:error, :centro_no_existe}

      is_nil(tipo) or not Reglas.positivo?(cantidad) or not Reglas.texto?(detalle) ->
        {:error, :movimiento_invalido}

      tipo == :salida and cantidad > saldo(datos, codigo, centro) ->
        {:error, :inventario_insuficiente}

      true ->
        actual = saldo(datos, codigo, centro)

        nuevo =
          if tipo == :entrada do
            actual + cantidad
          else
            actual - cantidad
          end

        datos =
          datos
          |> poner(codigo, centro, nuevo)
          |> movimiento(usuario, codigo, centro, centro, tipo, cantidad, detalle)

        {:ok, %{codigo: codigo, centro: centro, disponible: nuevo}, datos}
    end
  end

  @doc "Descuenta del origen y suma en el destino en una sola operación."
  def transferir(datos, usuario, codigo, origen, destino, cantidad) do
    cond do
      not Map.has_key?(datos.recursos, codigo) ->
        {:error, :recurso_no_existe}

      not Map.has_key?(datos.centros, origen) or not Map.has_key?(datos.centros, destino) ->
        {:error, :centro_no_existe}

      origen == destino or not Reglas.positivo?(cantidad) ->
        {:error, :transferencia_invalida}

      cantidad > saldo(datos, codigo, origen) ->
        {:error, :inventario_insuficiente}

      true ->
        nuevos =
          datos
          |> poner(codigo, origen, saldo(datos, codigo, origen) - cantidad)
          |> poner(codigo, destino, saldo(datos, codigo, destino) + cantidad)
          |> movimiento(usuario, codigo, origen, destino, :transferencia, cantidad, "Traslado")

        {:ok, :transferencia_realizada, nuevos}
    end
  end

  @doc "Registra el historial de una operación de inventario."
  def movimiento(datos, usuario, codigo, origen, destino, tipo, cantidad, detalle) do
    {id, datos} = Datos.siguiente(datos, "MOV")

    movimiento = %{
      id: id,
      usuario: usuario,
      codigo: codigo,
      origen: origen,
      destino: destino,
      tipo: tipo,
      cantidad: cantidad,
      detalle: detalle,
      fecha: Datos.fecha()
    }

    %{datos | movimientos: [movimiento | datos.movimientos]}
  end

  @doc "Disponibilidad por código, categoría, centro o zona."
  def listar(datos, filtros) do
    datos.existencias
    |> Map.values()
    |> Enum.map(fn existencia ->
      Map.merge(existencia, datos.recursos[existencia.codigo])
      |> Map.put(:zona, datos.centros[existencia.centro].zona)
    end)
    |> Reglas.filtrar(filtros)
    |> Enum.sort_by(&{&1.codigo, &1.centro})
  end
end
