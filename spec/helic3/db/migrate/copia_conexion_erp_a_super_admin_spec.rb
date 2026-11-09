# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261109120000_copia_conexion_erp_a_super_admin.rb')

# ERP-16: copia una sola vez el modo y la conexion de Siesa del entorno a Super Admin.
RSpec.describe CopiaConexionErpASuperAdmin do
  let(:migration) { described_class.new }

  def correr
    migration.suppress_messages { migration.up }
  end

  def valor(clave)
    InstallationConfig.find_by(name: clave)&.value
  end

  it 'copia lo que haya en el entorno a su clave de Super Admin' do
    with_modified_env HELIC3_ERP_MODO: 'siesa', SIESA_HUB_CONNI_KEY: 'key-del-entorno' do
      correr
    end

    expect(valor('HELIC3_ERP_MODO')).to eq('siesa')
    expect(valor('HELIC3_SIESA_HUB_CONNI_KEY')).to eq('key-del-entorno')
  end

  it 'no pisa un valor ya guardado en Super Admin' do
    InstallationConfig.create!(name: 'HELIC3_SIESA_HUB_CONNI_KEY', value: 'key-de-la-pagina', locked: false)

    with_modified_env SIESA_HUB_CONNI_KEY: 'key-del-entorno' do
      correr
    end

    expect(valor('HELIC3_SIESA_HUB_CONNI_KEY')).to eq('key-de-la-pagina')
  end

  it 'llena una fila que existe pero esta vacia' do
    InstallationConfig.create!(name: 'HELIC3_SIESA_HUB_BASE_URL', value: '', locked: false)

    with_modified_env SIESA_HUB_BASE_URL: 'https://apiqa.siesacloud.com' do
      correr
    end

    expect(valor('HELIC3_SIESA_HUB_BASE_URL')).to eq('https://apiqa.siesacloud.com')
  end

  it 'corrida dos veces, la segunda no cambia nada' do
    with_modified_env HELIC3_ERP_MODO: 'simulado' do
      correr
      expect { correr }.not_to(change { InstallationConfig.where('name LIKE ?', 'HELIC3_%').pluck(:name, :updated_at) })
    end
  end

  it 'sin nada en el entorno no crea filas (el modo queda en desactivado)' do
    with_modified_env HELIC3_ERP_MODO: nil, SIESA_HUB_BASE_URL: nil, SIESA_HUB_CLIENT_ID: nil,
                      SIESA_HUB_CONNI_KEY: nil, SIESA_HUB_CONNI_TOKEN: nil, SIESA_HUB_ID_COMPANIA: nil,
                      SIESA_HUB_CONSULTA_CLIENTES: nil, SIESA_HUB_CONSULTA_COMPRAS: nil do
      expect { correr }.not_to change(InstallationConfig, :count)
    end
  end
end
