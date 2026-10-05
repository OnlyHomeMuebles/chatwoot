# FMT-02 · Plantillas versionadas y llenado de marcadores — Plan de implementación

> **Para workers:** SUB-SKILL REQUERIDA: usar superpowers:subagent-driven-development
> (recomendado) o superpowers:executing-plans para implementar tarea por tarea.
> Los pasos usan checkbox (`- [ ]`) para seguimiento.

**Goal:** Que una plantilla `.docx` entre por API, se valide, se llene con datos de un expediente y se genere su PDF, con versiones y una sola activa por formato.

**Architecture:** Un catálogo nuevo (`helic3_catalogo_formatos`) y una tabla de versiones (`helic3_plantillas_formato`, con adjuntos `.docx` + `.fodt`). Servicios puros (`Marcadores`, `DatosDelFormato`, `LlenarPlantilla`, `SubirPlantilla`, `VistaPrevia`) y 2 controladores de admin. El relleno se hace sobre el `.fodt` con Nokogiri; el PDF lo produce el `Conversor` de FMT-01.

**Tech Stack:** Rails 7.2, PostgreSQL (índice único parcial), Active Storage, Nokogiri, `DidYouMean` (stdlib), RSpec. Docker Compose (specs con `-e RAILS_ENV=test`).

**Spec:** [docs/helic3/fmt-02-plantillas-diseno.md](fmt-02-plantillas-diseno.md)

## Global Constraints

- Frontera OSS: todo bajo `Helic3::` y tablas `helic3_*`; archivos nuevos bajo `app/**/helic3/`, `app/models/helic3/`, `spec/**/helic3/`, `db/migrate/`. **Único archivo upstream permitido: `config/routes.rb`.**
- Sin gemas nuevas: solo `Nokogiri` (ya en Rails) y `DidYouMean` (stdlib).
- Specs **siempre** con `-e RAILS_ENV=test` (sin eso usan la BD de dev y fallan falso).
- Longitud de columnas: `ApplicationRecord` ya valida `string` ≤ 255 y `text` ≤ 20_000 automáticamente.
- Autorización admin: sin rol admin → **401** (`check_admin_authorization?`, patrón existente). Recurso de otra cuenta → **404** (`find_by!(account: Current.account, …)`).
- Índices Postgres: nombre corto `idx_h3…` (límite de 63 chars).
- Lo que invoca `soffice` (Conversor) **se stubea** en specs; dev local no tiene LibreOffice.
- Guardián OSS debe salir "Sin hallazgos" antes de cada commit: `PYTHONUTF8=1 python .claude/skills/revisar-oss/guard.py --staged`.
- El hook de pre-commit está roto en este entorno (falta `lint-staged`); commitear con `--no-verify` tras correr rubocop a mano. Cerrar cada commit con:
  `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Review Focus

Entradas que el spec implica pero que ningún test obvio ejercita (más probable primero); cada una tiene su test en la tarea dueña:

1. **Marcador con espacios dentro de las llaves** (`{{ CLIENTE }}`) debe reconocerse igual que `{{CLIENTE}}` (Tarea 4).
2. **Valor con `<`, `>`, `&` o `<script>`**: entra escapado, el `.fodt` sigue siendo XML válido (Tarea 4, CA4).
3. **Zip válido que no es Word** (cabecera `PK\x03\x04` pero `soffice` falla al convertir): responde "no se pudo leer el archivo", no 500 (Tarea 5).
4. **Valor nil/campo faltante** (ficha sin cédula, sin contacto): el marcador queda **vacío**, nunca el texto "nil" (Tarea 3).
5. **Activar dos veces en paralelo / activar cuando ya hay una activa**: el índice parcial único garantiza una sola activa; activar retira la anterior en transacción (Tarea 2 el índice, Tarea 6 el flujo).

---

### Task 1: Catálogo de formatos (`Helic3::Catalogo::Formato`) + siembra

**Files:**
- Create: `db/migrate/20261006120000_create_helic3_catalogo_formatos.rb`
- Create: `app/models/helic3/catalogo/formato.rb`
- Modify: `app/services/helic3/catalogo/seeder_service.rb` (constante `FORMATOS`, línea en `sembrar!`, contador en `resumen`)
- Test: `spec/models/helic3/catalogo/formato_spec.rb`

**Interfaces:**
- Produces: `Helic3::Catalogo::Formato` (include `Helic3::Catalogo::Comun`; `has_many :plantillas`), tabla `helic3_catalogo_formatos` con 4 filas sembradas por cuenta; `Helic3::Catalogo::SeederService::FORMATOS`.

- [ ] **Step 1: Escribir el test del modelo (falla)**

`spec/models/helic3/catalogo/formato_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Catalogo::Formato do
  let(:account) { create(:account) }

  it 'usa la tabla helic3_catalogo_formatos' do
    expect(described_class.table_name).to eq('helic3_catalogo_formatos')
  end

  it 'valida nombre y codigo por cuenta (via Comun)' do
    described_class.create!(account: account, nombre: 'A', codigo: 'x', posicion: 0)
    dup = described_class.new(account: account, nombre: 'B', codigo: 'x', posicion: 1)
    expect(dup).not_to be_valid
  end

  it 'la siembra deja los 4 formatos por cuenta, idempotente' do
    Helic3::Catalogo::SeederService.new(account).sembrar!
    Helic3::Catalogo::SeederService.new(account).sembrar!
    expect(described_class.where(account: account).count).to eq(4)
    expect(described_class.where(account: account).pluck(:codigo)).to contain_exactly(
      'cumplimiento_mercancia_reparada', 'visita_tecnica',
      'recoleccion_productos', 'cumplimiento_cambio_devolucion'
    )
  end
end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/models/helic3/catalogo/formato_spec.rb`
Expected: FAIL (`uninitialized constant Helic3::Catalogo::Formato`).

- [ ] **Step 3: Crear la migración**

`db/migrate/20261006120000_create_helic3_catalogo_formatos.rb`:
```ruby
# frozen_string_literal: true

