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

## Configuración (ERP-04)

`Helic3::Erp.adapter` es el interruptor del módulo; `HELIC3_ERP_MODO` decide con quién se habla:

| `HELIC3_ERP_MODO` | Qué hace |
|---|---|
| `desactivado` (por defecto) | El ERP no responde; `habilitado?` es `false`. En producción nunca puede responder el simulado con clientes inventados: hay que encenderlo a propósito. |
| `simulado` | Usa `SimulatedAdapter` (datos de prueba). |
| `siesa` | Usa el adaptador real (ERP-05); exige las variables de conexión. |

Un valor desconocido levanta `Helic3::Erp::ConfiguracionInvalida`.

**Variables de Siesa Hub** (solo en modo `siesa`). Son secretos e infraestructura: se configuran en Dokploy, **nunca** en el repo, en un PR ni en el chat del equipo.

| Variable | Uso |
|---|---|
| `SIESA_HUB_BASE_URL` | Dirección base real de la API |
| `SIESA_HUB_CLIENT_ID` | Credencial (Apigee) |
| `SIESA_HUB_CONNI_KEY` | Credencial |
| `SIESA_HUB_CONNI_TOKEN` | Credencial |
| `SIESA_HUB_ID_COMPANIA` | Compañía donde se consulta |
| `SIESA_HUB_CONSULTA_CLIENTES` | Nombre exacto de la consulta de clientes |

En modo `siesa`, si falta alguna variable, `Helic3::Erp.adapter` levanta `ConfiguracionInvalida` nombrando la que falta (sin imprimir su valor). Errores del módulo: `ConfiguracionInvalida` (configuración) y `NoDisponible` (desactivado, o Siesa caído).

## Hoja de ruta (épica 4B)

- **ERP-01** Contrato ← *(hecho)*
- **ERP-02** Datos simulados de prueba ← *(hecho)* — `Helic3::Erp::SimulatedData`: casos reales (cliente al día, con pendiente, en mora, mezcla) con los objetos del contrato
- **ERP-03** Adaptador simulado ← *(hecho)* — `Helic3::Erp::SimulatedAdapter` implementa el contrato con los datos simulados
- **ERP-07** Tabla de campos requeridos por consulta ← *(hecho)* — `ERP_CAMPOS.md` + prueba que garantiza que coincide con el código
- (luego) ERP-04 interruptor por configuración · ERP-05 adaptador real · ERP-06 consultas como Tools · ERP-08 cédula en radicación · ERP-09 notificaciones
