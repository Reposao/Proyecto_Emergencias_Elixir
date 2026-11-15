defmodule EmergenciasTest do
  use ExUnit.Case
  alias Emergencias.{Servidor, Sesion, Persistencia, Comandos, Zonas}

  setup do
    carpeta =
      Path.join(
        System.tmp_dir!(),
        "emergencias_prueba_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    servidor = start_supervised!({Servidor, [nombre: nil, directorio: carpeta]})

    {:ok, sesion, _} =
      Servidor.conectar("admin", "1234", "Administrador", :administrador, "general", servidor)

    ok(sesion, {:registrar_zona, "centro", "Centro", :zona, "", :critico, 20})
    ok(sesion, {:registrar_centro, "C1", "Acopio principal", "centro", :acopio, ""})
    %{servidor: servidor, sesion: sesion, carpeta: carpeta}
  end

  defp ok(sesion, operacion) do
    assert {:ok, valor} = Sesion.solicitar(sesion, operacion)
    valor
  end

  defp recurso(s), do: ok(s, {:registrar_recurso, "R1", "Agua", "agua", 50, "litros", "C1"})

  defp necesidad(s, id, cantidad \\ 30, prioridad \\ :critica) do
    ok(
      s,
      {:registrar_necesidad, id, :agua, cantidad, prioridad, "centro", "Agua para familias",
       :zona, "centro"}
    )
  end

  defp persona(s, id \\ "P1", doc \\ "DOC1") do
    ok(s, {:registrar_persona, id, doc, "Ana Pérez", 24, "centro", :localizada})
  end

  defp mascota(s, id, tipo, color \\ "negro", especie \\ "perro") do
    ok(
      s,
      {:registrar_mascota, id, tipo, especie, "Luna", "Collar rojo", color, "mediano", "centro",
       "Contacto de prueba"}
    )
  end

  defp saldo(s, centro \\ "C1") do
    [r] = ok(s, {:listar_recursos, %{codigo: "R1", centro: centro}})
    r.cantidad
  end

  # Cada tarea inicia su propia sesión. La barrera permite liberar solicitudes
  # de procesos distintos cuando todos los clientes ya están preparados.
  defp simultaneos(servidor, operaciones) do
    padre = self()

    tareas =
      Enum.map(operaciones, fn operacion ->
        Task.async(fn ->
          {:ok, sesion, _} = Servidor.conectar("admin", "1234", "", :ciudadano, "", servidor)
          send(padre, {:preparado, self()})

          receive do
            :comenzar -> :ok
          after
            5_000 -> raise "No llegó la señal de inicio"
          end

          respuesta = Sesion.solicitar(sesion, operacion)
          Sesion.solicitar(sesion, :disconnect)
          respuesta
        end)
      end)

    Enum.each(tareas, fn tarea ->
      assert_receive {:preparado, pid} when pid == tarea.pid, 5_000
    end)

    Enum.each(tareas, &send(&1.pid, :comenzar))
    Enum.map(tareas, &Task.await(&1, 15_000))
  end

  test "alta automática, validación de contraseña y roles", c do
    assert {:ok, ciudadano, %{rol: :ciudadano}} =
             Servidor.conectar("ana", "5678", "Ana", :ciudadano, "centro", c.servidor)

    assert {:error, :clave_incorrecta} = Servidor.conectar("ana", "mal", "", nil, "", c.servidor)

    assert {:error, :las_altas_nuevas_son_ciudadanas} =
             Servidor.conectar(
               "intruso",
               "1234",
               "Intruso",
               :administrador,
               "general",
               c.servidor
             )

    assert {:error, :sin_permiso} =
             Sesion.solicitar(ciudadano, {:registrar_centro, "X", "X", "centro", :acopio, ""})

    ok(c.sesion, {:cambiar_rol, "ana", :coordinador})

    assert %{codigo: "C2"} =
             ok(ciudadano, {:registrar_centro, "C2", "Otro", "centro", :acopio, ""})

    usuarios = ok(c.sesion, :listar_usuarios)
    refute Enum.any?(usuarios, &Map.has_key?(&1, :clave_hash))
    assert Enum.find(usuarios, &(&1.usuario == "ana")).conexiones == 1
    ok(ciudadano, :disconnect)
    assert Enum.find(ok(c.sesion, :listar_usuarios), &(&1.usuario == "ana")).conexiones == 0
  end

  test "primera cuenta administradora y último administrador protegido" do
    datos = Emergencias.Datos.nuevo()

    assert {:error, :primero_cree_un_administrador} =
             Emergencias.Usuarios.conectar(datos, "a", "1234", "A", :ciudadano, "general")
  end

  test "no se degrada al único administrador", c do
    assert {:error, :debe_quedar_un_administrador} =
             Sesion.solicitar(c.sesion, {:cambiar_rol, "admin", :ciudadano})
  end

  test "un tercero no reutiliza el PID de una sesión ajena", c do
    tarea = Task.async(fn -> Sesion.solicitar(c.sesion, :resumen) end)
    assert {:error, :sesion_de_otro_cliente} = Task.await(tarea)

    assert {:error, :sesion_no_autenticada} =
             GenServer.call(c.servidor, {:operar, c.sesion, :resumen})

    assert %{zonas: 1} = ok(c.sesion, :resumen)
  end

  test "jerarquía y estadística recursivas", c do
    ok(c.sesion, {:registrar_zona, "S1", "Sector", :sector, "centro", :alto, 10})
    ok(c.sesion, {:registrar_zona, "PTO1", "Punto", :punto, "S1", :medio, 5})
    arbol = ok(c.sesion, {:arbol_zona, "centro"})
    assert Zonas.total_afectados(arbol) == 35
    assert Zonas.codigos(arbol) == ["centro", "S1", "PTO1"]
    assert %{afectados_estimados: 35, nodos: 3} = ok(c.sesion, {:resumen_zona, "centro"})

    assert {:error, :jerarquia_invalida} =
             Sesion.solicitar(
               c.sesion,
               {:registrar_zona, "mal", "Mal", :punto, "centro", :bajo, 0}
             )

    assert {:error, :codigo_repetido} =
             Sesion.solicitar(
               c.sesion,
               {:registrar_zona, "S1", "Duplicado", :sector, "centro", :bajo, 0}
             )
  end

  test "inventario, entradas, salidas, transferencias e historial", c do
    recurso(c.sesion)
    ok(c.sesion, {:registrar_centro, "C2", "Segundo", "centro", :acopio, ""})
    ok(c.sesion, {:mover_recurso, "R1", "C1", :entrada, 10, "Donación"})
    ok(c.sesion, {:mover_recurso, "R1", "C1", :salida, 5, "Entrega directa"})
    ok(c.sesion, {:transferir, "R1", "C1", "C2", 20})
    assert saldo(c.sesion) == 35
    assert saldo(c.sesion, "C2") == 20
    assert length(ok(c.sesion, {:historial_movimientos, "R1"})) == 4

    assert {:error, :inventario_insuficiente} =
             Sesion.solicitar(c.sesion, {:transferir, "R1", "C1", "C2", 99})

    assert saldo(c.sesion) + saldo(c.sesion, "C2") == 55

    assert {:error, :centro_no_existe} =
             Sesion.solicitar(c.sesion, {:transferir, "R1", "C1", "NO", 1})
  end

  test "rechazo de cantidades y códigos inválidos", c do
    assert {:error, :datos_recurso_invalidos} =
             Sesion.solicitar(
               c.sesion,
               {:registrar_recurso, "R1", "Agua", "agua", -1, "litros", "C1"}
             )

    recurso(c.sesion)

    assert {:error, :codigo_repetido} =
             Sesion.solicitar(
               c.sesion,
               {:registrar_recurso, "R1", "Agua", "agua", 4, "litros", "C1"}
             )

    for n <- [-3, 0] do
      assert {:error, :movimiento_invalido} =
               Sesion.solicitar(c.sesion, {:mover_recurso, "R1", "C1", :salida, n, "Inválido"})
    end

    assert saldo(c.sesion) == 50
  end

  test "asignación parcial, transiciones y cierre sin doble consumo", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N1")
    assert %{asignada: 10} = ok(c.sesion, {:asignar, "N1", "R1", "C1", 10})

    assert {:error, :faltan_recursos_por_asignar} =
             Sesion.solicitar(c.sesion, {:estado_necesidad, "N1", :en_atencion})

    ok(c.sesion, {:asignar, "N1", "R1", "C1", 20})
    ok(c.sesion, {:estado_necesidad, "N1", :en_atencion})
    ok(c.sesion, {:estado_necesidad, "N1", :atendida})

    assert {:error, :necesidad_no_asignable} =
             Sesion.solicitar(c.sesion, {:asignar, "N1", "R1", "C1", 1})

    assert {:error, :transicion_invalida} =
             Sesion.solicitar(c.sesion, {:estado_necesidad, "N1", :atendida})

    assert saldo(c.sesion) == 20
  end

  test "cancelar devuelve reservas una sola vez", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N1")
    ok(c.sesion, {:asignar, "N1", "R1", "C1", 20})
    ok(c.sesion, {:estado_necesidad, "N1", :cancelada})
    assert saldo(c.sesion) == 50

    assert {:error, :transicion_invalida} =
             Sesion.solicitar(c.sesion, {:estado_necesidad, "N1", :cancelada})

    assert saldo(c.sesion) == 50
  end

  test "la prioridad decide qué solicitud recibe recursos", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N_BAJA", 10, :baja)
    necesidad(c.sesion, "N_CRITICA", 20, :critica)
    assert %{id: "N_CRITICA", asignada: 20} = ok(c.sesion, {:asignar_prioritaria, "R1", "C1"})
    assert %{id: "N_BAJA", asignada: 10} = ok(c.sesion, {:asignar_prioritaria, "R1", "C1"})
    assert [n1, n2] = ok(c.sesion, {:listar_necesidades, %{zona: "centro"}})
    assert {n1.id, n2.id} == {"N_CRITICA", "N_BAJA"}
  end

  test "30 y 25 simultáneos nunca consumen 55 cuando hay 50", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N1", 30)
    necesidad(c.sesion, "N2", 25)

    respuestas =
      simultaneos(c.servidor, [
        {:asignar, "N1", "R1", "C1", 30},
        {:asignar, "N2", "R1", "C1", 25}
      ])

    assert Enum.count(respuestas, &match?({:ok, _}, &1)) == 1
    assert Enum.count(respuestas, &(&1 == {:error, :inventario_insuficiente})) == 1
    asignados = ok(c.sesion, {:listar_necesidades, %{}}) |> Enum.map(& &1.asignada) |> Enum.sum()
    assert asignados + saldo(c.sesion) == 50
    assert saldo(c.sesion) in [20, 25]
  end

  test "dos asignaciones simultáneas a la misma necesidad no duplican su cantidad", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N1", 30)
    respuestas = simultaneos(c.servidor, List.duplicate({:asignar, "N1", "R1", "C1", 30}, 8))
    assert Enum.count(respuestas, &match?({:ok, _}, &1)) == 1
    assert saldo(c.sesion) == 20
  end

  test "personas, documento único, búsquedas e historial", c do
    persona(c.sesion)
    assert [%{id: "P1"}] = ok(c.sesion, {:listar_personas, %{nombre: "pérez"}})

    assert {:error, :persona_repetida} =
             Sesion.solicitar(
               c.sesion,
               {:registrar_persona, "P2", "DOC1", "Otra", 20, "centro", :reportada}
             )

    ok(c.sesion, {:estado_persona, "P1", :trasladada, "Traslado a centro médico"})
    ok(c.sesion, {:estado_persona, "P1", :reunificada, "Familia encontrada"})
    assert length(ok(c.sesion, {:historial_persona, "P1"})) == 3

    assert {:error, :transicion_invalida} =
             Sesion.solicitar(c.sesion, {:estado_persona, "P1", :reunificada, "Duplicado"})
  end

  test "mensajes a personas y familias con remitente, fecha y estado", c do
    persona(c.sesion)
    mensaje = ok(c.sesion, {:enviar_mensaje, :persona, "P1", "Estoy bien\nNos vemos\tpronto %09"})
    assert mensaje.remitente == "admin"
    assert mensaje.fecha != ""
    ok(c.sesion, {:estado_mensaje, mensaje.id, :entregado})
    ok(c.sesion, {:enviar_mensaje, :familia, "Familia Pérez", "Estoy en el centro"})
    assert [%{estado: :entregado}] = ok(c.sesion, {:listar_mensajes, %{destinatario: "P1"}})

    assert {:error, :persona_no_existe} =
             Sesion.solicitar(c.sesion, {:enviar_mensaje, :persona, "NO", "Hola"})
  end

  test "cupo, ingreso único, salida y asociación del albergue", c do
    persona(c.sesion)
    persona(c.sesion, "P2", "DOC2")
    ok(c.sesion, {:registrar_albergue, "A1", "Albergue", "centro", 1})
    assert %{ocupacion: 1, cupos: 0} = ok(c.sesion, {:ingreso, "A1", "P1"})
    assert {:error, :persona_ya_alojada} = Sesion.solicitar(c.sesion, {:ingreso, "A1", "P1"})
    assert {:error, :albergue_lleno} = Sesion.solicitar(c.sesion, {:ingreso, "A1", "P2"})

    assert {:error, :registre_primero_la_salida_del_albergue} =
             Sesion.solicitar(c.sesion, {:estado_persona, "P1", :reunificada, "Familia"})

    ok(c.sesion, {:registrar_recurso, "R_A", "Agua", "agua", 5, "litros", "A1"})

    ok(
      c.sesion,
      {:registrar_necesidad, "N_A", :agua, 10, :alta, "centro", "Agua albergue", :albergue, "A1"}
    )

    assert %{recursos: [_], necesidades: [_]} = ok(c.sesion, {:consultar_albergue, "A1"})
    ok(c.sesion, {:salida, "A1", "P1"})
    assert %{cupos: 0} = ok(c.sesion, {:ingreso, "A1", "P2"})
    assert {:error, :persona_no_alojada_aqui} = Sesion.solicitar(c.sesion, {:salida, "A1", "P1"})
  end

  test "el último cupo se asigna una sola vez ante solicitudes concurrentes", c do
    persona(c.sesion)
    persona(c.sesion, "P2", "DOC2")
    ok(c.sesion, {:registrar_albergue, "A1", "Albergue", "centro", 1})
    respuestas = simultaneos(c.servidor, [{:ingreso, "A1", "P1"}, {:ingreso, "A1", "P2"}])
    assert Enum.count(respuestas, &match?({:ok, _}, &1)) == 1
    assert Enum.count(respuestas, &(&1 == {:error, :albergue_lleno})) == 1
    assert %{albergue: %{ocupacion: 1, cupos: 0}} = ok(c.sesion, {:consultar_albergue, "A1"})
  end

  test "mascotas consideran varios atributos y cierran ambos reportes", c do
    mascota(c.sesion, "M1", :perdida)
    mascota(c.sesion, "M2", :encontrada)
    mascota(c.sesion, "M3", :encontrada, "negro", "gato")
    assert [%{perdida: "M1", encontrada: "M2", puntaje: 10}] = ok(c.sesion, :coincidir_mascotas)
    assert length(ok(c.sesion, {:listar_mascotas, %{estado: :posible_coincidencia}})) == 2
    ok(c.sesion, {:confirmar_mascotas, "M1", "M2"})
    assert length(ok(c.sesion, {:listar_mascotas, %{estado: :resuelta}})) == 2

    assert {:error, :reporte_ya_resuelto} =
             Sesion.solicitar(c.sesion, {:confirmar_mascotas, "M1", "M2"})

    assert [] = ok(c.sesion, :coincidencias)
  end

  test "confirmaciones simultáneas no resuelven dos veces una mascota", c do
    mascota(c.sesion, "M1", :perdida)
    mascota(c.sesion, "M2", :encontrada)
    mascota(c.sesion, "M3", :encontrada)

    respuestas =
      simultaneos(c.servidor, [
        {:confirmar_mascotas, "M1", "M2"},
        {:confirmar_mascotas, "M1", "M3"}
      ])

    assert Enum.count(respuestas, &match?({:ok, _}, &1)) == 1
    assert Enum.count(respuestas, &(&1 == {:error, :reporte_ya_resuelto})) == 1
  end

  test "persistencia de todas las tablas y caracteres especiales", c do
    recurso(c.sesion)
    necesidad(c.sesion, "N1")
    ok(c.sesion, {:asignar, "N1", "R1", "C1", 5})
    persona(c.sesion)
    mensaje = ok(c.sesion, {:enviar_mensaje, :persona, "P1", "Línea 1\nLínea 2\t100% %09"})
    ok(c.sesion, {:registrar_albergue, "A1", "Albergue", "centro", 2})
    ok(c.sesion, {:ingreso, "A1", "P1"})
    mascota(c.sesion, "M1", :perdida)
    mascota(c.sesion, "M2", :encontrada)
    ok(c.sesion, {:confirmar_mascotas, "M1", "M2"})
    assert {:ok, leido} = Persistencia.cargar(c.carpeta)
    assert leido.mensajes[mensaje.id].contenido == mensaje.contenido
    assert MapSet.member?(leido.albergues["A1"].residentes, "P1")
    assert leido.personas["P1"].albergue == "A1"
    assert leido.necesidades["N1"].asignada == 5
    assert length(leido.asignaciones) == 1
    assert length(leido.coincidencias) == 1
    assert {:ok, restaurado} = Persistencia.decodificar(Persistencia.codificar(leido))
    assert restaurado == leido
    refute File.read!(Path.join(c.carpeta, "estado.txt")) =~ "\t1234\t"
  end

  test "si falla la escritura no se confirma ni se modifica el dominio", c do
    recurso(c.sesion)
    temporal = Path.join(c.carpeta, "estado.txt.tmp")
    :ok = File.mkdir(temporal)

    assert {:error, {:persistencia, _}} =
             Sesion.solicitar(
               c.sesion,
               {:mover_recurso, "R1", "C1", :salida, 10, "No debe guardarse"}
             )

    :ok = File.rmdir(temporal)
    assert saldo(c.sesion) == 50
    assert {:ok, datos} = Persistencia.cargar(c.carpeta)
    assert length(datos.movimientos) == 1
  end

  test "archivo dañado se detecta sin ejecutarlo ni borrarlo" do
    assert {:error, :archivo_invalido} = Persistencia.decodificar("código que no se ejecuta")
    assert {:error, _} = Persistencia.decodificar("EMERGENCIAS\t1\nsecuencia\t0\nusuarios\tmal\n")
  end

  test "la carga por líneas admite CRLF y rechaza cabeceras incompletas", c do
    ruta = Path.join(c.carpeta, "estado.txt")
    original = File.read!(ruta)
    assert {:ok, esperado} = Persistencia.cargar(c.carpeta)
    File.write!(ruta, String.replace(original, "\n", "\r\n"))
    assert {:ok, ^esperado} = Persistencia.cargar(c.carpeta)

    for contenido <- ["", "EMERGENCIAS\t1\n", "EMERGENCIAS\t1\nsecuencia\tx\n"] do
      File.write!(ruta, contenido)
      assert {:error, :archivo_invalido} = Persistencia.cargar(c.carpeta)
      assert File.read!(ruta) == contenido
    end
  end

  test "comandos con comillas y validación de entradas" do
    assert {:ok, {:registrar_zona, "z", "Zona Centro", "zona", "", "alto", 3}} =
             Comandos.interpretar(~s(register_zone z "Zona Centro" alto 3))

    assert {:ok, {:listar_personas, %{nombre: "Ana Pérez"}}} =
             Comandos.interpretar(~s(list_people nombre="Ana Pérez"))

    assert {:error, :faltan_comillas_de_cierre} = Comandos.interpretar(~s(report_person "mal))

    assert {:error, :se_esperaba_un_entero} =
             Comandos.interpretar(~s(register_zone z "Zona" alto 3abc))

    assert {:error, _} = Comandos.interpretar("list_resources inexistente=x")
    assert {:error, _} = Comandos.interpretar("list_needs zona=centro zona=otra")
    assert {:error, _} = Comandos.interpretar("no_existe")
  end

  test "auditoría registra acciones exitosas y rechazadas", c do
    recurso(c.sesion)
    Sesion.solicitar(c.sesion, {:transferir, "R1", "C1", "NO", 2})
    actividad = ok(c.sesion, {:actividades, "admin"})
    assert Enum.any?(actividad, &(&1.accion == "registrar_recurso" and &1.resultado == "ok"))
    assert Enum.any?(actividad, &(&1.accion == "transferir" and &1.resultado == "error"))
    assert Enum.all?(actividad, &(&1.fecha != "" and &1.usuario == "admin"))
  end

  test "una solicitud mal formada no termina el servidor", c do
    assert {:error, :comando_o_argumentos_invalidos} = Sesion.solicitar(c.sesion, {%{}, 1})

    assert {:error, _} =
             Sesion.solicitar(c.sesion, {:registrar_persona, "X", %{}, [], -1, nil, nil})

    assert %{zonas: 1} = ok(c.sesion, :resumen)
  end

  test "una sesión cerrada avisa inmediatamente que debe reconectarse", c do
    ok(c.sesion, :disconnect)
    assert {:error, :sesion_caducada_vuelva_a_conectar} = Sesion.solicitar(c.sesion, :resumen)
  end
end

defmodule SupervisorPrueba do
  use Supervisor
  def start_link(opciones), do: Supervisor.start_link(__MODULE__, opciones)
  @impl true
  def init(opciones) do
    Supervisor.init([{Emergencias.Servidor, opciones}], strategy: :one_for_one)
  end
end

defmodule RecuperacionTest do
  use ExUnit.Case
  alias Emergencias.{Servidor, Sesion}

  test "un supervisor reinicia el servidor y recupera información del archivo" do
    carpeta =
      Path.join(
        System.tmp_dir!(),
        "emergencias_reinicio_#{System.os_time(:nanosecond)}_#{System.unique_integer([:positive])}"
      )

    start_supervised!(
      {SupervisorPrueba, [nombre: :servidor_prueba_reinicio, directorio: carpeta]}
    )

    anterior = Process.whereis(:servidor_prueba_reinicio)

    {:ok, sesion, _} =
      Servidor.conectar("admin", "1234", "Admin", :administrador, "general", anterior)

    assert {:ok, _} =
             Sesion.solicitar(sesion, {:registrar_zona, "z", "Zona", :zona, "", :alto, 10})

    referencia = Process.monitor(anterior)
    Process.exit(anterior, :kill)
    assert_receive {:DOWN, ^referencia, :process, ^anterior, :killed}, 3_000
    nuevo = esperar(anterior, 100)
    assert is_pid(nuevo) and nuevo != anterior
    {:ok, otra, _} = Servidor.conectar("admin", "1234", "", :ciudadano, "", nuevo)
    assert {:ok, [%{codigo: "z"}]} = Sesion.solicitar(otra, :listar_zonas)
  end

  defp esperar(_, 0), do: nil

  defp esperar(anterior, intentos) do
    case Process.whereis(:servidor_prueba_reinicio) do
      pid when is_pid(pid) and pid != anterior ->
        pid

      _ ->
        receive do
        after
          10 -> esperar(anterior, intentos - 1)
        end
    end
  end
end
