# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261019130000_remapea_etapas_pqr_a_tres_helic3.rb')

# Migracion de DATOS: remapea las PQR existentes de las 4 etapas viejas a las 3 del
# mockup (Nuevo/En gestion/Solucionado), renombrando in situ y fundiendo Cerrada.
RSpec.describe RemapeaEtapasPqrATresHelic3 do
  let(:migration) { described_class.new }
  let(:account) { create(:account) }

  def correr(direccion)
    migration.suppress_messages { migration.public_send(direccion) }
  end

  # Escribe un codigo sucio saltandose el modelo (y su normalizes), como entro en
  # produccion por Excel/consola (asi se colo el 'nueva ' que rompio la radicacion).
  def ensuciar(fila, codigo)
    conexion = ActiveRecord::Base.connection
    conexion.execute("UPDATE #{fila.class.table_name} SET codigo = #{conexion.quote(codigo)} WHERE id = #{fila.id}")
  end

  # Si el schema de test ya trae el CHECK de codigo (lo instala la migracion de #127),
  # hay que quitarlo para montar el codigo sucio que simula el estado real de produccion.
  before do
    ActiveRecord::Base.connection.remove_check_constraint(
      'helic3_catalogo_etapas_pqr', name: 'helic3_catalogo_etapas_pqr_codigo_slug', if_exists: true
    )
  end

  # las 4 etapas tal como estaban sembradas en produccion antes del cambio
  def sembrar_viejas
    {
      nueva: Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva', posicion: 0),
      analisis: Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'En análisis', codigo: 'en_analisis', posicion: 1),
      respondida: Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida', detiene_reloj: true, posicion: 2),
      cerrada: Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Cerrada', codigo: 'cerrada', posicion: 3)
    }
  end

  describe 'renombrado 4 -> 3' do
    it 'deja exactamente las 3 etapas nuevas, en orden' do
      sembrar_viejas

      correr(:up)

      codigos = Helic3::Catalogo::EtapaPqr.where(account: account).order(:posicion).pluck(:codigo)
      expect(codigos).to eq(%w[nuevo en_gestion solucionado])
    end

    it 'marca Nuevo como la unica inicial y Solucionado como el unico que detiene el reloj' do
      sembrar_viejas

      correr(:up)

      expect(Helic3::Catalogo::EtapaPqr.where(account: account, inicial: true).pluck(:codigo)).to eq(['nuevo'])
      expect(Helic3::Catalogo::EtapaPqr.where(account: account, detiene_reloj: true).pluck(:codigo)).to eq(['solucionado'])
    end
  end

  describe 'tolera codigos viejos sucios (revision Jhan)' do
    it 'remapea aunque el codigo tenga espacios o mayusculas (btrim + lower)' do
      v = sembrar_viejas
      ensuciar(v[:nueva], 'Nueva ')        # mayuscula + espacio final
      ensuciar(v[:analisis], ' en_analisis') # espacio inicial

      correr(:up)

      codigos = Helic3::Catalogo::EtapaPqr.where(account: account).order(:posicion).pluck(:codigo)
      expect(codigos).to eq(%w[nuevo en_gestion solucionado])
    end
  end

  describe 'fusion de Cerrada' do
    it 'funde Cerrada en Solucionado y re-apunta sus tickets, sin perderlos' do
      v = sembrar_viejas
      ticket = create(:ticket, account: account, etapa: v[:cerrada])

      correr(:up)

      expect(Helic3::Catalogo::EtapaPqr.find_by(account: account, codigo: 'cerrada')).to be_nil
      expect(ticket.reload.etapa.codigo).to eq('solucionado')
    end
  end

  describe 'idempotencia' do
    it 'no rompe una cuenta que ya tiene las 3 etapas nuevas' do
      Helic3::Catalogo::SeederService.new(account).sembrar!

      expect { correr(:up) }.not_to raise_error
      codigos = Helic3::Catalogo::EtapaPqr.where(account: account).order(:posicion).pluck(:codigo)
      expect(codigos).to eq(%w[nuevo en_gestion solucionado])
    end
  end

  it 'el down es irreversible' do
    expect { correr(:down) }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