class CreateHelic3CatalogoFormatos < ActiveRecord::Migration[7.2]
  def up
    unless table_exists?(:helic3_catalogo_formatos)
      create_table :helic3_catalogo_formatos do |t|
        t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3cat_formatos_account' }
        t.string  :nombre,   null: false
        t.string  :codigo,   null: false
        t.integer :posicion, null: false, default: 0
        t.boolean :activo,   null: false, default: true
        t.timestamps
      end
      add_index :helic3_catalogo_formatos, %i[account_id codigo], unique: true,
                                                                  name: 'idx_h3cat_formatos_account_codigo'
    end

    Helic3::Catalogo::Formato.reset_column_information
    Account.find_each { |cuenta| Helic3::Catalogo::SeederService.new(cuenta).sembrar! }
  end

  def down
    drop_table :helic3_catalogo_formatos, if_exists: true
  end
end
```

- [ ] **Step 4: Crear el modelo**

`app/models/helic3/catalogo/formato.rb`:
```ruby
# frozen_string_literal: true

class Helic3::Catalogo::Formato < ApplicationRecord
  self.table_name = 'helic3_catalogo_formatos'

  include Helic3::Catalogo::Comun

  has_many :plantillas, class_name: 'Helic3::PlantillaFormato',
                        foreign_key: :formato_id, inverse_of: :formato,
                        dependent: :restrict_with_error
end
```

- [ ] **Step 5: Agregar `FORMATOS` al seeder**

En `app/services/helic3/catalogo/seeder_service.rb`, después de `PARAMETROS` agregar la constante:
```ruby
  FORMATOS = [
    { nombre: 'No. 2 · Cumplimiento — entrega de mercancía reparada', codigo: 'cumplimiento_mercancia_reparada' },
    { nombre: 'No. 3 · Visita de técnico',                            codigo: 'visita_tecnica' },
    { nombre: 'No. 5 · Recolección de productos',                     codigo: 'recoleccion_productos' },
    { nombre: 'No. 8 · Cumplimiento — cambio o devolución',           codigo: 'cumplimiento_cambio_devolucion' }
  ].freeze
```
En `sembrar!`, agregar la línea (junto a los demás `sembrar_con_atributos`):
```ruby
    sembrar_con_atributos(Helic3::Catalogo::Formato, FORMATOS)
