defmodule Emergencias.Sesion do
  @moduledoc """
  Proceso independiente de un usuario, escrito con spawn, send y receive.
  Solo acepta solicitudes del proceso cliente que inició la sesión.
  """
  @doc "Especificación que permite supervisar un proceso escrito a mano."
  def child_spec(argumentos) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [argumentos]}, restart: :temporary}
  end

  @doc "Inicia el buzón de una sesión y observa al cliente y al servidor."
  def start_link({duenio, servidor}) do
    pid =
      spawn_link(fn ->
        ref_cliente = Process.monitor(duenio)
        ref_servidor = Process.monitor(servidor)
        atender(duenio, servidor, ref_cliente, ref_servidor)
      end)

    {:ok, pid}
  end

  @doc "Solicita una operación y espera la respuesta identificada por una referencia."
  def solicitar(pid, operacion) when is_pid(pid) do
    referencia = make_ref()
    monitor = Process.monitor(pid)
    send(pid, {self(), referencia, operacion})

    receive do
      {^referencia, resultado} ->
        Process.demonitor(monitor, [:flush])
        resultado

      {:DOWN, ^monitor, :process, ^pid, _} ->
        {:error, :sesion_caducada_vuelva_a_conectar}
    after
      15_000 ->
        Process.demonitor(monitor, [:flush])
        {:error, :sesion_sin_respuesta_vuelva_a_conectar}
    end
  end

  def solicitar(_, _), do: {:error, :sesion_invalida}

  defp atender(duenio, servidor, ref_cliente, ref_servidor) do
    receive do
      {^duenio, referencia, operacion} ->
        resultado = pedir_al_servidor(servidor, operacion)
        send(duenio, {referencia, resultado})

        if operacion != :disconnect or not match?({:ok, _}, resultado),
          do: atender(duenio, servidor, ref_cliente, ref_servidor)

      {otro, referencia, _operacion} when is_pid(otro) and is_reference(referencia) ->
        send(otro, {referencia, {:error, :sesion_de_otro_cliente}})
        atender(duenio, servidor, ref_cliente, ref_servidor)

      {:DOWN, referencia, :process, _, _} when referencia in [ref_cliente, ref_servidor] ->
        :ok

      _ ->
        atender(duenio, servidor, ref_cliente, ref_servidor)
    end
  end

  defp pedir_al_servidor(servidor, operacion) do
    try do
      GenServer.call(servidor, {:operar, self(), operacion}, 12_000)
    catch
      :exit, _ -> {:error, :servidor_no_disponible_vuelva_a_conectar}
    end
  end
end
