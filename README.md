# Coordinación de emergencias en Elixir

Aplicación de consola para registrar usuarios, zonas, necesidades, recursos,
personas, mensajes familiares, mascotas y albergues. Usa procesos, GenServer,
supervisión y persistencia en texto plano.

## Requisitos

- Elixir 1.14 o posterior y Erlang/OTP.
- Windows para los lanzadores .bat.

La ejecución se comprobó con Elixir 1.19.5 y Erlang/OTP 28.
El proyecto no tiene dependencias externas.

## Ejecución

Abrir la carpeta que contiene mix.exs en Visual Studio Code y abrir una terminal.

```powershell
.\ejecutar.bat
```

Primera cuenta, dentro de la consola del programa:

```text
connect admin 1234 administrador general "Administrador"
help
```

El usuario y la contraseña son ejemplos de registro. Una cuenta existente
se conecta con sus credenciales guardadas:

```text
connect admin 1234
```

Los comandos completos, filtros y ejemplos están en [COMANDOS.md](COMANDOS.md).
El comando exit cierra la consola y disconnect cierra la sesión.

## Pruebas automáticas

```powershell
.\pruebas.bat
```

Equivale a mix.bat test. Las pruebas usan directorios temporales independientes.
Comprueban permisos, datos inválidos, inventario, prioridades, capacidad,
coincidencias, solicitudes concurrentes, archivos y recuperación del servidor.

## Demostración

```powershell
.\demostracion.bat
```

Ejecuta un recorrido de todas las áreas, con dos solicitudes concurrentes de
30 y 25 litros frente a 50 disponibles. Solo una se acepta. También comprueba
capacidad del albergue, cierre de mascotas y recuperación después de reiniciar.
Los datos del ejemplo quedan en una carpeta propia dentro de tmp.

## Servidor y clientes en terminales separadas

Desde la misma carpeta del proyecto:

1. Iniciar el servidor en una terminal:

```powershell
.\servidor.bat
```

2. Iniciar un cliente en otra terminal:

```powershell
.\cliente.bat
```

3. Ejecutar cliente.bat otra vez en una tercera terminal.

Cada cliente es un nodo independiente. Todos usan el servidor
emergencias_servidor@localhost y la misma cookie del lanzador.
El servidor se mantiene abierto durante las consultas.
Un solo servidor administra la carpeta datos.
El modo ejecutar.bat usa una consola local y su propio servidor; se ejecuta
por separado del modo servidor.bat sobre esa carpeta de datos.

### Comprobación de datos compartidos

En una instalación nueva, registrar desde el primer cliente:

```text
connect admin 1234 administrador general "Administrador"
register_zone red "Zona de prueba" critico 10
register_center C_RED "Acopio de prueba" red
register_resource R_RED "Agua" agua 50 litros C_RED
```

En el segundo cliente:

```text
connect cliente2 1234 ciudadano red "Segundo cliente"
list_resources codigo=R_RED
```

La consulta debe mostrar 50 litros. Desde el primer cliente:

```text
stock R_RED C_RED salida 10 "Entrega"
```

Al repetir la consulta en el segundo cliente, la cantidad debe ser 40.
Las cuentas y códigos ya existentes se conservan entre ejecuciones.

## Archivos y persistencia

- lib/emergencias: módulos de la aplicación.
- test: pruebas con ExUnit.
- scripts: demostración y comprobación entre nodos.
- datos/estado.txt: estado del sistema, generado durante la ejecución.
- datos/estado.txt.bak: estado anterior al último guardado.

El servidor carga el estado por líneas con File.stream! y guarda cada cambio
antes de confirmarlo. Las sesiones vuelven a autenticarse al reiniciar.
Los archivos compilados, datos de ejecución y temporales están excluidos de Git.