```
En `resumen`, sumar el contador de formatos siguiendo el patrón de los demás catálogos (una línea `formatos: Helic3::Catalogo::Formato.where(account: @account).count`).

> `sembrar_con_atributos` ya hace `return unless tabla_lista?(modelo)`, así que si esta migración aún no ha corrido (p. ej. durante SIE-01), la siembra de formatos se salta sola.

- [ ] **Step 6: Migrar la BD de test y correr el spec (pasa)**

Run:
```
docker compose exec -e RAILS_ENV=test rails bundle exec rails db:migrate
docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/models/helic3/catalogo/formato_spec.rb
```
Expected: PASS (3 examples).

- [ ] **Step 7: rubocop + guardián + commit**

```
docker compose exec rails bundle exec rubocop app/models/helic3/catalogo/formato.rb app/services/helic3/catalogo/seeder_service.rb db/migrate/20261006120000_create_helic3_catalogo_formatos.rb
PYTHONUTF8=1 python .claude/skills/revisar-oss/guard.py --staged   # tras git add
git add -A && git commit --no-verify -m "feat(formatos): catalogo helic3_catalogo_formatos sembrado (FMT-02)"
```

---

### Task 2: `Helic3::PlantillaFormato` (versiones, estados, adjuntos)

**Files:**
- Create: `db/migrate/20261006120100_create_helic3_plantillas_formato.rb`
- Create: `app/models/helic3/plantilla_formato.rb`
- Test: `spec/models/helic3/plantilla_formato_spec.rb`

**Interfaces:**
- Consumes: `Helic3::Catalogo::Formato` (Task 1).
- Produces: `Helic3::PlantillaFormato` con `ESTADOS`, `has_one_attached :original` y `:fodt`, `scope :activa`, guard `before_destroy`; índice único `(formato_id, version)` e índice único parcial `(formato_id) WHERE estado='activa'`.

- [ ] **Step 1: Escribir el test del modelo (falla)**

`spec/models/helic3/plantilla_formato_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::PlantillaFormato do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def nueva(estado:, version:)
    described_class.create!(account: account, formato: formato, version: version, estado: estado, marcadores: [])
  end

  it 'rechaza un estado invalido' do
    p = described_class.new(account: account, formato: formato, version: 1, estado: 'otro')
    expect(p).not_to be_valid
  end

  it 'no permite dos versiones iguales por formato (indice unico)' do
    nueva(estado: 'borrador', version: 1)
    expect { nueva(estado: 'borrador', version: 1) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'no permite dos activas del mismo formato (indice parcial) [CA5]' do
    nueva(estado: 'activa', version: 1)
    expect { nueva(estado: 'activa', version: 2) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'no borra una activa o retirada; si borra un borrador [CA6]' do
    activa = nueva(estado: 'activa', version: 1)
    expect(activa.destroy).to be_falsey
    borrador = nueva(estado: 'borrador', version: 2)
    expect(borrador.destroy).to be_truthy
  end

  it 'scope activa' do
    nueva(estado: 'activa', version: 1)
    nueva(estado: 'borrador', version: 2)
    expect(described_class.activa.count).to eq(1)
  end
end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/models/helic3/plantilla_formato_spec.rb`
Expected: FAIL (constante/tabla inexistente).

- [ ] **Step 3: Crear la migración**

`db/migrate/20261006120100_create_helic3_plantillas_formato.rb`:
```ruby
# frozen_string_literal: true

class CreateHelic3PlantillasFormato < ActiveRecord::Migration[7.2]
  def change
    create_table :helic3_plantillas_formato do |t|
      t.references :account, null: false, foreign_key: true, index: { name: 'idx_h3_plantilla_formato_account' }
      t.bigint   :formato_id, null: false
      t.integer  :version, null: false
      t.string   :estado, null: false, default: 'borrador'
      t.jsonb    :marcadores, null: false, default: []
      t.bigint   :subido_por_id
      t.string   :subido_por_nombre
      t.datetime :activada_at
      t.bigint   :activada_por_id
      t.timestamps
    end

    add_index :helic3_plantillas_formato, :formato_id, name: 'idx_h3_plantilla_formato_formato'
    add_index :helic3_plantillas_formato, %i[formato_id version], unique: true,
                                                                  name: 'idx_h3_plantilla_formato_version'
    add_index :helic3_plantillas_formato, :formato_id, unique: true,
                                                        where: "estado = 'activa'",
                                                        name: 'idx_h3_plantilla_activa_unica'
    add_foreign_key :helic3_plantillas_formato, :helic3_catalogo_formatos, column: :formato_id
    add_foreign_key :helic3_plantillas_formato, :users, column: :subido_por_id, on_delete: :nullify
    add_foreign_key :helic3_plantillas_formato, :users, column: :activada_por_id, on_delete: :nullify
  end
end
```

- [ ] **Step 4: Crear el modelo**

`app/models/helic3/plantilla_formato.rb`:
```ruby
# frozen_string_literal: true

class Helic3::PlantillaFormato < ApplicationRecord
  self.table_name = 'helic3_plantillas_formato'

  ESTADOS = %w[borrador activa retirada].freeze

  belongs_to :account
  belongs_to :formato, class_name: 'Helic3::Catalogo::Formato'
  belongs_to :subido_por, class_name: 'User', optional: true
  belongs_to :activada_por, class_name: 'User', optional: true

  has_one_attached :original
  has_one_attached :fodt

  validates :estado, inclusion: { in: ESTADOS }
  validates :version, numericality: { only_integer: true, greater_than: 0 }

  scope :activa, -> { where(estado: 'activa') }

  before_destroy :solo_borrador_se_borra

  private

  def solo_borrador_se_borra
    return if estado == 'borrador'

    errors.add(:base, 'una plantilla activa o retirada no se puede borrar')
    throw(:abort)
  end
end
```

- [ ] **Step 5: Migrar test DB y correr el spec (pasa)**

Run:
```
docker compose exec -e RAILS_ENV=test rails bundle exec rails db:migrate
docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/models/helic3/plantilla_formato_spec.rb
```
Expected: PASS (5 examples).

- [ ] **Step 6: rubocop + guardián + commit**

```
docker compose exec rails bundle exec rubocop app/models/helic3/plantilla_formato.rb db/migrate/20261006120100_create_helic3_plantillas_formato.rb
git add -A && git commit --no-verify -m "feat(formatos): tabla helic3_plantillas_formato con version y una sola activa (FMT-02)"
```

---

### Task 3: Diccionario de marcadores + `DatosDelFormato`

**Files:**
- Create: `app/services/helic3/formatos/marcadores.rb`
- Create: `app/services/helic3/formatos/datos_del_formato.rb`
- Test: `spec/services/helic3/formatos/datos_del_formato_spec.rb`

**Interfaces:**
- Produces: `Helic3::Formatos::Marcadores::DICCIONARIO` (hash `"NOMBRE" => {descripcion:, ejemplo:}`), `.conocido?(nombre)`, `.nombres`; `Helic3::Formatos::DatosDelFormato.call(item:, user:) → Hash`, `.faltantes(plantilla, item:, user:) → Array`, `DATOS_DE_EJEMPLO`.

- [ ] **Step 1: Escribir el test (falla)**

`spec/services/helic3/formatos/datos_del_formato_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::DatosDelFormato do
  it 'DATOS_DE_EJEMPLO cubre todos los marcadores del diccionario' do
    expect(described_class::DATOS_DE_EJEMPLO.keys).to match_array(Helic3::Formatos::Marcadores.nombres)
  end

  it 'un campo faltante queda vacio, nunca "nil" [Review Focus 4]' do
    item = instance_double(Helic3::GarantiaItem,
                           garantia: instance_double(Helic3::Garantia, numero_radicado: 'GAR-1',
                                                                       ticket: ticket_sin_datos),
                           producto_nombre: 'Silla', producto_referencia: nil,
                           motivo_garantia: nil, detalle_tipificado: nil, decision: nil)
    datos = described_class.call(item: item, user: nil)
    expect(datos['CEDULA']).to eq('')
    expect(datos['CLIENTE']).to eq('')
    expect(datos.values).not_to include('nil')
  end

  def ticket_sin_datos
    instance_double(Helic3::Ticket, display_id: 7, datos: nil, conversation: nil)
  end
end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/datos_del_formato_spec.rb`
Expected: FAIL (constantes inexistentes).

- [ ] **Step 3: Crear `Marcadores`**

`app/services/helic3/formatos/marcadores.rb`:
```ruby
# frozen_string_literal: true

# Contrato de que datos expone el sistema (no valores de negocio): por eso en codigo.
module Helic3::Formatos::Marcadores
  DICCIONARIO = {
    'FECHA'               => { descripcion: 'Fecha de generación (dd/mm/aaaa)', ejemplo: '05/10/2026' },
    'RADICADO'            => { descripcion: 'Radicado de la garantía', ejemplo: 'GAR-0001' },
    'RADICADO_PQR'        => { descripcion: 'Consecutivo del expediente', ejemplo: '1234' },
    'CLIENTE'             => { descripcion: 'Nombre del cliente', ejemplo: 'Cliente de Ejemplo' },
    'TELEFONO'            => { descripcion: 'Teléfono del cliente', ejemplo: '3001234567' },
    'CEDULA'              => { descripcion: 'Cédula del cliente', ejemplo: '1.234.567' },
    'DIRECCION'           => { descripcion: 'Dirección del cliente', ejemplo: 'Calle 1 # 2-3' },
    'CIUDAD'              => { descripcion: 'Ciudad del cliente', ejemplo: 'Cali' },
    'FACTURA_NUMERO'      => { descripcion: 'Número de factura', ejemplo: 'FAC-999' },
    'FECHA_COMPRA'        => { descripcion: 'Fecha de compra (AGT-11, aún no disponible)', ejemplo: '' },
    'PRODUCTO'            => { descripcion: 'Nombre del producto', ejemplo: 'Sofá Milano' },
    'PRODUCTO_REFERENCIA' => { descripcion: 'Referencia del producto', ejemplo: 'REF-123' },
    'MOTIVO_GARANTIA'     => { descripcion: 'Motivo de garantía', ejemplo: 'Falla de fábrica' },
    'DETALLE'             => { descripcion: 'Detalle tipificado', ejemplo: 'Chapilla levantada' },
    'DECISION'            => { descripcion: 'Decisión del ítem', ejemplo: 'Cambio de producto' },
    'ELABORADO_POR'       => { descripcion: 'Quien genera el formato', ejemplo: 'Asesora SAC' }
  }.freeze

  def self.conocido?(nombre)
    DICCIONARIO.key?(nombre)
  end

  def self.nombres
    DICCIONARIO.keys
  end
end
```

- [ ] **Step 4: Crear `DatosDelFormato`**

`app/services/helic3/formatos/datos_del_formato.rb`:
```ruby
# frozen_string_literal: true

# Resuelve cada marcador a su texto desde el item de garantia y su expediente.
class Helic3::Formatos::DatosDelFormato
  ZONA = 'America/Bogota'

  DATOS_DE_EJEMPLO = Helic3::Formatos::Marcadores::DICCIONARIO
                     .transform_values { |v| v[:ejemplo].to_s }.freeze

  def self.call(item:, user:)
    new(item, user).call
  end

  def self.faltantes(plantilla, item:, user:)
    datos = call(item: item, user: user)
    Array(plantilla.marcadores).select { |m| datos[m].to_s.strip.empty? }
  end

  def initialize(item, user)
    @item = item
    @user = user
    @garantia = item.garantia
    @ticket = @garantia.ticket
    @ficha = @ticket.datos
    @contacto = @ticket.conversation&.contact
  end

  def call
    {
      'FECHA' => Time.current.in_time_zone(ZONA).strftime('%d/%m/%Y'),
      'RADICADO' => @garantia.numero_radicado.to_s,
      'RADICADO_PQR' => @ticket.display_id.to_s,
      'CLIENTE' => @contacto&.name.to_s,
      'TELEFONO' => @contacto&.phone_number.to_s,
      'CEDULA' => @ficha&.cedula.to_s,
      'DIRECCION' => @ficha&.direccion.to_s,
      'CIUDAD' => @ficha&.ciudad.to_s,
      'FACTURA_NUMERO' => @ficha&.factura_numero.to_s,
      'FECHA_COMPRA' => fecha_compra,
      'PRODUCTO' => @item.producto_nombre.to_s,
      'PRODUCTO_REFERENCIA' => @item.producto_referencia.to_s,
      'MOTIVO_GARANTIA' => @item.motivo_garantia&.nombre.to_s,
      'DETALLE' => @item.detalle_tipificado&.nombre.to_s,
      'DECISION' => @item.decision.to_s,
      'ELABORADO_POR' => @user&.name.to_s
    }
  end

  private

  # AGT-11: la ficha aun no tiene factura_fecha en dev. Se conecta cuando AGT-11 entre.
  def fecha_compra
    ''
  end
end
```

- [ ] **Step 5: Correr el spec (pasa)**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/datos_del_formato_spec.rb`
Expected: PASS (2 examples).

- [ ] **Step 6: rubocop + guardián + commit**

```
docker compose exec rails bundle exec rubocop app/services/helic3/formatos/marcadores.rb app/services/helic3/formatos/datos_del_formato.rb
git add -A && git commit --no-verify -m "feat(formatos): diccionario de marcadores y DatosDelFormato (FMT-02)"
```

---

### Task 4: `Helic3::Formatos::LlenarPlantilla` (Nokogiri) — núcleo

**Files:**
- Create: `app/services/helic3/formatos/llenar_plantilla.rb`
- Test: `spec/services/helic3/formatos/llenar_plantilla_spec.rb`
- Test fixtures: `.fodt` mínimos fabricados dentro del propio spec (string heredoc), sin LibreOffice.

**Interfaces:**
- Produces: `Helic3::Formatos::LlenarPlantilla.call(fodt_xml, valores) → fodt_xml`, `.marcadores_de(fodt_xml) → Array<String>`.

- [ ] **Step 1: Escribir el test (falla) — cubre CA3, CA4 y Review Focus 1/2**

`spec/services/helic3/formatos/llenar_plantilla_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::LlenarPlantilla do
  NS = 'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"'

  def fodt(cuerpo)
    %(<?xml version="1.0"?><office xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" #{NS}>#{cuerpo}</office>)
  end

  it 'reemplaza un marcador partido en tres text:span con formatos distintos [CA3]' do
    xml = fodt('<text:p><text:span>Hola {{CLI</text:span><text:span>EN</text:span><text:span>TE}}!</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => 'Ana')
    expect(Nokogiri::XML(salida).text).to eq('Hola Ana!')
  end

  it 'escapa valores con <script> y & y deja XML valido [CA4]' do
    xml = fodt('<text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    salida = described_class.call(xml, 'CLIENTE' => '<script> & "x"')
    doc = Nokogiri::XML(salida)
    expect(doc.errors).to be_empty
    expect(doc.text).to eq('<script> & "x"')
  end

  it 'tolera espacios dentro de las llaves [Review Focus 1]' do
    xml = fodt('<text:p><text:span>{{ CLIENTE }}</text:span></text:p>')
    expect(described_class.marcadores_de(xml)).to eq(['CLIENTE'])
    salida = described_class.call(xml, 'CLIENTE' => 'Ana')
    expect(Nokogiri::XML(salida).text).to eq('Ana')
  end

  it 'reduce saltos de linea del valor a espacio' do
    xml = fodt('<text:p><text:span>{{DIRECCION}}</text:span></text:p>')
    salida = described_class.call(xml, 'DIRECCION' => "Calle 1\nApto 2")
    expect(Nokogiri::XML(salida).text).to eq('Calle 1 Apto 2')
  end

  it 'marcadores_de encuentra en parrafos, encabezados y tablas' do
    xml = fodt('<text:h><text:span>{{RADICADO}}</text:span></text:h><text:p><text:span>{{CLIENTE}}</text:span></text:p>')
    expect(described_class.marcadores_de(xml)).to contain_exactly('RADICADO', 'CLIENTE')
  end
end
```

- [ ] **Step 2: Correr y ver que falla**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/llenar_plantilla_spec.rb`
Expected: FAIL (constante inexistente).

- [ ] **Step 3: Implementar `LlenarPlantilla`**

`app/services/helic3/formatos/llenar_plantilla.rb`:
```ruby
# frozen_string_literal: true

# Llena los marcadores {{NOMBRE}} de un .fodt (OpenDocument plano) con Nokogiri.
# Word parte el texto en varios text:span; se reconstruye el texto del parrafo, se
# ubica el marcador por posicion, el valor va al primer fragmento y el resto se borra.
# El valor se pone como TEXTO del nodo: Nokogiri lo escapa (nunca entra como XML).
class Helic3::Formatos::LlenarPlantilla
  PATRON = /\{\{\s*([A-Z_]+)\s*\}\}/
  NS_TEXT = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'

  def self.call(fodt_xml, valores)
    new(fodt_xml).llenar(valores)
  end

  def self.marcadores_de(fodt_xml)
    new(fodt_xml).marcadores
  end

  def initialize(fodt_xml)
    @doc = Nokogiri::XML(fodt_xml)
  end

  def marcadores
    parrafos.flat_map { |p| texto_de(p).scan(PATRON).flatten }.uniq
  end

  def llenar(valores)
    parrafos.each { |p| reemplazar_en(p, valores) }
    @doc.to_xml
  end

  private

  def parrafos
    @doc.xpath('//text:p | //text:h', 'text' => NS_TEXT)
  end

  def nodos(parrafo)
    parrafo.xpath('.//text()')
  end

  def texto_de(parrafo)
    nodos(parrafo).map(&:content).join
  end

  # reemplaza el PRIMER marcador del parrafo y repite hasta que no queden (asi
  # multiples marcadores en el mismo parrafo no corren los indices entre si).
  def reemplazar_en(parrafo, valores)
    loop do
      ns = nodos(parrafo)
      completo = ns.map(&:content).join
      coincidencia = completo.match(PATRON)
      break unless coincidencia

      valor = (valores[coincidencia[1]] || '').to_s.gsub(/\s*\n\s*/, ' ')
      aplicar(ns, coincidencia.begin(0), coincidencia.end(0), valor)
    end
  end

  # pone `valor` en el rango [desde, hasta): todo el valor va al primer nodo tocado;
  # en los siguientes se borra la parte del marcador que les corresponde.
  def aplicar(nodos, desde, hasta, valor)
    pos = 0
    primero = true
    nodos.each do |nodo|
      ini = pos
      fin = pos + nodo.content.length
      pos = fin
      next if fin <= desde || ini >= hasta

      recorte_ini = [desde, ini].max - ini
      recorte_fin = [hasta, fin].min - ini
      actual = nodo.content
      nodo.content = if primero
                       "#{actual[0...recorte_ini]}#{valor}#{actual[recorte_fin..]}"
                     else
                       "#{actual[0...recorte_ini]}#{actual[recorte_fin..]}"
                     end
      primero = false
    end
  end
end
```

- [ ] **Step 4: Correr el spec (pasa)**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/llenar_plantilla_spec.rb`
Expected: PASS (5 examples).

- [ ] **Step 5: rubocop + guardián + commit**

```
docker compose exec rails bundle exec rubocop app/services/helic3/formatos/llenar_plantilla.rb
git add -A && git commit --no-verify -m "feat(formatos): LlenarPlantilla reemplaza marcadores con Nokogiri (FMT-02)"
```

---

### Task 5: `SubirPlantilla` y `VistaPrevia` (Conversor stubeado)

**Files:**
- Create: `app/services/helic3/formatos/subir_plantilla.rb`
- Create: `app/services/helic3/formatos/vista_previa.rb`
- Test: `spec/services/helic3/formatos/subir_plantilla_spec.rb`
- Test: `spec/services/helic3/formatos/vista_previa_spec.rb`

**Interfaces:**
- Consumes: `Conversor.a_fodt`/`.a_pdf` (FMT-01), `LlenarPlantilla` (Task 4), `Marcadores` (Task 3), `PlantillaFormato` (Task 2).
- Produces: `SubirPlantilla.call(formato:, archivo:, user:) → Resultado(ok?, plantilla, errores, advertencias)`; `VistaPrevia.call(plantilla:, item: nil, user: nil) → String(bytes PDF)`.

- [ ] **Step 1: Escribir los tests (fallan) — cubre CA1, CA2, CA8, Review Focus 3**

`spec/services/helic3/formatos/subir_plantilla_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::SubirPlantilla do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def archivo(nombre, contenido)
    Rack::Test::UploadedFile.new(StringIO.new(contenido), nil, original_filename: nombre)
  end

  def docx(contenido = "PK\x03\x04docx-bytes")
    archivo('plantilla.docx', contenido)
  end

  it 'sube un .docx con marcadores conocidos → ok, borrador, version 1 [CA1]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLIENTE RADICADO])

    r = described_class.call(formato: formato, archivo: docx, user: nil)
    expect(r.ok?).to be(true)
    expect(r.plantilla.estado).to eq('borrador')
    expect(r.plantilla.version).to eq(1)
    expect(r.plantilla.marcadores).to eq(%w[CLIENTE RADICADO])
  end

  it 'rechaza un marcador desconocido y sugiere el cercano; no guarda nada [CA2]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLEINTE])

    r = described_class.call(formato: formato, archivo: docx, user: nil)
    expect(r.ok?).to be(false)
    expect(r.errores.first).to include('{{CLEINTE}}').and include('{{CLIENTE}}')
    expect(formato.plantillas.count).to eq(0)
  end

  it 'rechaza un .xlsx o un PDF renombrado a .docx [CA8]' do
    expect(described_class.call(formato: formato, archivo: archivo('x.xlsx', 'PK\x03\x04'), user: nil).ok?).to be(false)
    expect(described_class.call(formato: formato, archivo: archivo('x.docx', '%PDF-1.7'), user: nil).ok?).to be(false)
  end

  it 'si el Conversor falla → "no se pudo leer el archivo" [Review Focus 3]' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_raise(Helic3::Formatos::Conversor::Error)
    r = described_class.call(formato: formato, archivo: docx, user: nil)
    expect(r.ok?).to be(false)
    expect(r.errores).to include('no se pudo leer el archivo')
  end

  it 'cero marcadores: ok con advertencia' do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return([])
    r = described_class.call(formato: formato, archivo: docx, user: nil)
    expect(r.ok?).to be(true)
    expect(r.advertencias).not_to be_empty
  end
end
```

`spec/services/helic3/formatos/vista_previa_spec.rb`:
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Formatos::VistaPrevia do
  let(:account) { create(:account) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }
  let(:plantilla) do
    p = formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[CLIENTE])
    p.fodt.attach(io: StringIO.new('<office/>'), filename: 'p.fodt', content_type: 'text/xml')
    p
  end

  it 'sin item usa DATOS_DE_EJEMPLO y devuelve un PDF [CA7]' do
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:call).and_return('<office/>')
    allow(Helic3::Formatos::Conversor).to receive(:a_pdf).and_return('%PDF-1.7 ok')
    expect(described_class.call(plantilla: plantilla)).to start_with('%PDF')
  end
