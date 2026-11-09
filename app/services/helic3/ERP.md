# Only Home — Integración con Siesa (ERP)

Módulo para consultar el ERP **Siesa** (cliente por cédula, facturas, estado de cuenta). Sigue
**puertos y adaptadores**: se define un **contrato** independiente del proveedor y se desarrolla
todo contra un **adaptador simulado**, de modo que conectar el API real de Siesa sea solo
configuración. Todo en open source, namespace `Helic3::Erp`, sin tocar `enterprise/`.

## Contrato (ERP-01) — `Helic3::Erp::Base`

Las implementaciones (simulada ERP-03, real ERP-05) heredan de `Base` e implementan:

| Método | Parámetros | Devuelve |
|---|---|---|
| `find_customer(cedula:)` | cédula del cliente | `Customer` o `nil` |
| `invoices(cedula:)` | cédula del cliente | `Array<Invoice>` |
| `invoice(number:)` | número de factura | `Invoice` o `nil` |
| `account_statement(cedula:)` | cédula del cliente | `AccountStatement` o `nil` |

El código que consume el ERP depende de `Base`, nunca de una implementación concreta.

## Objetos de valor (lo que devuelve cada consulta)

| Objeto | Campos |
|---|---|
| `Customer` | `cedula`, `nombre`, `email`, `telefono`, `ciudad`, `direccion` |
| `Invoice` | `numero`, `fecha`, `total`, `saldo`, `estado` (`pagada`/`pendiente`/`vencida`), `items` |
| `AccountStatement` | `cedula`, `saldo_total`, `facturas_pendientes`, `al_dia` |

## Contrato de adaptador (pruebas)

`spec/support/helic3/erp_adapter_contract.rb` define el shared example
`'un adaptador de ERP'`. Cualquier adaptador lo reutiliza para garantizar que cumple el contrato:

```ruby
subject(:adapter) { described_class.new }
let(:known_cedula) { '...' }
let(:known_invoice_number) { '...' }
it_behaves_like 'un adaptador de ERP'
```

## Configuración (ERP-16: Super Admin)

El modo y la conexión con Siesa se configuran en **Super Admin > Settings > Helic3 · ERP Siesa** (`/super_admin/app_config?config=helic3_erp`). Se guardan en `installation_configs` y se leen con `GlobalConfig`, igual que la llave de OpenAI (CFG-01). No hay respaldo en variables de entorno: es la única fuente de verdad. Al guardar la página se limpia la caché de `GlobalConfig`, así que el cambio aplica en la siguiente consulta, sin reiniciar.

`Helic3::Erp.adapter` es el interruptor del módulo; el **Modo del ERP** decide con quién se habla:

| Modo | Qué hace |
|---|---|
| `desactivado` (por defecto, o sin fila) | El ERP no responde; `habilitado?` es `false`. En producción nunca puede responder el simulado con clientes inventados: hay que encenderlo a propósito. |
| `simulado` | Usa `SimulatedAdapter` (datos de prueba). |
| `siesa` | Usa el adaptador real (ERP-05); exige toda la conexión de la tabla de abajo. |

Un valor desconocido levanta `Helic3::Erp::ConfiguracionInvalida`.

| Clave en `installation_configs` | Título en la página | Tipo |
|---|---|---|
| `HELIC3_ERP_MODO` | Modo del ERP | select (desactivado / simulado / siesa) |
| `HELIC3_SIESA_HUB_BASE_URL` | URL base de Siesa HUB | texto |
| `HELIC3_SIESA_HUB_CLIENT_ID` | Client ID (Apigee) | secreto |
| `HELIC3_SIESA_HUB_CONNI_KEY` | ConniKey | secreto |
| `HELIC3_SIESA_HUB_CONNI_TOKEN` | ConniToken | secreto |
| `HELIC3_SIESA_HUB_ID_COMPANIA` | Compañía | texto |
| `HELIC3_SIESA_HUB_CONSULTA_CLIENTES` | Consulta de clientes | texto |
| `HELIC3_SIESA_HUB_CONSULTA_COMPRAS` | Consultas de compras (separadas por coma) | texto |

Las credenciales son secretos: se escriben solo en esa página, **nunca** en el repo, en un PR ni en el chat del equipo. Pasar de Siesa QA a producción es cambiar la URL y las credenciales en la página, sin desarrollo.

La migración `copia_conexion_erp_a_super_admin` copió, una sola vez, los valores que hubiera en las variables de entorno anteriores (`HELIC3_ERP_MODO`, `SIESA_HUB_*`) sin pisar lo ya guardado.

`erp_meses_compras`, `erp_cache_horas` y `ventana_doble_radicacion_minutos` **no** van en esta página: son reglas de negocio de la cuenta y siguen en Parámetros.

> `find_customer` usa la **consulta de clientes** (filtro por cédula) y trae **nombre, teléfono, correo y dirección** de cualquier cédula, tenga compras o no. La **ciudad** llega como código (`idCiudad`/`idDepto` DANE), no como nombre, así que queda en blanco hasta agregar el catálogo DANE (follow-up). La **ventana de compras** la fija el parámetro administrable `erp_meses_compras`.

En modo `siesa`, si falta un campo, `Helic3::Erp.adapter` levanta `ConfiguracionInvalida` nombrando la clave que falta (sin imprimir su valor) y el endpoint responde 503: el formulario y el agente siguen a mano. Errores del módulo: `ConfiguracionInvalida` (configuración) y `NoDisponible` (desactivado, o Siesa caído).

## Hoja de ruta (épica 4B)

- **ERP-01** Contrato ← *(hecho)*
- **ERP-02** Datos simulados de prueba ← *(hecho)* — `Helic3::Erp::SimulatedData`: casos reales (cliente al día, con pendiente, en mora, mezcla) con los objetos del contrato
- **ERP-03** Adaptador simulado ← *(hecho)* — `Helic3::Erp::SimulatedAdapter` implementa el contrato con los datos simulados
- **ERP-07** Tabla de campos requeridos por consulta ← *(hecho)* — `ERP_CAMPOS.md` + prueba que garantiza que coincide con el código
- (luego) ERP-04 interruptor por configuración · ERP-05 adaptador real · ERP-06 consultas como Tools · ERP-08 cédula en radicación · ERP-09 notificaciones
