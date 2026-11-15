defmodule Emergencias.Zona do
  @moduledoc "Nodo de la jerarquía zona, sector y punto de atención."

  defstruct codigo: "",
            nombre: "",
            tipo: :zona,
            padre: "",
            nivel: :bajo,
            afectados: 0,
            hijos: []

  @doc "Crea un nodo. Los hijos se construyen recursivamente al consultar el árbol."
  def crear(codigo, nombre, tipo, padre, nivel, afectados) do
    %__MODULE__{
      codigo: codigo,
      nombre: nombre,
      tipo: tipo,
      padre: padre,
      nivel: nivel,
      afectados: afectados
    }
  end
end

defmodule Emergencias.Necesidad do
  @moduledoc "Solicitud de ayuda y avance de la cantidad asignada."

  defstruct id: "",
            tipo: :otra,
            cantidad: 0,
            asignada: 0,
            zona: "",
            prioridad: :media,
            responsable: "",
            estado: :pendiente,
            descripcion: "",
            destino_tipo: :zona,
            destino: ""

  @doc "Crea una necesidad pendiente, todavía sin recursos asignados."
  def crear(id, tipo, cantidad, zona, prioridad, responsable, descripcion, destino_tipo, destino) do
    %__MODULE__{
      id: id,
      tipo: tipo,
      cantidad: cantidad,
      zona: zona,
      prioridad: prioridad,
      responsable: responsable,
      descripcion: descripcion,
      destino_tipo: destino_tipo,
      destino: destino
    }
  end

  defimpl String.Chars do
    def to_string(n) do
      "#{n.id}: #{n.tipo}, #{n.asignada}/#{n.cantidad}, #{n.prioridad}, #{n.estado}, #{n.zona}"
    end
  end
end