end
```

- [ ] **Step 2: Correr y ver que fallan**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/subir_plantilla_spec.rb spec/services/helic3/formatos/vista_previa_spec.rb`
Expected: FAIL.

- [ ] **Step 3: Implementar `SubirPlantilla`**

`app/services/helic3/formatos/subir_plantilla.rb`:
```ruby
# frozen_string_literal: true

# Valida un .docx, lo convierte a .fodt, verifica sus marcadores contra el
# diccionario y crea la plantilla en borrador con la version siguiente.
class Helic3::Formatos::SubirPlantilla
  Resultado = Struct.new(:ok?, :plantilla, :errores, :advertencias, keyword_init: true)

  FIRMA_DOCX = "PK\x03\x04".b
  TIPO_DOCX = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'

  def self.call(formato:, archivo:, user:)
    new(formato, archivo, user).call
  end

  def initialize(formato, archivo, user)
    @formato = formato
    @archivo = archivo
    @user = user
  end

  def call
    error = validar_archivo
    return fallo([error]) if error

    bytes = @archivo.read
    fodt = Helic3::Formatos::Conversor.a_fodt(bytes)
    marcadores = Helic3::Formatos::LlenarPlantilla.marcadores_de(fodt)
    desconocidos = marcadores.reject { |m| Helic3::Formatos::Marcadores.conocido?(m) }
    return fallo(mensajes_desconocidos(desconocidos)) if desconocidos.any?

    crear(bytes, fodt, marcadores)
  rescue Helic3::Formatos::Conversor::Error
    fallo(['no se pudo leer el archivo'])
  end

  private

  def validar_archivo
    nombre = @archivo.original_filename.to_s.downcase
    return 'solo se aceptan archivos .docx' unless nombre.end_with?('.docx')

    cabecera = @archivo.read(4)
    @archivo.rewind
    return 'el archivo no es un .docx válido' unless cabecera == FIRMA_DOCX
    return "el archivo supera #{max_mb} MB" if @archivo.size.to_i > max_mb * 1_000_000

    nil
  end

  def max_mb
    ENV.fetch('HELIC3_PLANTILLA_MAX_MB', '10').to_i
  end

  def crear(bytes, fodt, marcadores)
    plantilla = @formato.plantillas.new(
      account: @formato.account, version: siguiente_version, estado: 'borrador',
      marcadores: marcadores, subido_por_id: @user&.id, subido_por_nombre: @user&.name
    )
    plantilla.original.attach(io: StringIO.new(bytes), filename: @archivo.original_filename, content_type: TIPO_DOCX)
    plantilla.fodt.attach(io: StringIO.new(fodt), filename: 'plantilla.fodt', content_type: 'text/xml')
    plantilla.save!
    Resultado.new(ok?: true, plantilla: plantilla, errores: [],
                  advertencias: marcadores.empty? ? ['la plantilla no tiene marcadores'] : [])
  end

  def siguiente_version
    (@formato.plantillas.maximum(:version) || 0) + 1
  end

  def mensajes_desconocidos(desconocidos)
    corrector = DidYouMean::SpellChecker.new(dictionary: Helic3::Formatos::Marcadores.nombres)
    desconocidos.map do |m|
      sugerencia = corrector.correct(m).first
      sugerencia ? "{{#{m}}} no existe; ¿quisiste decir {{#{sugerencia}}}?" : "{{#{m}}} no existe"
    end
  end

  def fallo(errores)
    Resultado.new(ok?: false, plantilla: nil, errores: errores, advertencias: [])
  end
end
```

