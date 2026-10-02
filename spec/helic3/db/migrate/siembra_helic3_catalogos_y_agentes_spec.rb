# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261002120000_siembra_helic3_catalogos_y_agentes.rb')

# SIE-01: el grueso de la siembra se prueba en los specs de los dos seeders. Aqui
# se cubre lo propio de la MIGRACION: que siembre todas las cuentas que existan
# (Account.find_each), que sea idempotente al nivel de la migracion (CA3) y que el
# down no borre nada (CA9).
RSpec.describe SiembraHelic3CatalogosYAgentes do
  let(:migration) { described_class.new }

  def correr(direccion)
    migration.suppress_messages { migration.public_send(direccion) }
  end

  it 'siembra catalogos, parametros y agentes de TODAS las cuentas existentes' do
    cuentas = create_list(:account, 2)

    correr(:up)

    cuentas.each do |cuenta|
      expect(Helic3::Catalogo::Categoria.where(account: cuenta).count).to eq(6)
      expect(Helic3::Catalogo::MotivoPqr.where(account: cuenta).count).to eq(7)
      expect(Helic3::Catalogo::Parametro.where(account: cuenta).count).to eq(19)
      expect(Helic3::Agente.where(account: cuenta).count).to eq(5)
    end
  end

  it 'es idempotente: correr up dos veces no cambia los conteos (CA3)' do
    create(:account)
    correr(:up)

    expect { correr(:up) }
      .not_to(change { [Helic3::Catalogo::Categoria.count, Helic3::Catalogo::Parametro.count, Helic3::Agente.count] })
  end

  it 'el down no borra nada (CA9)' do
    cuenta = create(:account)
    correr(:up)

    expect { correr(:down) }
      .not_to(change { Helic3::Catalogo::Categoria.where(account: cuenta).count })
  end
end
