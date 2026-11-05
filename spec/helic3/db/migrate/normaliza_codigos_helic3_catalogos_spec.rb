# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261015120000_normaliza_codigos_helic3_catalogos.rb')

# Migracion de DATOS que limpia los codigos sucios de produccion (el bug del
# "nueva " con espacio que daba 404 al radicar). El dato sucio se inyecta con SQL
# DIRECTO (no con el modelo) porque asi es como entro en produccion: por fuera de
# ActiveRecord (Excel/CSV/consola), evadiendo el normalizes nuevo.
RSpec.describe NormalizaCodigosHelic3Catalogos do
  let(:migration) { described_class.new }
  let(:account) { create(:account) }

  def correr(direccion)
    migration.suppress_messages { migration.public_send(direccion) }
  end

  # Escribe un codigo "sucio" saltandose el modelo (y su normalizes), como un
  # import externo.
  def ensuciar(fila, codigo)
    conexion = ActiveRecord::Base.connection
    conexion.execute(
      "UPDATE #{fila.class.table_name} SET codigo = #{conexion.quote(codigo)} WHERE id = #{fila.id}"
    )
  end

  it 'limpia un codigo con espacios (el caso que rompia la radicacion)' do
    etapa = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
    ensuciar(etapa, 'nueva ')

    correr(:up)

    expect(etapa.reload.codigo).to eq('nueva')
  end

  it 'pasa a slug un codigo que no lo era' do
    tipo = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Retracto', codigo: 'retracto')
    ensuciar(tipo, 'Retracto de compra ')

    correr(:up)

    expect(tipo.reload.codigo).to eq('retracto_de_compra')
  end

  it 'NO fusiona un duplicado: conserva el codigo sucio para revisarlo a mano' do
    limpia = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Cerrada', codigo: 'cerrada')
    sucia = Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Cerrada vieja', codigo: 'cerrada_vieja')
    ensuciar(sucia, ' cerrada') # al limpiar chocaria con 'cerrada'

    correr(:up)

    expect(sucia.reload.codigo).to eq(' cerrada')
    expect(limpia.reload.codigo).to eq('cerrada')
  end

  it 'el down es irreversible' do
    expect { correr(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
