defmodule Emergencias.Servidor do
  @moduledoc """
  GenServer que coordina las operaciones y mantiene sus invariantes.
  Validación, actualización y persistencia ocurren antes de atender el próximo mensaje.
  La interfaz y las sesiones viven en otros procesos, incluso en otros nodos.
  """
  use GenServer
  alias Emergencias.{Datos, Usuarios, Dominio, Persistencia}

  @doc "Inicia el servidor. Las opciones permiten usar un directorio aislado en pruebas."
  def start_link(opciones) do
    nombre = Keyword.get(opciones, :nombre, __MODULE__)
    registro = if is_nil(nombre), do: [], else: [name: nombre]
    GenServer.start_link(__MODULE__, opciones, registro)
  end

  @doc "Registra o autentica y entrega el PID de una sesión del cliente llamador."
  def conectar(usuario, clave, nombre, rol, zona, servidor \\ __MODULE__) do
    try do
      GenServer.call(servidor, {:connect, usuario, clave, nombre, rol, zona}, 15_000)
    catch
      :exit, _ -> {:error, :servidor_no_disponible}
    end
  end

  @impl true
  def init(opciones) do
    directorio =
      Keyword.get(
        opciones,
        :directorio,
        Application.get_env(:emergencias, :directorio, Path.expand("datos"))
      )

    case Persistencia.cargar(directorio) do
      {:ok, datos} ->
        {:ok, %{datos: datos, directorio: directorio, sesiones: %{}, monitores: %{}}}

      {:error, razon} ->
        {:stop, {:no_se_pudo_cargar_el_archivo, razon}}
    end
  end

  @impl true
  def handle_call({:connect, usuario, clave, nombre, rol, zona}, {cliente, _}, estado) do
    case Usuarios.conectar(estado.datos, usuario, clave, nombre, rol, zona) do
      {:error, razon} ->
        {:reply, {:error, razon}, estado}

      {:ok, registro, datos} ->
        datos = Datos.actividad(datos, usuario, :connect, "ok")

        case Persistencia.guardar(estado.directorio, datos) do
          {:error, razon} ->
            {:reply, {:error, {:persistencia, razon}}, estado}

          :ok ->
            nuevos = %{estado | datos: datos}

            case DynamicSupervisor.start_child(
                   Emergencias.SupervisorSesiones,
                   {Emergencias.Sesion, {cliente, self()}}
                 ) do
              {:ok, pid} ->
                ref = Process.monitor(pid)

                nuevos = %{
                  nuevos
                  | sesiones: Map.put(nuevos.sesiones, pid, usuario),
                    monitores: Map.put(nuevos.monitores, ref, pid)
                }

                {:reply, {:ok, pid, Usuarios.publico(registro)}, nuevos}

              {:error, _} ->
                {:reply, {:error, :no_se_pudo_iniciar_la_sesion}, nuevos}
            end
        end
    end
  end

  def handle_call({:operar, sesion, operacion}, {remitente, _}, estado) do
    case Map.fetch(estado.sesiones, sesion) do
      {:ok, usuario} when remitente == sesion ->
        atender_autenticado(estado, sesion, usuario, operacion)

      _ ->
        {:reply, {:error, :sesion_no_autenticada}, estado}
    end
  end

  def handle_call(_, _, estado), do: {:reply, {:error, :solicitud_invalida}, estado}

  defp atender_autenticado(estado, sesion, usuario, :disconnect) do
    datos = Datos.actividad(estado.datos, usuario, :disconnect, "ok")

    case Persistencia.guardar(estado.directorio, datos) do
      :ok ->
        {:reply, {:ok, :desconectado},
         %{estado | datos: datos, sesiones: Map.delete(estado.sesiones, sesion)}}

      {:error, razon} ->
        {:reply, {:error, {:persistencia, razon}}, estado}
    end
  end

  defp atender_autenticado(estado, _sesion, usuario, operacion) do
    resultado = ejecutar_seguro(estado.datos, estado.datos.usuarios[usuario], operacion)

    {respuesta, datos} =
      case resultado do
        {:ok, valor, nuevos} -> {{:ok, decorar(valor, operacion, estado)}, nuevos}
        {:error, razon} -> {{:error, razon}, estado.datos}
      end

    etiqueta = if match?({:ok, _}, respuesta), do: "ok", else: "error"
    datos = Datos.actividad(datos, usuario, Dominio.accion(operacion), etiqueta)

    case Persistencia.guardar(estado.directorio, datos) do
      :ok -> {:reply, respuesta, %{estado | datos: datos}}
      {:error, razon} -> {:reply, {:error, {:persistencia, razon}}, estado}
    end
  end

  # Los comandos de consola ya validan tipos. Esta última barrera evita que una
  # solicitud mal formada enviada directamente por otro nodo termine el servidor.
  defp ejecutar_seguro(datos, usuario, operacion) do
    try do
      Dominio.ejecutar(datos, usuario, operacion)
    rescue
      ArgumentError -> {:error, :argumentos_invalidos}
      FunctionClauseError -> {:error, :argumentos_invalidos}
      Protocol.UndefinedError -> {:error, :argumentos_invalidos}
    end
  end

  defp decorar(resumen, :resumen, estado) do
    Map.merge(resumen, %{
      sesiones: map_size(estado.sesiones),
      usuarios_conectados: estado.sesiones |> Map.values() |> Enum.uniq() |> length()
    })
  end

  defp decorar(usuarios, :listar_usuarios, estado) do
    Enum.map(usuarios, fn u ->
      Map.put(
        u,
        :conexiones,
        Enum.count(estado.sesiones, fn {_, nombre} -> nombre == u.usuario end)
      )
    end)
  end

  defp decorar(valor, _, _), do: valor

  @impl true
  def handle_info({:DOWN, referencia, :process, _pid, _razon}, estado) do
    {sesion, monitores} = Map.pop(estado.monitores, referencia)
    {usuario, sesiones} = Map.pop(estado.sesiones, sesion)
    nuevos = %{estado | sesiones: sesiones, monitores: monitores}

    if usuario do
      datos = Datos.actividad(estado.datos, usuario, :desconexion_inesperada, "ok")

      case Persistencia.guardar(estado.directorio, datos) do
        :ok -> {:noreply, %{nuevos | datos: datos}}
        {:error, _} -> {:noreply, nuevos}
      end
    else
      {:noreply, nuevos}
    end
  end

  def handle_info(_, estado), do: {:noreply, estado}
end