- [ ] **Step 4: Implementar `VistaPrevia`**

`app/services/helic3/formatos/vista_previa.rb`:
```ruby
# frozen_string_literal: true

# Llena el .fodt de la plantilla (con datos de ejemplo o de un item real) y lo pasa
# a PDF con el Conversor. Es la MISMA funcion que usa FMT-04 para generar.
class Helic3::Formatos::VistaPrevia
  def self.call(plantilla:, item: nil, user: nil)
    valores = if item
                Helic3::Formatos::DatosDelFormato.call(item: item, user: user)
              else
                Helic3::Formatos::DatosDelFormato::DATOS_DE_EJEMPLO
              end
    lleno = Helic3::Formatos::LlenarPlantilla.call(plantilla.fodt.download, valores)
    Helic3::Formatos::Conversor.a_pdf(lleno, extension: 'fodt')
  end
end
```

- [ ] **Step 5: Correr specs (pasan)**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/`
Expected: PASS (todo el directorio).

- [ ] **Step 6: rubocop + guardián + commit**

```
docker compose exec rails bundle exec rubocop app/services/helic3/formatos/subir_plantilla.rb app/services/helic3/formatos/vista_previa.rb
git add -A && git commit --no-verify -m "feat(formatos): SubirPlantilla y VistaPrevia (FMT-02)"
```

---

### Task 6: API de administración (rutas + controladores)

**Files:**
- Modify: `config/routes.rb` (dentro del `namespace :admin` de Helic3)
- Create: `app/controllers/api/v1/accounts/helic3/admin/formatos_controller.rb`
- Create: `app/controllers/api/v1/accounts/helic3/admin/plantillas_controller.rb`
- Create: `app/views/api/v1/accounts/helic3/admin/formatos/index.json.jbuilder`
- Test: `spec/controllers/api/v1/accounts/helic3/admin/formatos_controller_spec.rb`
- Test: `spec/controllers/api/v1/accounts/helic3/admin/plantillas_controller_spec.rb`

**Interfaces:**
- Consumes: `SubirPlantilla`, `VistaPrevia`, `Marcadores::DICCIONARIO`, `PlantillaFormato`, `Catalogo::Formato`.

- [ ] **Step 1: Escribir los request specs (fallan) — cubre CA1, CA2, CA7, CA8, CA9, CA5/CA6 por API**

`spec/controllers/api/v1/accounts/helic3/admin/plantillas_controller_spec.rb` (request spec):
```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Plantillas', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def docx
    Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04x"), nil, original_filename: 'p.docx')
  end

  before do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLIENTE])
  end

  it 'POST crea plantilla → 201 [CA1]' do
    post "/api/v1/accounts/#{account.id}/helic3/admin/formatos/#{formato.id}/plantillas",
         params: { archivo: docx }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created)
  end

  it 'sin rol admin → 401 [CA9]' do
    post "/api/v1/accounts/#{account.id}/helic3/admin/formatos/#{formato.id}/plantillas",
         params: { archivo: docx }, headers: agente.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'plantilla de otra cuenta → 404 [CA9]' do
    otra = Helic3::PlantillaFormato.create!(account: create(:account), formato: formato, version: 1, estado: 'borrador')
    delete "/api/v1/accounts/#{account.id}/helic3/admin/plantillas/#{otra.id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'activar retira la anterior [CA5]' do
    v1 = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    v2 = formato.plantillas.create!(account: account, version: 2, estado: 'borrador')
    post "/api/v1/accounts/#{account.id}/helic3/admin/plantillas/#{v2.id}/activar",
         headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(v1.reload.estado).to eq('retirada')
    expect(v2.reload.estado).to eq('activa')
  end

  it 'borrar una activa → 422 [CA6]' do
    v1 = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    delete "/api/v1/accounts/#{account.id}/helic3/admin/plantillas/#{v1.id}",
           headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'vista_previa devuelve application/pdf [CA7]' do
    plantilla = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    allow(Helic3::Formatos::VistaPrevia).to receive(:call).and_return('%PDF-1.7 ok')
    get "/api/v1/accounts/#{account.id}/helic3/admin/plantillas/#{plantilla.id}/vista_previa",
        headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/pdf')
    expect(response.body).to start_with('%PDF')
  end
