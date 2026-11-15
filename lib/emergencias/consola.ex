defmodule Emergencias.Consola do
  @moduledoc "Cliente de texto local o distribuido. La sesión conserva su dueño en este proceso."

  alias Emergencias.{Comandos, Dominio, Sesion, Servidor, Util2}

  @doc "Ejecuta la consola. Puede recibir {Servidor, nodo} como destino remoto."
  def main(servidor \\ Servidor) do
    case conectar_nodo(servidor) do
      :ok ->
        Util2.mostrar(
          "\nCOORDINACIÓN DE EMERGENCIAS - ELIXIR\nEscriba help para ver los comandos.\n",
          :mensaje
        )

        atender(%{servidor: servidor, sesion: nil})

      {:error, razon} ->
        Util2.resultado({:error, razon})
    end
  end

  defp conectar_nodo({_modulo, nodo}) do
    case Node.connect(nodo) do
      true -> :ok
      false -> {:error, :no_se_pudo_conectar_al_nodo_servidor}
      :ignored -> {:error, :inicie_el_cliente_con_sname}
    end
  end

  defp conectar_nodo(_), do: :ok

  defp atender(estado) do
    pregunta = if estado.sesion, do: "emergencias> ", else: "sin sesión> "

    case Util2.ingresar(pregunta, :texto) do
      :fin ->
        cerrar(estado)

      {:ok, linea} ->
        case Comandos.interpretar(linea) do
          {:ok, :salir} ->
            cerrar(estado)

          {:ok, :vacio} ->
            atender(estado)

          {:ok, :ayuda} ->
            ayuda()
            atender(estado)

          {:ok, {:connect, u, p, n, rol, zona}} ->
            if estado.sesion do
              Util2.resultado({:error, :desconectese_antes_de_cambiar_de_usuario})
              atender(estado)
            else
              case Servidor.conectar(u, p, n, rol, zona, estado.servidor) do
                {:ok, pid, usuario} ->
                  Util2.mostrar(
                    "Conectado: #{usuario.nombre} (#{usuario.rol})",
                    :mensaje
                  )

                  atender(%{estado | sesion: pid})

                error ->
                  Util2.resultado(error)
                  atender(estado)
              end
            end

          {:ok, operacion} ->
            if is_nil(estado.sesion) do
              Util2.resultado({:error, :primero_use_connect})
              atender(estado)
            else
              resultado = Sesion.solicitar(estado.sesion, operacion)
              Util2.resultado(resultado, Dominio.accion(operacion))

              nuevo =
                if (operacion == :disconnect and match?({:ok, _}, resultado)) or
                     sesion_perdida?(resultado) do
                  %{estado | sesion: nil}
                else
                  estado
                end

              atender(nuevo)
            end

          error ->
            Util2.resultado(error)
            atender(estado)
        end
    end
  end

  defp sesion_perdida?({:error, razon}) do
    razon in [
      :sesion_caducada_vuelva_a_conectar,
      :servidor_no_disponible_vuelva_a_conectar,
      :sesion_sin_respuesta_vuelva_a_conectar,
      :sesion_no_autenticada
    ]
  end

  defp sesion_perdida?(_), do: false

  defp cerrar(%{sesion: nil}) do
    Util2.mostrar("Consola finalizada.", :mensaje)
  end

  defp cerrar(estado) do
    Sesion.solicitar(estado.sesion, :disconnect)
    Util2.mostrar("Sesión cerrada. Los datos quedaron guardados.", :mensaje)
  end

  @doc "Muestra los formatos admitidos; COMANDOS.md incluye ejemplos completos."
  def ayuda do
    Util2.mostrar(
      """
      Texto con espacios: entre comillas dobles. Cantidades: enteros.
      PRIMER USO: connect admin 1234 administrador general "Administrador"
      Otras altas: connect ana 1234 ciudadano centro "Ana Pérez"
      Existentes: connect ana 1234
      disconnect | exit | list_users | set_role usuario rol | activity usuario

      register_zone codigo "nombre" nivel afectados
      register_sector codigo "nombre" zona_padre nivel afectados
      register_point codigo "nombre" sector_padre nivel afectados
      list_zones | zone_tree codigo | zone_summary codigo
      register_center codigo "nombre" zona
      register_center codigo "nombre" punto punto -
      list_centers

      register_resource codigo "nombre" categoria cantidad unidad centro
      list_resources [zona=centro] [categoria=agua]
      stock codigo centro entrada|salida cantidad "motivo"
      transfer_resource codigo origen destino cantidad
      movements [codigo]
      register_need id tipo cantidad prioridad zona "descripción" [persona|familia|albergue destino]
      list_needs [zona=centro] [tipo=agua] [prioridad=critica] [estado=pendiente]
      assign_resource necesidad recurso centro cantidad
      assign_priority recurso centro
      need_state id en_atencion|atendida|cancelada
      pending_needs

      report_person id documento "nombre" edad zona estado
      list_people [nombre="Ana"] [documento=123] [zona=centro] [estado=localizada]
      find_person documento | person_history id
      person_state id estado "motivo"
      send_family_message persona|familia destinatario "contenido"
      list_family_messages [destinatario=P001] [estado=pendiente]
      message_state id pendiente|entregado

      report_pet id perdida|encontrada especie "nombre" "características" color tamaño zona "contacto"
      list_pets [especie=perro] [zona=centro] [estado=activa]
      match_pets | pet_candidates | confirm_pets perdida encontrada
      register_shelter codigo "nombre" zona capacidad
      list_shelters | check_shelter codigo | shelter_occupancy
      register_entry albergue persona | register_exit albergue persona
      summary | critical_resources [umbral]

      Roles: ciudadano, voluntario, coordinador, administrador.
      Niveles: critico, alto, medio, bajo. Prioridades: critica, alta, media, baja.
      Las necesidades permiten agua, alimentos, medicamentos, primeros_auxilios,
      refugio, transporte, rescate y otra.
      """,
      :mensaje
    )
  end
end
