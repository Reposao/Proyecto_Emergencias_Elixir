defmodule Emergencias.Aplicacion do
  @moduledoc """
  Inicia los procesos del proyecto siguiendo el ejemplo de Application y Mix.
  El supervisor reinicia el servidor si falla; las sesiones son temporales.
  """
  use Application

  @impl true
  def start(_tipo, _argumentos) do
    hijos = [
      {DynamicSupervisor, name: Emergencias.SupervisorSesiones, strategy: :one_for_one},
      {Emergencias.Servidor, []}
    ]

    Supervisor.start_link(hijos, strategy: :one_for_one, name: Emergencias.Supervisor)
  end
end
