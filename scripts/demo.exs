defmodule Demostracion do
  @moduledoc "Recorrido automático con datos propios; no cambia la carpeta datos del uso normal."

  alias Emergencias.{Servidor, Sesion, Util2}

  def ejecutar do
    carpeta = Path.expand("tmp/demo_#{System.os_time(:millisecond)}")
    {:ok, servidor} = Servidor.start_link(nombre: nil, directorio: carpeta)

    {:ok, admin, _} =
      Servidor.conectar(
        "admin",
        "1234",
        "Administrador",
        :administrador,
        "general",
        servidor
      )

    IO.puts("\n=== 1. ZONAS Y CENTROS ===")

    pedir(admin, {:registrar_zona, "centro", "Zona Centro", :zona, "", :critico, 20})
    pedir(admin, {:registrar_zona, "S01", "Sector 1", :sector, "centro", :alto, 10})
    pedir(admin, {:registrar_zona, "PTO1", "Punto de atención", :punto, "S01", :alto, 5})
    pedir(admin, {:registrar_centro, "C01", "Acopio Centro", "centro", :acopio, ""})
    pedir(admin, {:registrar_albergue, "A01", "Albergue Norte", "centro", 1})
    pedir(admin, {:registrar_recurso, "R001", "Agua", "agua", 50, "litros", "C01"})

    IO.puts("\n=== 2. USUARIOS Y CONCURRENCIA: 50 LITROS, SOLICITUDES DE 30 Y 25 ===")

    Enum.each([{"laura", "Laura"}, {"mario", "Mario"}], fn {usuario, nombre} ->
      {:ok, sesion, _} =
        Servidor.conectar(
          usuario,
          "1234",
          nombre,
          :ciudadano,
          "centro",
          servidor
        )

      pedir(admin, {:cambiar_rol, usuario, :coordinador})
      pedir(sesion, :disconnect)
    end)

    pedir(
      admin,
      {:registrar_necesidad, "N001", :agua, 30, :critica, "PTO1",
       "Agua para el punto", :zona, "PTO1"}
    )

    pedir(
      admin,
      {:registrar_necesidad, "N002", :agua, 25, :alta, "centro",
       "Agua para una familia", :familia, "Familia Ruiz"}
    )

    padre = self()

    tareas =
      Enum.map([{"laura", "N001", 30}, {"mario", "N002", 25}], fn {u, id, cantidad} ->
        Task.async(fn ->
          {:ok, sesion, _} =
            Servidor.conectar(u, "1234", "", :ciudadano, "", servidor)

          send(padre, {:listo, self()})

          receive do
            :comenzar -> :ok
          after
            5_000 -> raise "No se pudo iniciar la prueba"
          end

          resultado =
            Sesion.solicitar(sesion, {:asignar, id, "R001", "C01", cantidad})

          Sesion.solicitar(sesion, :disconnect)
          {u, resultado}
        end)
      end)

    Enum.each(tareas, fn t ->
      receive do
        {:listo, pid} when pid == t.pid -> :ok
      after
        5_000 -> raise "Cliente ausente"
      end
    end)

    Enum.each(tareas, &send(&1.pid, :comenzar))
    respuestas = Enum.map(tareas, &Task.await(&1, 15_000))

    IO.puts("\nResultado de las solicitudes simultáneas:")

    Enum.each(respuestas, fn
      {usuario, {:ok, necesidad}} ->
        IO.puts(
          "  #{usuario}: solicitud aceptada, #{necesidad.asignada} litros asignados."
        )

      {usuario, {:error, razon}} ->
        IO.puts(
          "  #{usuario}: solicitud rechazada. #{Emergencias.Salida.error(razon)}"
        )
    end)

    1 = Enum.count(respuestas, fn {_, r} -> match?({:ok, _}, r) end)

    [{_, {:ok, atendida}}] =
      Enum.filter(respuestas, fn {_, r} -> match?({:ok, _}, r) end)

    pedir(admin, {:estado_necesidad, atendida.id, :en_atencion})
    pedir(admin, {:estado_necesidad, atendida.id, :atendida})

    [{_, {:error, :inventario_insuficiente}}] =
      Enum.filter(respuestas, fn {_, r} -> match?({:error, _}, r) end)

    IO.puts("CONCURRENCIA CORRECTA: se confirmó una solicitud, nunca 55 litros.")

    IO.puts("\n=== 3. PERSONAS, FAMILIARES Y ALBERGUES ===")

    pedir(
      admin,
      {:registrar_persona, "P001", "DOC1001", "Andrés Ruiz", 24, "centro", :localizada}
    )

    pedir(
      admin,
      {:registrar_persona, "P002", "DOC1002", "Ana Ruiz", 20, "centro", :reportada}
    )

    mensaje =
      pedir(
        admin,
        {:enviar_mensaje, :persona, "P001", "Estoy bien, voy al Albergue Norte"}
      )

    pedir(admin, {:estado_mensaje, mensaje.id, :entregado})

    pedir(
      admin,
      {:enviar_mensaje, :familia, "Familia Ruiz", "Andrés ya está localizado"}
    )

    pedir(admin, {:ingreso, "A01", "P001"})

    {:error, :albergue_lleno} =
      Sesion.solicitar(admin, {:ingreso, "A01", "P002"})

    IO.puts("CUPO CORRECTO: el albergue lleno rechazó el segundo ingreso.")

    pedir(admin, {:historial_persona, "P001"})
    pedir(admin, {:transferir, "R001", "C01", "A01", 5})

    pedir(
      admin,
      {:registrar_necesidad, "N003", :agua, 10, :critica, "centro",
       "Agua del albergue", :albergue, "A01"}
    )

    pedir(admin, {:consultar_albergue, "A01"})

    IO.puts("\n=== 4. MASCOTAS ===")

    pedir(
      admin,
      {:registrar_mascota, "M001", :perdida, "perro", "Luna",
       "Collar rojo", "negro", "mediano", "centro", "Contacto familia"}
    )

    pedir(
      admin,
      {:registrar_mascota, "M002", :encontrada, "perro", "desconocido",
       "Collar rojo", "negro", "mediano", "centro", "Contacto voluntario"}
    )

    pedir(admin, :coincidir_mascotas)
    pedir(admin, {:confirmar_mascotas, "M001", "M002"})

    {:error, :reporte_ya_resuelto} =
      Sesion.solicitar(admin, {:confirmar_mascotas, "M001", "M002"})

    IO.puts("CIERRE CORRECTO: ambos reportes se resolvieron una sola vez.")

    IO.puts("\n=== 5. RECURSIÓN, PRIORIDAD Y RESUMEN ===")

    %{afectados_estimados: 35} =
      pedir(admin, {:resumen_zona, "centro"})

    pedir(admin, :pendientes)
    pedir(admin, {:asignar_prioritaria, "R001", "A01"})
    pedir(admin, {:listar_recursos, %{}})

    resumen = pedir(admin, :resumen)

    pedir(admin, :disconnect)
    GenServer.stop(servidor)

    IO.puts("\n=== 6. REINICIO Y PERSISTENCIA ===")

    {:ok, restaurado} =
      Servidor.start_link(nombre: nil, directorio: carpeta)

    {:ok, sesion, _} =
      Servidor.conectar("admin", "1234", "", :ciudadano, "", restaurado)

    nuevo = pedir(sesion, :resumen)

    true = nuevo.personas == resumen.personas
    true = nuevo.inventario == resumen.inventario

    pedir(sesion, :disconnect)
    GenServer.stop(restaurado)

    IO.puts(
      "\nDEMOSTRACIÓN COMPLETA Y CORRECTA.\nDatos del ejemplo: #{carpeta}"
    )
  end

  defp pedir(sesion, operacion) do
    case Sesion.solicitar(sesion, operacion) do
      {:ok, valor} ->
        Util2.resultado({:ok, valor}, Emergencias.Dominio.accion(operacion))
        valor

      {:error, razon} ->
        raise "La demostración falló en #{inspect(operacion)}: #{inspect(razon)}"
    end
  end
end

Demostracion.ejecutar()
