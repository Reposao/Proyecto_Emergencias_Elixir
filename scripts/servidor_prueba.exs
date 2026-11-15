# Servidor aislado para comprobar dos nodos. No modifica datos/.
Application.put_env(:emergencias, :directorio, Path.expand("tmp/prueba_nodos"))
{:ok, _} = Application.ensure_all_started(:emergencias)
IO.puts("SERVIDOR_DISTRIBUIDO_LISTO")

receive do
  :terminar -> :ok
after
  120_000 -> :ok
end
