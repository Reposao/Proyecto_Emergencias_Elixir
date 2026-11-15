# Comandos de la consola

Se escriben dentro del programa, después de ejecutar `ejecutar.bat` o `cliente.bat`.
Los textos que contienen espacios van entre comillas dobles. También se admite
`nombre="Ana Pérez"` en un filtro. Las cantidades y edades son números enteros.
Los estados se escriben con guion bajo y sin tildes.

## Usuarios

| Comando | Función |
|---|---|
| `connect admin 1234 administrador general "Administrador"` | Primera cuenta de la instalación. |
| `connect ana 1234 ciudadano centro "Ana Pérez"` | Registro automático de una cuenta ciudadana nueva. |
| `connect ana 1234` | Autenticación de una cuenta existente. |
| `set_role ana coordinador` | El administrador cambia el rol de Ana. |
| `list_users` | Administrador: datos públicos y conexiones actuales. |
| `activity ana` | Actividad propia; coordinadores y administradores pueden consultar otros usuarios. |
| `activity ""` | Coordinador o administrador: toda la actividad. |
| `disconnect` | Cierra la sesión; deja abierta la consola. |
| `exit` | Cierra la sesión y la consola. |
| `help` | Muestra ayuda. |

Para crear una cuenta con otro rol, primero se registra como ciudadana y el
administrador le asigna el rol. Una cuenta existente conserva su rol guardado,
independientemente del rol escrito en el comando de conexión.

## Zonas y centros

```text
register_zone centro "Zona Centro" critico 20
register_sector S01 "Sector 1" centro alto 10
register_point PTO1 "Punto médico" S01 medio 5
list_zones
zone_tree centro
zone_summary centro
register_center C01 "Acopio Centro" centro
register_center C02 "Inventario del punto" PTO1 punto -
list_centers
```

Niveles: `critico`, `alto`, `medio`, `bajo`. Una zona no tiene padre; un sector
depende de una zona y un punto depende de un sector. La cifra de afectados de cada
nodo se refiere solo a ese nodo: el resumen suma las cifras propias y las de sus hijos.

## Recursos

```text
register_resource R001 "Agua potable" agua 50 litros C01
list_resources
list_resources zona=centro categoria=agua
stock R001 C01 entrada 20 "Donación recibida"
stock R001 C01 salida 5 "Entrega directa documentada"
transfer_resource R001 C01 C02 10
movements R001
critical_resources 5
```

El código identifica el producto en el catálogo; cada existencia identifica el par
recurso-centro. La categoría debe corresponder al tipo de necesidad que se atenderá.
Las transferencias conservan el total. Una entrada puede crear la existencia de un
producto ya registrado en otro centro. `critical_resources` usa 5 como umbral por defecto.

## Necesidades

```text
register_need N001 agua 30 critica PTO1 "Agua para pacientes"
register_need N002 alimentos 10 alta centro "Alimentos para una familia" familia "Familia Ruiz"
register_need N003 agua 10 media centro "Agua para Ana" persona P001
register_need N004 agua 10 critica centro "Agua del albergue" albergue A01
list_needs
list_needs zona=centro tipo=agua prioridad=critica estado=pendiente
assign_resource N001 R001 C01 20
assign_resource N001 R001 C01 10
need_state N001 en_atencion
need_state N001 atendida
assign_priority R001 C01
pending_needs
```

Tipos: `agua`, `alimentos`, `medicamentos`, `primeros_auxilios`, `refugio`,
`transporte`, `rescate`, `otra`. Prioridades: `critica`, `alta`, `media`, `baja`.
Sin beneficiario explícito, se asocia a la zona indicada.
Los listados salen ordenados por prioridad e ID. `assign_priority` selecciona la
primera necesidad compatible y asigna hasta donde alcancen inventario y cantidad pendiente.

Para cancelar una reserva antes de iniciar la atención:

```text
need_state N002 cancelada
```

Se devuelven sus asignaciones una sola vez. La cantidad requerida debe estar
completa para pasar a `en_atencion`. Una necesidad atendida o cancelada no admite
asignaciones nuevas. Un ciudadano solo puede cancelar su propia necesidad.

## Personas y familiares

```text
report_person P001 DOC1001 "Andrés Ruiz" 24 centro localizada
find_person DOC1001
list_people nombre="Andrés" zona=centro
person_state P001 trasladada "Traslado al centro médico"
person_state P001 localizada "Llegó al centro médico"
person_history P001
send_family_message persona P001 "Estoy bien, voy al Albergue Norte"
send_family_message familia "Familia Ruiz" "Andrés fue localizado"
list_family_messages destinatario=P001
message_state MSG00001 entregado
```

El ID `MSG00001` es ilustrativo: usen el ID que muestre el programa al crear el
mensaje. Estados iniciales: `sin_informacion`, `reportada`, `localizada`, `trasladada`.
`en_albergue` se obtiene mediante el ingreso a un albergue y `reunificada` mediante
una transición válida. El documento o dato de referencia no se puede repetir.

## Mascotas

```text
report_pet M001 perdida perro "Luna" "Collar rojo" negra mediana centro "Familia Ruiz"
report_pet M002 encontrada perro "desconocido" "Collar rojo" negra mediana centro "Voluntario Ana"
list_pets especie=perro zona=centro
match_pets
pet_candidates
confirm_pets M001 M002
list_pets estado=resuelta
```

También se admiten `lost` y `found`. Se comparan especie, color, tamaño, zona,
nombre y características. La especie debe coincidir y se requieren 6 de 10 puntos.
La búsqueda marca coincidencias posibles; la confirmación humana cierra ambos
reportes conjuntamente. Un reporte cerrado no puede participar en otra confirmación.

## Albergues

```text
register_shelter A01 "Albergue Norte" centro 150
list_shelters
register_entry A01 P001
check_shelter A01
register_exit A01 P001
shelter_occupancy
summary
```

Al registrar un albergue se crea también su centro de inventario, con el mismo
código. Por eso se puede registrar o transferir un recurso hacia `A01`.
`check_shelter` incluye cupos, residentes, recursos y necesidades asociadas.
El estado de una persona alojada se cambia mediante ingreso/salida para mantener
consistente la ocupación.

## Filtros admitidos

| Listado | Campos |
|---|---|
| `list_resources` | codigo, categoria, centro, zona |
| `list_needs` | id, tipo, zona, prioridad, estado, responsable, destino_tipo, destino |
| `list_people` | id, nombre, documento, zona, estado |
| `list_family_messages` | destinatario, estado, tipo, remitente |
| `list_pets` | id, especie, zona, estado, tipo |

Los filtros se combinan con «y». `nombre` en personas permite coincidencia parcial
sin distinguir mayúsculas. Los otros filtros son exactos. Los códigos son sensibles
a mayúsculas y minúsculas.
