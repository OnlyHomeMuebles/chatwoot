# Only Home — Integración con Siesa (ERP)

Módulo para consultar el ERP **Siesa** (cliente por cédula, facturas, estado de cuenta). Sigue
**puertos y adaptadores**: se define un **contrato** independiente del proveedor y se desarrolla
todo contra un **adaptador simulado**, de modo que conectar el API real de Siesa sea solo
configuración. Todo en open source, namespace `OnlyHome::Erp`, sin tocar `enterprise/`.

## Contrato (ERP-01) — `OnlyHome::Erp::Base`

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
| `Customer` | `cedula`, `nombre`, `email`, `telefono` |
| `Invoice` | `numero`, `fecha`, `total`, `saldo`, `estado` (`pagada`/`pendiente`/`vencida`), `items` |
| `AccountStatement` | `cedula`, `saldo_total`, `facturas_pendientes`, `al_dia` |

## Contrato de adaptador (pruebas)

`spec/support/only_home/erp_adapter_contract.rb` define el shared example
`'un adaptador de ERP'`. Cualquier adaptador lo reutiliza para garantizar que cumple el contrato:

```ruby
subject(:adapter) { described_class.new }
let(:known_cedula) { '...' }
let(:known_invoice_number) { '...' }
it_behaves_like 'un adaptador de ERP'
```

## Hoja de ruta (épica 4B)

- **ERP-01** Contrato ← *(hecho)*
- **ERP-02** Datos simulados de prueba ← *(hecho)* — `OnlyHome::Erp::SimulatedData`: casos reales (cliente al día, con pendiente, en mora, mezcla) con los objetos del contrato
- **ERP-03** Adaptador simulado ← *(hecho)* — `OnlyHome::Erp::SimulatedAdapter` implementa el contrato con los datos simulados
- **ERP-07** Tabla de campos requeridos por consulta ← *(hecho)* — `ERP_CAMPOS.md` + prueba que garantiza que coincide con el código
- (luego) ERP-04 interruptor por configuración · ERP-05 adaptador real · ERP-06 consultas como Tools · ERP-08 cédula en radicación · ERP-09 notificaciones
