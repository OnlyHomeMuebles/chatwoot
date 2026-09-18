# Only Home — ERP Siesa · Campos requeridos por consulta (ERP-07)

Documento que define **exactamente qué se le pide al ERP** en cada consulta (entrada) y **qué
campos se esperan de vuelta** (salida). Es el insumo para que el área negocie el plan de consumo
del API con el proveedor (Siesa).

> Fuente de verdad: los objetos de valor del contrato (`Helic3::Erp::Customer`, `Invoice`,
> `AccountStatement`). Una prueba (`erp/campos_spec.rb`) verifica que esta tabla coincide con el código.

## Consultas

### 1. Identificar cliente por cédula — `find_customer(cedula:)`
- **Entrada:** `cedula` (texto)
- **Salida:** un `Customer` (o nada si no existe)

| Campo | Tipo | Descripción |
|---|---|---|
| `cedula` | texto | Documento del cliente |
| `nombre` | texto | Nombre completo |
| `email` | texto | Correo (opcional) |
| `telefono` | texto | Teléfono (opcional) |

### 2. Facturas del cliente — `invoices(cedula:)`
- **Entrada:** `cedula` (texto)
- **Salida:** lista de `Invoice` (campos de la tabla de abajo)

### 3. Detalle de una factura — `invoice(number:)`
- **Entrada:** `number` (texto, número de factura)
- **Salida:** un `Invoice` (o nada si no existe)

| Campo | Tipo | Descripción |
|---|---|---|
| `numero` | texto | Número de factura |
| `fecha` | fecha | Fecha de emisión |
| `total` | número | Valor total (COP) |
| `saldo` | número | Saldo pendiente (COP) |
| `estado` | texto | `pagada` / `pendiente` / `vencida` |
| `items` | lista | Detalle de líneas: `descripcion`, `cantidad`, `valor` (opcional) |

### 4. Estado de cuenta — `account_statement(cedula:)`
- **Entrada:** `cedula` (texto)
- **Salida:** un `AccountStatement` (o nada si no existe)

| Campo | Tipo | Descripción |
|---|---|---|
| `cedula` | texto | Documento del cliente |
| `saldo_total` | número | Suma de saldos pendientes (COP) |
| `facturas_pendientes` | número | Cantidad de facturas sin pagar |
| `al_dia` | booleano | `true` si no tiene facturas vencidas |

## Resumen para negociar con el proveedor

El API de Siesa debe permitir, como mínimo:
1. **Buscar un cliente por cédula** y devolver: cédula, nombre, email, teléfono.
2. **Listar las facturas de un cliente** con: número, fecha, total, saldo, estado.
3. **Consultar una factura** por número, con su detalle de líneas (descripción, cantidad, valor).
4. **Obtener el estado de cuenta** (saldo total, número de pendientes, si está al día).

Campos clave de identificación/entrada: **cédula** (cliente) y **número de factura**.
