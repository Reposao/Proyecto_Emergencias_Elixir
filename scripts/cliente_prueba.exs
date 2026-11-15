nodo = :emergencias_prueba@localhost
true = Node.connect(nodo)

servidor = {Emergencias.Servidor, nodo}

{:ok, sesion, _} =
  Emergencias.Servidor.conectar(
    "admin_nodo",
    "1234",
    "Prueba entre nodos",
    :administrador,
    "general",
    servidor
  )

resultado = Emergencias.Sesion.solicitar(sesion, :resumen)

{:ok, %{usuarios: usuarios}} = resultado
true = usuarios >= 1

Emergencias.Util2.resultado(resultado, :resumen)

{:ok, :desconectado} =
  Emergencias.Sesion.solicitar(sesion, :disconnect)

IO.puts("PRUEBA_DISTRIBUIDA_CORRECTA")
