# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261016120000_fusiona_duplicados_y_blinda_catalogos_helic3.rb')

# Segunda migracion del saneamiento (continua la del #127): fusiona los duplicados
# que la primera dejo sin tocar y blinda las tablas con un CHECK. El dato sucio se
# inyecta con SQL DIRECTO, igual que entro en produccion (por fuera del modelo).
RSpec.describe FusionaDuplicadosYBlindaCatalogosHelic3 do
  let(:migration) { described_class.new }
  let(:account) { create(:account) }

  def correr(direccion)
    migration.suppress_messages { migration.public_send(direccion) }
  end

  # Escribe un codigo sucio saltandose el modelo (y su normalizes), como un import
  # externo o la consola de produccion.
  def ensuciar(fila, codigo)
    conexion = ActiveRecord::Base.connection
    conexion.execute(
      "UPDATE #{fila.class.table_name} SET codigo = #{conexion.quote(codigo)} WHERE id = #{fila.id}"
    )
  end

  # El schema de test YA trae los CHECK (viven en schema.rb). Para recrear el
  # estado PRE-migracion —cuando el dato sucio todavia podia entrar— hay que
  # quitarlos antes de inyectarlo; correr :up los vuelve a poner. Sin esto, el
  # propio CHECK que la migracion instala impediria montar el escenario a sanear.
  before do
    conexion = ActiveRecord::Base.connection
    described_class::MODELOS.each do |nombre|
      tabla = "Helic3::Catalogo::#{nombre}".constantize.table_name
      conexion.remove_check_constraint(tabla, name: "#{tabla}_codigo_slug", if_exists: true)
    end
  end

  describe 'fusion de duplicados' do
    # Bloqueante 2 (revision Jhan): gana la fila MAS referenciada (la original de
    # Karen, con su config y sus datos), no la de la semilla SIE-01 (codigo limpio
    # pero vacia). Y las referencias de las absorbidas se re-apuntan a ella.
    it 'elige como superviviente la fila con mas referencias y le re-apunta las demas' do
      karen = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía Karen', codigo: 'garantia_karen')
      semilla = Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
      Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'M1', codigo: 'm1', categoria: karen)
      Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'M2', codigo: 'm2', categoria: karen)
      motivo_semilla = Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'M3', codigo: 'm3', categoria: semilla)
      ensuciar(karen, 'garantia ') # colapsa con 'garantia', pero es la mas usada

      correr(:up)

      expect(Helic3::Catalogo::Categoria.exists?(karen.id)).to be(true)
      expect(Helic3::Catalogo::Categoria.exists?(semilla.id)).to be(false)
      expect(motivo_semilla.reload.categoria_id).to eq(karen.id) # la ref de la absorbida se re-apunta
      expect(karen.reload.codigo).to eq('garantia')
      expect(karen.nombre).to eq('Garantía Karen') # conserva la config de Karen
    end

    it 'si ninguna fila tiene referencias, conserva la de menor id (la original)' do
      primera = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva original', codigo: 'nueva_original')
      segunda = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
      ensuciar(primera, 'nueva ') # colapsa con 'nueva'; menor id gana aunque este sucia

      correr(:up)

      expect(Helic3::Catalogo::EtapaPqr.exists?(primera.id)).to be(true)
      expect(Helic3::Catalogo::EtapaPqr.exists?(segunda.id)).to be(false)
      expect(primera.reload.codigo).to eq('nueva')
    end

    # Bloqueante 1 (revision Jhan): resultado_propuesto_id vive en pqrs_metadata
    # (JSONB), no es una FK, asi que el re-apunte de REFERENCIAS no lo alcanza. Si no
    # se mueve, la propuesta pendiente en la cola de decisiones queda huerfana.
    it 're-apunta resultado_propuesto_id de las propuestas pendientes al fusionar resultados' do
      superviviente = Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Cerrar', codigo: 'cerrar')
      dup = Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Cerrar dup', codigo: 'cerrar_dup')
      ticket = create(:ticket, account: account, pqrs_metadata: { 'resultado_propuesto_id' => dup.id })
      ensuciar(dup, 'cerrar ') # colapsa con 'cerrar'

      correr(:up)

      expect(Helic3::Catalogo::Resultado.exists?(dup.id)).to be(false)
      expect(ticket.reload.pqrs_metadata['resultado_propuesto_id']).to eq(superviviente.id)
    end
  end

  describe 'normalizacion sin duplicado' do
    it 'limpia un codigo sucio aunque no choque con ninguna otra fila' do
      tipo = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo')
      ensuciar(tipo, 'Reclamo Formal ')

      correr(:up)

      expect(tipo.reload.codigo).to eq('reclamo_formal')
    end
  end

  describe 'blindaje con CHECK' do
    it 'rechaza un codigo mal formado metido por SQL directo (asi entro el bug)' do
      etapa = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')

      correr(:up)

      expect { ensuciar(etapa, 'con espacio') }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe 'robustez: no aborta el deploy' do
    def tiene_check?(tabla)
      ActiveRecord::Base.connection.check_constraints(tabla).any? { |c| c.name == "#{tabla}_codigo_slug" }
    end

    it 'si fusionar choca con un indice unico, revierte ese grupo, lo reporta y NO blinda esa tabla' do
      limpia = Helic3::Catalogo::Formato.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
      sucia = Helic3::Catalogo::Formato.create!(account: account, nombre: 'Garantía vieja', codigo: 'garantia_vieja')
      # dos plantillas con la MISMA version: re-apuntar formato_id chocaria con el
      # indice unico (formato_id, version) de helic3_plantillas_formato.
      Helic3::PlantillaFormato.create!(account: account, formato: limpia, version: 1)
      Helic3::PlantillaFormato.create!(account: account, formato: sucia, version: 1)
      ensuciar(sucia, ' garantia')

      expect { correr(:up) }.not_to raise_error
      expect(Helic3::Catalogo::Formato.exists?(sucia.id)).to be(true) # no se fusiono
      expect(tiene_check?('helic3_catalogo_formatos')).to be(false)   # no se blindo
      expect(tiene_check?('helic3_catalogo_etapas_pqr')).to be(true)  # las demas si
    end

    it 'si un codigo normaliza a vacio, lo reporta, no lo toca y NO blinda esa tabla' do
      tipo = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Simbolos', codigo: 'simbolos')
      ensuciar(tipo, '...') # parameterize('...') => '' : no es un slug valido

      expect { correr(:up) }.not_to raise_error
      expect(tipo.reload.codigo).to eq('...')
      expect(tiene_check?('helic3_catalogo_tipos')).to be(false)
    end
  end

  it 'el down es irreversible' do
    expect { correr(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
