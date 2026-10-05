# FMT-02 · Plantillas de formato versionadas y llenado de marcadores — Diseño

> Spec de implementación. Aterriza el ticket "Formatos con plantillas de Karen
> (Semana 3) · §5 FMT-02" contra el código real del fork. Verificado el 2026-10-05
> sobre la rama `feature/FMT-01-rev-libreoffice`.

## 1. Objetivo y alcance

Que una plantilla `.docx` entre al sistema, se **valide**, se **llene** con datos y
se **active**, todo **por API** (sin pantalla). Es el motor que FMT-03 (pantalla) y
FMT-04 (generar desde el expediente) consumen después.

**Fuera de alcance:** pantalla (FMT-03); generar desde el expediente (FMT-04);
editar el `.docx` en el navegador; plantillas en PDF/ODT/Excel; tablas que crecen
una fila por producto (cada marcador es un solo valor; una garantía con 3 productos
genera un formato por producto); imágenes que cambian por caso.

## 2. Rama, base y secuencia

- **Rama:** `feature/FMT-02-plantillas-formato`.
- **Base del ticket:** `integracion/entrega-7-formatos-pdf` con FMT-01 rev mergeado.
- **Realidad:** FMT-01 rev (PR #110) aún está en revisión. Esta rama se creó **desde
  `feature/FMT-01-rev-libreoffice`** para disponer del `Conversor`. Cuando #110
  entre a `entrega-7`, se re-apunta/rebasa FMT-02 sobre `entrega-7`. **FMT-02 no se
  mergea antes que #110.**
- **Dependencia dura:** `Helic3::Formatos::Conversor` (FMT-01).

## 3. Ajustes respecto al ticket (verificados contra el código)

1. **`numero_radicado` es un método derivado, no una columna.**
   `Helic3::Garantia#numero_radicado` = `"#{prefijo_radicado}#{display_id}"`
   (`app/models/helic3/garantia.rb:63`). Se usa tal cual.
2. **La ficha `helic3_ticket_datos` NO tiene `telefono` ni `factura_fecha`.**
   - `TELEFONO` se toma del contacto de la conversación: `conversation.contact.phone_number`.
   - `FECHA_COMPRA` (de AGT-11) **queda vacío** hasta que AGT-11 esté en `dev`; el
     método que lo resuelve lleva una línea marcada (comentario `# AGT-11`) devolviendo `''`.
   - Sí existen en la ficha: `cedula`, `direccion`, `ciudad`, `factura_numero`
     (`Helic3::TicketDato`, `app/models/helic3/ticket_dato.rb`).
3. **Autorización: el admin de Helic3 responde 401, no 403.** El patrón existente
   (`check_admin_authorization?` → `Pundit::NotAuthorizedError` → `render_unauthorized`
   → **401**) se reutiliza. El CA9 del ticket dice 403; **decisión pendiente de Jhan**:
   se recomienda **401** para no divergir del resto del admin. Este spec asume 401;
   si Jhan confirma 403, se ajusta solo el render de esos controladores.
4. **El PDF del expediente vive en `Helic3::Documento`** (`has_one_attached :archivo`,
   `clase: 'formato'`, `belongs_to :garantia optional`), no como attachment directo del
   ticket. Esto es de FMT-04; se anota aquí para que FMT-02 no cree otro mecanismo.

## 4. Datos: migraciones y modelos (ticket A, B)

### 4.1 `helic3_catalogo_formatos` (catálogo)

Replica el patrón de catálogos (`crear_catalogo`,
`db/migrate/20260821150000_create_helic3_catalogos_clasificacion.rb:73`): columnas
`account_id` (FK not null), `nombre` (string not null), `codigo` (string not null),
`posicion` (int not null default 0), `activo` (bool not null default true),
timestamps. Índices con **nombre corto** (límite de 63 chars de Postgres):
`idx_h3cat_formatos_account` y `idx_h3cat_formatos_account_codigo` (UNIQUE sobre
`[account_id, codigo]`).

Modelo `Helic3::Catalogo::Formato` (`app/models/helic3/catalogo/formato.rb`):
- `self.table_name = 'helic3_catalogo_formatos'` (inflector español).
- `include Helic3::Catalogo::Comun` (aporta `belongs_to :account`, validaciones de
  `nombre`/`codigo`/`posicion`, scope `activos`).
- `has_many :plantillas, class_name: 'Helic3::PlantillaFormato', foreign_key: :formato_id,
  dependent: :restrict_with_error, inverse_of: :formato`.

### 4.2 `helic3_plantillas_formato`

| Columna | Tipo | Papel |
| --- | --- | --- |
| `account_id` | FK accounts, not null | Aislamiento por cuenta |
| `formato_id` | FK `helic3_catalogo_formatos`, not null | A qué formato pertenece |
| `version` | integer, not null | 1,2,3… por formato |
| `estado` | string, not null, default `'borrador'` | `borrador` / `activa` / `retirada` |
| `marcadores` | jsonb, not null, default `[]` | Marcadores hallados al subir |
| `subido_por_id` | FK users, `on_delete: :nullify` | Quién subió |
| `subido_por_nombre` | string | Instantánea del nombre (sobrevive al borrado del user) |
| `activada_at` | datetime, null | Cuándo se activó |
| `activada_por_id` | FK users, `on_delete: :nullify` | Quién activó |

Índices:
- UNIQUE `(formato_id, version)` → `idx_h3_plantilla_formato_version`.
- **Parcial** UNIQUE `(formato_id) WHERE estado = 'activa'` → `idx_h3_plantilla_activa_unica`.
  Es la red de seguridad de "nunca dos activas del mismo formato".

Adjuntos (Active Storage, estilo `Helic3::Documento`):
`has_one_attached :original` (el `.docx` tal como lo subió Karen) y
`has_one_attached :fodt` (la conversión, lo que se llena).

Modelo `Helic3::PlantillaFormato` (`app/models/helic3/plantilla_formato.rb`,
`< ApplicationRecord`):
- `belongs_to :account`; `belongs_to :formato, class_name: 'Helic3::Catalogo::Formato'`.
- `belongs_to :subido_por`/`:activada_por` → `User`, `optional: true`.
- `has_one_attached :original`, `has_one_attached :fodt`.
- `ESTADOS = %w[borrador activa retirada].freeze`; `validates :estado, inclusion: ESTADOS`.
- `validates :version, numericality: { only_integer: true, greater_than: 0 }`.
- `scope :activa, -> { where(estado: 'activa') }`.
- Guard: `before_destroy` que **impide borrar** si `estado` ∈ (`activa`,`retirada`)
  (los PDF generados la referencian); un `borrador` sí se borra.
- Validaciones de pertenencia a la misma cuenta que el formato (patrón `TicketDato`).

### 4.3 Seeder (siembra de los 4 formatos)

En `Helic3::Catalogo::SeederService` (`app/services/helic3/catalogo/seeder_service.rb`):
- Constante nueva:
  ```ruby
  FORMATOS = [
    { nombre: 'No. 2 · Cumplimiento — entrega de mercancía reparada', codigo: 'cumplimiento_mercancia_reparada' },
    { nombre: 'No. 3 · Visita de técnico',                            codigo: 'visita_tecnica' },
    { nombre: 'No. 5 · Recolección de productos',                     codigo: 'recoleccion_productos' },
    { nombre: 'No. 8 · Cumplimiento — cambio o devolución',           codigo: 'cumplimiento_cambio_devolucion' }
  ].freeze
  ```
- Una línea en `sembrar!`: `sembrar_con_atributos(Helic3::Catalogo::Formato, FORMATOS)`.
- Contador en `resumen`.
- Registrar `formatos` en el despacho por `:tipo` del admin de catálogos para que
  Karen los renombre/desactive.

> La migración de catálogo nuevo es independiente de la siembra SIE-01; si se corre
> en un despliegue donde la tabla aún no existe, el seeder la salta con `tabla_lista?`.

## 5. Diccionario de marcadores y datos (ticket C, D)

### 5.1 `Helic3::Formatos::Marcadores`

`DICCIONARIO`: hash `"{{NOMBRE}}" → { descripcion:, ejemplo: }`. Sintaxis `{{NOMBRE}}`
en mayúsculas; al parsear se **toleran espacios** dentro de las llaves
(`{{ CLIENTE }}` == `{{CLIENTE}}`). Vive en código: es el **contrato** de qué datos
expone el sistema, no un valor de negocio.

Marcadores y su fuente real:

| Marcador | Fuente (código real) |
| --- | --- |
| `FECHA` | `Time.current.in_time_zone('America/Bogota')`, `dd/mm/aaaa` |
| `RADICADO` | `garantia.numero_radicado` |
| `RADICADO_PQR` | `ticket.display_id` (expediente) |
| `CLIENTE` | `ticket.conversation&.contact&.name` |
| `TELEFONO` | `ticket.conversation&.contact&.phone_number` |
| `CEDULA`,`DIRECCION`,`CIUDAD`,`FACTURA_NUMERO` | `ticket.datos` (`Helic3::TicketDato`) |
| `FECHA_COMPRA` | `''` por ahora — `# AGT-11` (no existe `factura_fecha`) |
| `PRODUCTO`,`PRODUCTO_REFERENCIA` | `item.producto_nombre`, `item.producto_referencia` |
| `MOTIVO_GARANTIA`,`DETALLE` | `item.motivo_garantia&.nombre`, `item.detalle_tipificado&.nombre` |
| `DECISION` | `item.decision` |
| `ELABORADO_POR` | `user` que genera (nombre) |

### 5.2 `Helic3::Formatos::DatosDelFormato`

- `.call(item:, user:)` → `Hash` marcador→texto, navegando
  `item.garantia.ticket` para llegar a conversación/contacto/ficha.
- `.faltantes(plantilla)` → los marcadores de `plantilla.marcadores` cuyo valor
  resuelto está vacío (para avisar en vista previa/generación).
- `DATOS_DE_EJEMPLO` → valores ficticios evidentes ("Cliente de Ejemplo", "1.234.567",
  "VISITA-0001"…) para la vista previa sin caso.

## 6. `Helic3::Formatos::LlenarPlantilla` (ticket E) — núcleo

`.call(fodt_xml, valores) → fodt_xml_lleno` con Nokogiri:

1. Parsear el `.fodt` como XML. Recorrer cada `text:p` y `text:h` (incluye tablas,
   encabezados y pies: en el `.fodt` todo está en el mismo archivo).
2. Por cada párrafo, **reconstruir el texto completo** concatenando sus fragmentos
   de texto (hijos `text:span` y texto suelto). Word parte un `{{CLIENTE}}` en varios
   `text:span`; marcadores de libro y elementos sin texto cuentan como **longitud 0**.
3. Localizar cada `{{...}}` por **posición** en el texto reconstruido. El reemplazo
   (valor) va en el **primer fragmento** del marcador (conserva su formato); el resto
   del marcador se **borra** de los fragmentos siguientes.
4. El valor entra como **texto del nodo** (Nokogiri lo escapa): un `<script>` o `&`
   quedan escapados y el `.fodt` sigue siendo XML válido. Saltos de línea del valor →
   espacio.
5. `.marcadores_de(fodt_xml)` → lista de marcadores presentes (misma lógica de
   fragmentos), usada por `SubirPlantilla`.

**Riesgo y prueba:** es la pieza más delicada, pero **no usa LibreOffice** (opera
sobre texto XML) → se testea 100% en local con `.fodt` de prueba fabricados
(cubre CA3 y CA4).

## 7. `SubirPlantilla` y `VistaPrevia` (ticket F, G)

### 7.1 `Helic3::Formatos::SubirPlantilla.call(formato:, archivo:, user:)`

- Acepta **solo `.docx`**: extensión `.docx` **y** cabecera de bytes `PK\x03\x04`.
- Tope de tamaño: `ENV.fetch('HELIC3_PLANTILLA_MAX_MB', '10').to_i` (infraestructura).
- Convierte a `.fodt` con `Conversor.a_fodt`. Si falla → error "no se pudo leer el archivo".
- Extrae marcadores con `LlenarPlantilla.marcadores_de`. Un marcador **fuera del
  diccionario detiene la subida** con la lista de desconocidos y la sugerencia más
  cercana (`DidYouMean::SpellChecker`, stdlib): «`{{CLEINTE}}` no existe; ¿quisiste
  decir `{{CLIENTE}}`?».
- **Cero marcadores se permite**, con advertencia en la respuesta.
- Crea la plantilla en `borrador` con `version = (max por formato) + 1`, adjunta
  `original` (el `.docx`) y `fodt` (la conversión), guarda `marcadores`,
  `subido_por_id`/`subido_por_nombre`.
- Devuelve un objeto resultado (ok?/errores/plantilla/advertencias) que el
  controlador traduce a 201 o 422.

### 7.2 `Helic3::Formatos::VistaPrevia.call(plantilla:, item: nil, user:)`

- Toma el `.fodt` de la plantilla, lo llena con `DATOS_DE_EJEMPLO` (si `item` nil) o
  con `DatosDelFormato.call(item:, user:)`, y lo pasa a PDF con `Conversor.a_pdf(_, extension: 'fodt')`.
- Devuelve los bytes del PDF. **Es la misma función que usa FMT-04** para generar
  (un solo camino: lo que se ve es lo que se guarda).

## 8. API de administración (ticket H)

Dentro del `namespace :admin` de Helic3 ya existente en `config/routes.rb`
(`/api/v1/accounts/:account_id/helic3/admin/...`):

```
GET    helic3/admin/formatos                         # formatos con su activa y versiones
GET    helic3/admin/formatos/marcadores              # el diccionario (descripcion + ejemplo)
POST   helic3/admin/formatos/:formato_id/plantillas  # multipart "archivo" → 201 | 422
GET    helic3/admin/plantillas/:id/vista_previa       # ?item_id= opcional → application/pdf inline
GET    helic3/admin/plantillas/:id/original           # descarga el .docx subido
POST   helic3/admin/plantillas/:id/activar            # la activa anterior → retirada (transacción)
DELETE helic3/admin/plantillas/:id                    # solo borrador
```

Controladores (`Api::V1::Accounts::Helic3::Admin::FormatosController` y
`PlantillasController`), heredan de `Api::V1::Accounts::BaseController`:
- `before_action :check_admin_authorization?` en las escrituras (crear/activar/borrar).
  Lectura (index/marcadores/vista_previa/original) abierta a agentes, como catálogos.
- Todo acotado por `Current.account`: `find_by!(account: Current.account, id:)` →
  recurso de otra cuenta da **404**. Sin rol admin → **401** (ver §3.3).
- `activar`: transacción que pone la activa anterior en `retirada` y esta en `activa`
  con `activada_at`/`activada_por_id`; el índice parcial es la última red.
- `destroy`: 422 si no es `borrador`.

## 9. Pruebas (los 10 CA)

Ubicación: `spec/services/helic3/formatos/`, `spec/models/helic3/plantilla_formato_spec.rb`,
`spec/controllers/api/v1/accounts/helic3/admin/`.

| CA | Prueba | ¿Local? |
| --- | --- | --- |
| 1 | Subir `.docx` conocido → 201, borrador, versión siguiente, lista de marcadores | Stub soffice |
| 2 | `{{CLEINTE}}` → 422 que lo nombra y sugiere `{{CLIENTE}}`; no guarda nada | Stub soffice |
| 3 | Marcador en 3 fragmentos con formatos distintos → reemplazo completo | **Sí (LlenarPlantilla)** |
| 4 | Valor con `<script>` y `&` → escapado, `.fodt` válido, PDF se genera | Parte local + stub PDF |
| 5 | Activar → anterior `retirada`; nunca dos activas (contra índice parcial) | **Sí** |
| 6 | Borrar `activa`/`retirada` → 422; `borrador` → borra | **Sí** |
| 7 | Vista previa → `application/pdf` que empieza con `%PDF` (ejemplo e ítem real) | Stub soffice |
| 8 | PDF renombrado a `.docx`, o `.xlsx` → 422 | **Sí** (chequeo de bytes) |
| 9 | Sin rol admin → 401 (ver §3.3); plantilla de otra cuenta → 404 | **Sí** |
| 10 | Migraciones corren y revierten limpio; `schema.rb` solo suma las 2 tablas; único upstream `config/routes.rb` | **Sí** |

> Lo que invoca `soffice` (SubirPlantilla, VistaPrevia) se **stubea** como en
> `spec/services/helic3/formatos/conversor_spec.rb` (dev local no tiene LibreOffice).
> `LlenarPlantilla` se prueba de verdad en local porque opera sobre `.fodt` (texto).

## 10. Frontera OSS

- Todo bajo `Helic3::` y tablas `helic3_*`; archivos nuevos bajo `app/.../helic3/`,
  `app/models/helic3/`, `spec/helic3|spec/services/helic3|spec/models/helic3`, `db/migrate/`.
- **Único archivo upstream tocado: `config/routes.rb`** (CA10). El guardián
  (`revisar-oss`) debe salir "Sin hallazgos".
- Sin gemas nuevas: `DidYouMean` y `Nokogiri` ya son dependencias (stdlib / Rails).

## 11. Comandos de verificación (del ticket)

```
bundle exec rails db:migrate && bundle exec rails db:rollback STEP=2 && bundle exec rails db:migrate
bundle exec rspec spec/services/helic3/formatos/ spec/models/helic3/plantilla_formato_spec.rb spec/controllers/api/v1/accounts/helic3/admin/
bundle exec rubocop app/services/helic3/formatos/ app/models/helic3/ app/controllers/api/v1/accounts/helic3/admin/
git diff --name-only origin/dev | grep -v -E "helic3|spec/|railpack.json|nixpacks.toml"   # solo config/routes.rb
```

## 12. Orden de implementación sugerido

1. Migraciones + modelos (`Catalogo::Formato`, `PlantillaFormato`) + seeder `FORMATOS`.
2. `Marcadores::DICCIONARIO` + `DatosDelFormato` (con `DATOS_DE_EJEMPLO`).
3. `LlenarPlantilla` (+ sus specs locales: CA3, CA4) — la pieza de riesgo, primero probada.
4. `SubirPlantilla` + `VistaPrevia` (stub soffice en specs).
5. Controladores + rutas admin + specs de controlador (CA1,2,7,8,9).
6. Pasada de `rubocop` + guardián OSS + comandos de verificación.