end
```

- [ ] **Step 2: Correr y ver que fallan**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/controllers/api/v1/accounts/helic3/admin/`
Expected: FAIL (rutas/controladores inexistentes).

- [ ] **Step 3: Agregar las rutas** (único cambio upstream)

En `config/routes.rb`, dentro del `namespace :admin` de Helic3 (junto a `catalogos`/`parametros`):
```ruby
      get    'formatos',                        to: 'formatos#index'
      get    'formatos/marcadores',             to: 'formatos#marcadores'
      post   'formatos/:formato_id/plantillas', to: 'plantillas#create'
      get    'plantillas/:id/vista_previa',     to: 'plantillas#vista_previa'
      get    'plantillas/:id/original',         to: 'plantillas#original'
      post   'plantillas/:id/activar',          to: 'plantillas#activar'
      delete 'plantillas/:id',                  to: 'plantillas#destroy'
```
> `formatos/marcadores` debe ir **antes** que cualquier `formatos/:id`; aquí no hay `formatos/:id` GET, así que el orden mostrado funciona.

- [ ] **Step 4: Crear `FormatosController` + vista**

`app/controllers/api/v1/accounts/helic3/admin/formatos_controller.rb`:
```ruby
# frozen_string_literal: true

class Api::V1::Accounts::Helic3::Admin::FormatosController < Api::V1::Accounts::BaseController
  def index
    @formatos = Helic3::Catalogo::Formato.where(account: Current.account).order(:posicion)
  end

  def marcadores
    render json: Helic3::Formatos::Marcadores::DICCIONARIO
  end
end
```
`app/views/api/v1/accounts/helic3/admin/formatos/index.json.jbuilder`:
```ruby
json.array! @formatos do |formato|
  json.id formato.id
  json.codigo formato.codigo
  json.nombre formato.nombre
  json.activo formato.activo
  activa = formato.plantillas.activa.first
  json.activa_id activa&.id
  json.versiones formato.plantillas.order(version: :desc) do |p|
    json.id p.id
    json.version p.version
    json.estado p.estado
    json.marcadores p.marcadores
  end
end
```

