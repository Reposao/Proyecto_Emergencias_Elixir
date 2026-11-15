defmodule Emergencias.Persistencia do
  @moduledoc """
  Conserva el estado en un archivo de texto tabulado UTF-8, sin dependencias.
  Las columnas tienen un esquema fijo; no se evalúa código leído desde archivos.
  Primero escribe un temporal y después lo renombra. Mantiene una copia anterior.
  """
  alias Emergencias.Datos

  @tablas [
    {:usuarios, :mapa, :usuario,
     [usuario: :texto, nombre: :texto, rol: :atomo, zona: :texto, sal: :texto, clave_hash: :texto]},
    {:zonas, :mapa, :codigo,
     [
       codigo: :texto,
       nombre: :texto,
       tipo: :atomo,
       padre: :texto,
       nivel: :atomo,
       afectados: :entero
     ]},
    {:centros, :mapa, :codigo,
     [codigo: :texto, nombre: :texto, zona: :texto, tipo: :atomo, referencia: :texto]},
    {:recursos, :mapa, :codigo,
     [codigo: :texto, nombre: :texto, categoria: :texto, unidad: :texto]},
    {:existencias, :mapa, :id, [id: :texto, codigo: :texto, centro: :texto, cantidad: :entero]},
    {:necesidades, :mapa, :id,
     [
       id: :texto,
       tipo: :atomo,
       cantidad: :entero,
       asignada: :entero,
       zona: :texto,
       prioridad: :atomo,
       responsable: :texto,
       estado: :atomo,
       descripcion: :texto,
       destino_tipo: :atomo,
       destino: :texto
     ]},
    {:personas, :mapa, :id,
     [
       id: :texto,
       documento: :texto,
       nombre: :texto,
       edad: :entero,
       zona: :texto,
       estado: :atomo,
       albergue: :texto
     ]},
    {:mensajes, :mapa, :id,
     [
       id: :texto,
       tipo: :atomo,
       destinatario: :texto,
       contenido: :texto,
       remitente: :texto,
       fecha: :texto,
       estado: :atomo
     ]},
    {:mascotas, :mapa, :id,
     [
       id: :texto,
       tipo: :atomo,
       especie: :texto,
       nombre: :texto,
       caracteristicas: :texto,
       color: :texto,
       tamano: :texto,
       zona: :texto,
       contacto: :texto,
       estado: :atomo,
       pareja: :texto
     ]},
    {:albergues, :mapa, :codigo,
     [codigo: :texto, nombre: :texto, zona: :texto, capacidad: :entero, residentes: :conjunto]},
    {:movimientos, :lista, :id,
     [
       id: :texto,
       usuario: :texto,
       codigo: :texto,
       origen: :texto,
       destino: :texto,
       tipo: :atomo,
       cantidad: :entero,
       detalle: :texto,
       fecha: :texto
     ]},
    {:actividades, :lista, :id,
     [id: :texto, usuario: :texto, accion: :texto, resultado: :texto, fecha: :texto]},
    {:historial_personas, :lista, :id,
     [
       id: :texto,
       persona: :texto,
       anterior: :atomo,
       nuevo: :atomo,
       motivo: :texto,
       usuario: :texto,
       fecha: :texto
     ]},
    {:asignaciones, :lista, :id,
     [
       id: :texto,
       necesidad: :texto,
       codigo: :texto,
       centro: :texto,
       cantidad: :entero,
       devuelta: :boolean,
       fecha: :texto
     ]},
    {:coincidencias, :lista, :id,
     [
       id: :texto,
       perdida: :texto,
       encontrada: :texto,
       puntaje: :entero,
       usuario: :texto,
       fecha: :texto
     ]}
  ]
  @atomos ~w(ciudadano voluntario coordinador administrador zona sector punto critico alto medio bajo
    acopio albergue agua alimentos medicamentos primeros_auxilios refugio transporte rescate otra
    critica alta media baja pendiente asignada en_atencion atendida cancelada persona familia
    sin_registro sin_informacion reportada localizada trasladada en_albergue reunificada entregado
    perdida encontrada activa posible_coincidencia resuelta registro entrada salida transferencia
    asignacion devolucion)a

  @doc "Carga el archivo o inicia vacío solamente cuando todavía no existe."
  def cargar(directorio) do
    ruta = Path.join(directorio, "estado.txt")

    case File.stat(ruta) do
      {:error, :enoent} ->
        {:ok, Datos.nuevo()}

      {:error, razon} ->
        {:error, {:lectura, razon}}

      {:ok, _} ->
        ruta
        |> File.stream!()
        |> Stream.map(&String.trim_trailing(&1, "\n"))
        |> Stream.map(&String.trim_trailing(&1, "\r"))
        |> Stream.reject(&(&1 == ""))
        |> decodificar_lineas()
    end
  rescue
    error in File.Error -> {:error, {:lectura, error.reason}}
  end

  @doc "Guarda antes de confirmar una operación al cliente."
  def guardar(directorio, datos) do
    ruta = Path.join(directorio, "estado.txt")
    temporal = ruta <> ".tmp"

    with :ok <- File.mkdir_p(directorio),
         :ok <- copia_anterior(ruta),
         :ok <- File.write(temporal, codificar(datos)),
         :ok <- File.rename(temporal, ruta) do
      :ok
    else
      {:error, razon} -> {:error, {:escritura, razon}}
    end
  end

  defp copia_anterior(ruta) do
    case File.copy(ruta, ruta <> ".bak") do
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Convierte todas las tablas a líneas de texto con columnas conocidas."
  def codificar(datos) do
    lineas =
      Enum.flat_map(@tablas, fn {tabla, forma, _, campos} ->
        registros =
          if forma == :mapa,
            do: datos[tabla] |> Map.values() |> Enum.sort_by(&inspect/1),
            else: Enum.reverse(datos[tabla])

        Enum.map(registros, fn r ->
          valores =
            Enum.map(campos, fn {campo, tipo} ->
              convertir(Map.get(r, campo), tipo) |> escapar()
            end)

          Enum.join([to_string(tabla) | valores], "\t")
        end)
      end)

    Enum.join(["EMERGENCIAS\t1", "secuencia\t#{datos.secuencia}" | lineas], "\n") <> "\n"
  end

  defp convertir(valor, :conjunto), do: valor |> MapSet.to_list() |> Enum.sort() |> Enum.join(",")
  defp convertir(valor, _), do: to_string(valor)

  defp escapar(valor) do
    valor
    |> String.replace("%", "%25")
    |> String.replace("\t", "%09")
    |> String.replace("\r", "%0D")
    |> String.replace("\n", "%0A")
  end

  defp desescapar(valor) do
    valor
    |> String.replace("%09", "\t")
    |> String.replace("%0D", "\r")
    |> String.replace("%0A", "\n")
    |> String.replace("%25", "%")
  end

  @doc "Rechaza formatos o valores inválidos; nunca ejecuta el contenido."
  def decodificar(texto) do
    texto
    |> String.split("\n", trim: true)
    |> Stream.map(&String.trim_trailing(&1, "\r"))
    |> decodificar_lineas()
  end

  # El flujo se consume una sola vez: cabecera, secuencia y registros.
  defp decodificar_lineas(lineas) do
    resultado =
      Enum.reduce_while(lineas, {:cabecera, Datos.nuevo()}, fn linea, {paso, actual} ->
        case procesar_linea(linea, paso, actual) do
          {:ok, siguiente, nuevos} -> {:cont, {siguiente, nuevos}}
          error -> {:halt, error}
        end
      end)

    case resultado do
      {:registros, nuevos} ->
        if consistente?(nuevos), do: {:ok, nuevos}, else: {:error, :datos_inconsistentes}

      {:error, _} = error ->
        error

      _ ->
        {:error, :archivo_invalido}
    end
  end

  defp procesar_linea("EMERGENCIAS\t1", :cabecera, datos), do: {:ok, :secuencia, datos}

  defp procesar_linea("secuencia\t" <> numero, :secuencia, datos) do
    case Integer.parse(numero) do
      {n, ""} when n >= 0 -> {:ok, :registros, %{datos | secuencia: n}}
      _ -> {:error, :archivo_invalido}
    end
  end

  defp procesar_linea(linea, :registros, datos) do
    case cargar_linea(String.split(linea, "\t"), datos) do
      {:ok, nuevos} -> {:ok, :registros, nuevos}
      error -> error
    end
  end

  defp procesar_linea(_, _, _), do: {:error, :archivo_invalido}

  defp cargar_linea([nombre | valores], datos) do
    case Enum.find(@tablas, fn {tabla, _, _, _} -> to_string(tabla) == nombre end) do
      nil ->
        {:error, :tabla_desconocida}

      {tabla, forma, llave, campos} when length(campos) == length(valores) ->
        pares = Enum.zip(campos, valores)

        resultado =
          Enum.reduce_while(pares, {:ok, %{}}, fn {{campo, tipo}, valor}, {:ok, r} ->
            case interpretar(desescapar(valor), tipo) do
              {:ok, dato} -> {:cont, {:ok, Map.put(r, campo, dato)}}
              error -> {:halt, error}
            end
          end)

        case resultado do
          {:ok, r} ->
            r = restaurar_modelo(tabla, r)

            repetido =
              if forma == :mapa,
                do: Map.has_key?(datos[tabla], Map.get(r, llave)),
                else: Enum.any?(datos[tabla], &(Map.get(&1, llave) == Map.get(r, llave)))

            if repetido do
              {:error, :identificador_repetido_en_archivo}
            else
              registros =
                if forma == :mapa,
                  do: Map.put(datos[tabla], Map.get(r, llave), r),
                  else: [r | datos[tabla]]

              {:ok, Map.put(datos, tabla, registros)}
            end

          error ->
            error
        end

      _ ->
        {:error, :columnas_invalidas}
    end
  end

  defp restaurar_modelo(:zonas, r), do: struct(Emergencias.Zona, r)
  defp restaurar_modelo(:necesidades, r), do: struct(Emergencias.Necesidad, r)
  defp restaurar_modelo(_, r), do: r
  defp interpretar(valor, :texto), do: {:ok, valor}

  defp interpretar(valor, :entero) do
    case Integer.parse(valor) do
      {n, ""} when n >= 0 -> {:ok, n}
      _ -> {:error, :numero_invalido}
    end
  end

  defp interpretar("true", :boolean), do: {:ok, true}
  defp interpretar("false", :boolean), do: {:ok, false}

  defp interpretar(valor, :atomo) do
    case Enum.find(@atomos, &(to_string(&1) == valor)) do
      nil -> {:error, :opcion_invalida}
      opcion -> {:ok, opcion}
    end
  end

  defp interpretar(valor, :conjunto), do: {:ok, MapSet.new(String.split(valor, ",", trim: true))}
  defp interpretar(_, _), do: {:error, :valor_invalido}

  # Se comprueban las relaciones que pueden invalidar inventario o cupos al reiniciar.
  defp consistente?(d) do
    Enum.all?(d.existencias, fn {_, e} ->
      Map.has_key?(d.recursos, e.codigo) and Map.has_key?(d.centros, e.centro)
    end) and
      Enum.all?(d.centros, fn {_, c} -> Map.has_key?(d.zonas, c.zona) end) and
      Enum.all?(d.necesidades, fn {_, n} ->
        n.cantidad > 0 and n.asignada <= n.cantidad and Map.has_key?(d.zonas, n.zona)
      end) and
      Enum.all?(d.albergues, fn {codigo, a} ->
        MapSet.size(a.residentes) <= a.capacidad and
          Enum.all?(a.residentes, fn id -> match?(%{albergue: ^codigo}, d.personas[id]) end)
      end) and
      Enum.all?(d.personas, fn {id, p} ->
        p.albergue == "" or
          (Map.has_key?(d.albergues, p.albergue) and
             MapSet.member?(d.albergues[p.albergue].residentes, id))
      end)
  end
end
