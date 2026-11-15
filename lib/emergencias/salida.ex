defmodule Emergencias.Salida do
  @moduledoc "Da formato a los resultados de la consola sin modificar los datos."

  @campos [
    id: "ID",
    codigo: "Código",
    nombre: "Nombre",
    usuario: "Usuario",
    rol: "Rol",
    documento: "Documento",
    edad: "Edad",
    tipo: "Tipo",
    estado: "Estado",
    prioridad: "Prioridad",
    categoria: "Categoría",
    cantidad: "Cantidad",
    asignada: "Cantidad asignada",
    unidad: "Unidad",
    zona: "Zona",
    centro: "Centro",
    padre: "Zona o sector padre",
    nivel: "Nivel de emergencia",
    afectados: "Afectados",
    afectados_estimados: "Afectados estimados",
    nodos: "Zonas, sectores y puntos",
    descripcion: "Descripción",
    responsable: "Responsable",
    destino_tipo: "Tipo de beneficiario",
    destino: "Destino",
    capacidad: "Capacidad",
    ocupacion: "Ocupación",
    cupos: "Cupos disponibles",
    porcentaje: "Ocupación (%)",
    albergue: "Albergue",
    residentes: "Residentes",
    especie: "Especie",
    color: "Color",
    tamano: "Tamaño",
    caracteristicas: "Características",
    contacto: "Contacto",
    pareja: "Reporte relacionado",
    perdida: "Reporte de pérdida",
    encontrada: "Reporte de hallazgo",
    puntaje: "Puntaje",
    persona: "Persona",
    anterior: "Estado anterior",
    nuevo: "Nuevo estado",
    motivo: "Motivo",
    detalle: "Detalle",
    referencia: "Referencia",
    remitente: "Remitente",
    destinatario: "Destinatario",
    contenido: "Mensaje",
    fecha: "Fecha (UTC)",
    origen: "Origen",
    necesidad: "Necesidad",
    devuelta: "Devuelta",
    accion: "Acción",
    resultado: "Resultado",
    conexiones: "Conexiones",
    sesiones: "Sesiones",
    usuarios_conectados: "Usuarios conectados",
    usuarios: "Usuarios registrados",
    zonas: "Zonas registradas",
    personas: "Personas registradas",
    personas_localizadas: "Personas localizadas",
    necesidades_pendientes: "Necesidades pendientes",
    mascotas_activas: "Reportes de mascotas activos",
    mensajes_pendientes: "Mensajes pendientes",
    hijos: "Sectores y puntos",
    albergues: "Albergues",
    necesidades: "Necesidades",
    recursos: "Recursos",
    inventario: "Inventario"
  ]

  @errores %{
    inventario_insuficiente: "No hay inventario suficiente para esa cantidad.",
    albergue_lleno: "El albergue no tiene cupos disponibles.",
    persona_ya_alojada: "La persona ya se encuentra en un albergue.",
    reporte_ya_resuelto: "El reporte de la mascota ya fue resuelto.",
    codigo_repetido: "Ya existe un registro con ese código.",
    persona_repetida: "Ya existe una persona con ese ID o documento.",
    clave_incorrecta: "La contraseña es incorrecta.",
    sin_permiso: "El usuario no tiene permiso para realizar esta operación.",
    primero_use_connect: "Inicie sesión con el comando connect.",
    primero_cree_un_administrador: "La primera cuenta debe tener el rol administrador.",
    las_altas_nuevas_son_ciudadanas: "Las cuentas nuevas se registran como ciudadanas.",
    faltan_comillas_de_cierre: "Falta cerrar las comillas del texto.",
    se_esperaba_un_entero: "La cantidad debe ser un número entero.",
    transicion_invalida: "El cambio de estado solicitado no está permitido.",
    faltan_recursos_por_asignar: "Todavía faltan recursos por asignar a la necesidad.",
    necesidad_no_asignable: "La necesidad ya no admite nuevas asignaciones.",
    no_se_pudo_conectar_al_nodo_servidor:
      "No se pudo conectar con el servidor. Compruebe que esté abierto.",
    inicie_el_cliente_con_sname: "Inicie el cliente mediante cliente.bat.",
    eacces: "Acceso denegado al archivo o al recurso.",
    enoent: "No se encontró el archivo.",
    desconectese_antes_de_cambiar_de_usuario: "Use disconnect antes de cambiar de usuario."
  }

  @doc "Convierte registros, listas y resultados simples en texto legible."
  def formatear(valor), do: valor |> lineas(2) |> Enum.join("\n")

  @doc "Entrega un título para una operación."
  def titulo(nil), do: "Resultado"
  def titulo(:resumen), do: "Resumen general"
  def titulo(:disconnect), do: "Cierre de sesión"
  def titulo(accion), do: nombre(accion)

  @doc "Explica el motivo de un error esperado sin imprimir una traza."
  def error({:persistencia, razon}),
    do: "No se pudo guardar la información. " <> error(razon)

  def error({:lectura, razon}),
    do: "Error de lectura. " <> error(razon)

  def error({:escritura, razon}),
    do: "Error de escritura. " <> error(razon)

  def error(razon) when is_atom(razon),
    do: Map.get(@errores, razon, nombre(razon) <> ".")

  def error(razon), do: texto(razon)

  defp lineas([], nivel),
    do: [espacios(nivel) <> "No hay registros."]

  defp lineas(lista, nivel) when is_list(lista) do
    registros =
      lista
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {registro, numero} ->
        [espacios(nivel) <> "Registro #{numero}" | lineas(registro, nivel + 2)] ++ [""]
      end)

    registros ++ [espacios(nivel) <> "Total de registros: #{length(lista)}"]
  end

  defp lineas(%MapSet{} = conjunto, nivel),
    do: [espacios(nivel) <> texto(conjunto)]

  defp lineas(mapa, nivel) when is_map(mapa) do
    mapa
    |> Map.drop([:__struct__, :sal, :clave_hash, :clave, :contrasena])
    |> Enum.sort_by(fn {clave, _} ->
      {
        Enum.find_index(@campos, fn {campo, _} -> campo == clave end) ||
          length(@campos),
        to_string(clave)
      }
    end)
    |> Enum.flat_map(&campo(&1, nivel))
  end

  defp lineas(valor, nivel),
    do: [espacios(nivel) <> texto(valor)]

  defp campo({clave, %MapSet{} = valor}, nivel),
    do: [espacios(nivel) <> etiqueta(clave) <> ": " <> texto(valor)]

  defp campo({clave, []}, nivel),
    do: [espacios(nivel) <> etiqueta(clave) <> ": Sin registros"]

  defp campo({clave, valor}, nivel) when is_map(valor) or is_list(valor),
    do: [espacios(nivel) <> etiqueta(clave) <> ":" | lineas(valor, nivel + 2)]

  defp campo({clave, valor}, nivel) do
    contenido =
      texto(valor)
      |> String.replace("\n", "\n" <> espacios(nivel + 2))

    [espacios(nivel) <> etiqueta(clave) <> ": " <> contenido]
  end

  defp etiqueta(clave),
    do: Keyword.get(@campos, clave, nombre(clave))

  defp espacios(cantidad),
    do: String.duplicate(" ", cantidad)

  defp nombre(valor) do
    valor
    |> to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp texto(nil), do: "Sin dato"
  defp texto(""), do: "Sin dato"
  defp texto(true), do: "Sí"
  defp texto(false), do: "No"
  defp texto(:desconectado), do: "Sesión cerrada."
  defp texto(:critico), do: "Crítico"
  defp texto(:critica), do: "Crítica"
  defp texto(:en_atencion), do: "En atención"
  defp texto(:sin_informacion), do: "Sin información"
  defp texto(:posible_coincidencia), do: "Posible coincidencia"

  defp texto(valor) when is_binary(valor),
    do: String.replace(valor, "\t", "  ")

  defp texto(valor) when is_atom(valor),
    do: nombre(valor)

  defp texto(valor) when is_float(valor),
    do: valor |> Float.round(2) |> to_string()

  defp texto(%MapSet{} = conjunto) do
    if MapSet.size(conjunto) == 0 do
      "Sin residentes"
    else
      conjunto
      |> MapSet.to_list()
      |> Enum.sort()
      |> Enum.join(", ")
    end
  end

  defp texto(valor) when is_tuple(valor),
    do: valor |> Tuple.to_list() |> Enum.map_join(" - ", &texto/1)

  defp texto(valor), do: to_string(valor)
end
