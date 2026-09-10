# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::RegistrarDatos do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  def registrar(campos, fuente)
    described_class.new(ticket: ticket, campos: campos, fuente: fuente).call
  end

  it 'crea la ficha 1:1 y guarda el valor con su fuente' do
    datos = registrar({ direccion: 'Calle 1' }, :ia)

    expect(datos.direccion).to eq('Calle 1')
    expect(datos.fuentes['direccion']).to eq('ia')
    expect(ticket.reload.datos).to eq(datos)
  end

  it 'no crea una segunda ficha al registrar dos veces' do
    registrar({ direccion: 'A' }, :ia)
    registrar({ ciudad: 'Armenia' }, :ia)

    expect(Helic3::TicketDato.where(ticket: ticket).count).to eq(1)
  end

  it 'un campo vacio no borra el valor que ya habia' do
    registrar({ direccion: 'Calle 1' }, :humano)
    registrar({ direccion: '' }, :humano)

    expect(ticket.reload.datos.direccion).to eq('Calle 1')
  end

  it 'guarda el detalle tipificado por id' do
    detalle = Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Tela motosa',
                                                          codigo: 'tela_motosa')
    datos = registrar({ detalle_tipificado_id: detalle.id }, :ia)

    expect(datos.detalle_tipificado).to eq(detalle)
    expect(datos.fuentes['detalle_tipificado_id']).to eq('ia')
  end

  describe 'precedencia humano > erp > ia (las seis combinaciones)' do
    {
      %w[ia erp] => true,
      %w[ia humano] => true,
      %w[erp humano] => true,
      %w[erp ia] => false,
      %w[humano erp] => false,
      %w[humano ia] => false
    }.each do |(previa, nueva), pisa|
      it "#{nueva} #{pisa ? 'pisa' : 'NO pisa'} a #{previa}" do
        registrar({ direccion: 'vieja' }, previa.to_sym)
        registrar({ direccion: 'nueva' }, nueva.to_sym)

        expect(ticket.reload.datos.direccion).to eq(pisa ? 'nueva' : 'vieja')
        expect(ticket.datos.fuentes['direccion']).to eq(pisa ? nueva : previa)
      end
    end
  end
end