- [ ] **Step 5: Crear `PlantillasController`**

`app/controllers/api/v1/accounts/helic3/admin/plantillas_controller.rb`:
```ruby
# frozen_string_literal: true

class Api::V1::Accounts::Helic3::Admin::PlantillasController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, only: %i[create activar destroy]

  def create
    formato = Helic3::Catalogo::Formato.find_by!(account: Current.account, id: params[:formato_id])
    resultado = Helic3::Formatos::SubirPlantilla.call(formato: formato, archivo: params[:archivo], user: current_user)
    if resultado.ok?
      render json: carga(resultado.plantilla).merge(advertencias: resultado.advertencias), status: :created
    else
      render json: { errores: resultado.errores }, status: :unprocessable_entity
    end
  end

  def vista_previa
    plantilla = plantilla_de_la_cuenta
    pdf = Helic3::Formatos::VistaPrevia.call(plantilla: plantilla, item: item_opcional, user: current_user)
    send_data pdf, type: 'application/pdf', disposition: 'inline', filename: "vista-previa-#{plantilla.id}.pdf"
  end

  def original
    plantilla = plantilla_de_la_cuenta
    send_data plantilla.original.download, filename: plantilla.original.filename.to_s,
                                           type: plantilla.original.content_type, disposition: 'attachment'
  end

  def activar
    plantilla = plantilla_de_la_cuenta
    Helic3::PlantillaFormato.transaction do
      plantilla.formato.plantillas.activa.where.not(id: plantilla.id).update_all(estado: 'retirada')
      plantilla.update!(estado: 'activa', activada_at: Time.current, activada_por_id: current_user.id)
    end
    render json: carga(plantilla)
  end

  def destroy
    plantilla = plantilla_de_la_cuenta
    if plantilla.destroy
      head :no_content
    else
      render json: { errores: plantilla.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def plantilla_de_la_cuenta
    Helic3::PlantillaFormato.find_by!(account: Current.account, id: params[:id])
  end

  def item_opcional
    return nil if params[:item_id].blank?

    Helic3::GarantiaItem.joins(:garantia)
                        .where(helic3_garantias: { account_id: Current.account.id })
                        .find(params[:item_id])
  end

  def carga(plantilla)
    { id: plantilla.id, formato_id: plantilla.formato_id, version: plantilla.version,
      estado: plantilla.estado, marcadores: plantilla.marcadores }
  end
end
```

