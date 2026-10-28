# frozen_string_literal: true

require 'rails_helper'

# ERP-14: cache por cuenta+cedula del resultado del ERP (cliente + compras). El wizard,
# la radicacion y el agente leen lo mismo sin volver a llamar a Siesa; vence a las
# erp_cache_horas (24 por defecto) y "Volver a consultar" lo fuerza con refrescar:.
RSpec.describe Helic3::Erp::Cache do
  let(:account) { create(:account) }

  around do |ejemplo|
    with_modified_env HELIC3_ERP_MODO: 'simulado' do
      ejemplo.run
    end
  end

  it 'la 1ra consulta llama al adaptador y guarda la fila' do
    expect do
      resultado = described_class.consultar(account: account, cedula: '1032456789')
      expect(resultado.cliente.nombre).to eq('Ana Ruiz')
      expect(resultado.compras.map(&:numero)).to contain_exactly('FV-1001', 'FV-1002')
    end.to change(Helic3::ErpConsulta, :count).by(1)
  end

  it 'la 2da consulta vigente NO vuelve a llamar al adaptador y rehidrata los items' do
    described_class.consultar(account: account, cedula: '1032456789') # llena el cache

    expect(Helic3::Erp).not_to receive(:adapter)
    resultado = described_class.consultar(account: account, cedula: '1032456789')

    expect(resultado.cliente.nombre).to eq('Ana Ruiz')
    factura = resultado.compras.find { |c| c.numero == 'FV-1001' }
    expect(factura.items.first).to have_attributes(referencia: 'MIL-200', cantidad: 2, valor: 900_000)
  end

  it 'refrescar: true vuelve a consultar aunque haya fila vigente' do
    described_class.consultar(account: account, cedula: '1032456789')

    expect(Helic3::Erp).to receive(:adapter).and_call_original.at_least(:once)
    described_class.consultar(account: account, cedula: '1032456789', refrescar: true)
  end

  it 'una fila vencida (mas vieja que erp_cache_horas) vuelve a consultar' do
    described_class.consultar(account: account, cedula: '1032456789')
    Helic3::ErpConsulta.where(account: account).update_all(consultado_at: 25.hours.ago)

    expect(Helic3::Erp).to receive(:adapter).and_call_original.at_least(:once)
    described_class.consultar(account: account, cedula: '1032456789')
  end

  it 'una cedula sin cliente guarda la fila igual (compras vacias)' do
    resultado = described_class.consultar(account: account, cedula: '99999999')

    expect(resultado.cliente).to be_nil
    expect(resultado.compras).to eq([])
    expect(Helic3::ErpConsulta.where(account: account, cedula: '99999999')).to exist
  end

  it 'una fila vigente con forma vieja (campo desconocido) no da 503: reconsulta al adaptador' do
    described_class.consultar(account: account, cedula: '1032456789') # llena el cache
    # Simula una fila guardada por una version anterior con un campo que el contrato ya no tiene:
    # Customer es Data con keywords estrictos, asi que rehidratarla reventaria con ArgumentError.
    Helic3::ErpConsulta.where(account: account, cedula: '1032456789')
                       .update_all(cliente: { cedula: '1032456789', nombre: 'Ana Ruiz', campo_viejo: 'x' })

    expect(Helic3::Erp).to receive(:adapter).and_call_original.at_least(:once)
    resultado = described_class.consultar(account: account, cedula: '1032456789')

    expect(resultado.cliente.nombre).to eq('Ana Ruiz') # vuelve del adaptador, sin tumbar el wizard
  end
end