- [ ] **Step 6: Correr specs (pasan)**

Run: `docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/controllers/api/v1/accounts/helic3/admin/`
Expected: PASS.

- [ ] **Step 7: rubocop + guardián + verificación de frontera + commit**

```
docker compose exec rails bundle exec rubocop app/controllers/api/v1/accounts/helic3/admin/
git diff --name-only origin/dev | grep -v -E "helic3|spec/|railpack.json|nixpacks.toml"   # debe imprimir SOLO config/routes.rb
git add -A && git commit --no-verify -m "feat(formatos): API admin de formatos y plantillas (FMT-02)"
```

---

### Task 7: Verificación final (los 10 CA + frontera)

**Files:** ninguno nuevo (corridas de verificación).

- [ ] **Step 1: Migraciones corren y revierten limpio [CA10]**

Run:
```
docker compose exec -e RAILS_ENV=test rails bundle exec rails db:migrate
docker compose exec -e RAILS_ENV=test rails bundle exec rails db:rollback STEP=2
docker compose exec -e RAILS_ENV=test rails bundle exec rails db:migrate
```
Expected: sin errores; `git diff db/schema.rb` muestra **solo** las tablas `helic3_catalogo_formatos` y `helic3_plantillas_formato`.

- [ ] **Step 2: Suite completa de FMT-02**

Run:
```
docker compose exec -e RAILS_ENV=test rails bundle exec rspec spec/services/helic3/formatos/ spec/models/helic3/plantilla_formato_spec.rb spec/models/helic3/catalogo/formato_spec.rb spec/controllers/api/v1/accounts/helic3/admin/
```
Expected: todo verde.

- [ ] **Step 3: rubocop + guardián sobre todo lo tocado**

Run:
```
docker compose exec rails bundle exec rubocop app/services/helic3/formatos/ app/models/helic3/ app/controllers/api/v1/accounts/helic3/admin/
PYTHONUTF8=1 python .claude/skills/revisar-oss/guard.py --staged
```
Expected: "no offenses" + "Sin hallazgos".

- [ ] **Step 4: Frontera — único upstream es routes.rb [CA10]**

Run: `git diff --name-only origin/dev | grep -v -E "helic3|spec/|railpack.json|nixpacks.toml"`
Expected: imprime **solo** `config/routes.rb`.

- [ ] **Step 5: Abrir PR a `integracion/entrega-7-formatos-pdf`** (cuando #110 esté mergeado) con el resumen y marcar la decisión 401/403 pendiente de Jhan.

## Notas de ejecución

- **Dependencia de secuencia:** el PR de FMT-02 se mergea **después** de #110 (FMT-01). Mientras tanto la rama parte de `feature/FMT-01-rev-libreoffice`; al mergearse #110 se re-apunta a `entrega-7`.
- **Factories:** este plan asume factories de `account`, `user` (con `role`) y los modelos Helic3. Si falta una factory para `Helic3::GarantiaItem`/`Helic3::Ticket`, usar `instance_double` en los specs de servicio (como en Task 3) y construir registros reales solo donde el controlador los necesite.
- **AGT-11:** `FECHA_COMPRA` devuelve `''` hasta que AGT-11 agregue `factura_fecha` a la ficha; el único cambio futuro es el método `fecha_compra` de `DatosDelFormato`.
