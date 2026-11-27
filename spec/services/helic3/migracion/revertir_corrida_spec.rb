# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::RevertirCorrida do
  let(:account) { create(:account) }
  let!(:etapa) { Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nuevo', codigo: 'nuevo', inicial: true) }
  let(:corrida) { Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'revirtiendo') }

  let!(:migrado) { Helic3::Ticket.create!(account: account, title: 'Migrado', etapa: etapa) }
  let!(:garantia) { Helic3::Garantia.create!(account: account, ticket: migrado) }
  let!(:ajeno) { Helic3::Ticket.create!(account: account, title: 'No migrado', etapa: etapa) }
  let!(:fila) do
    travel_to(1.minute.from_now) do
      corrida.casos.create!(account: account, consecutivo: 100, resultado: 'ok', ticket: migrado, garantia: garantia)
    end
  end

  it 'borra solo los PQR que creó la corrida y la deja revertida' do
    described_class.call(corrida: corrida)

    expect(Helic3::Ticket.where(id: migrado.id)).to be_empty
    expect(Helic3::Ticket.where(id: ajeno.id)).to exist
    expect(corrida.reload.estado).to eq('revertida')
  end

  it 'no revierte nada y lista los casos modificados después de migrar' do
    travel_to(2.minutes.from_now) { migrado.update!(title: 'Editado') }

    described_class.call(corrida: corrida)

    expect(Helic3::Ticket.where(id: migrado.id)).to exist
    expect(corrida.reload.estado).to eq('completada')
    expect(corrida.mensaje_error).to include('1 casos se modificaron', '100')
  end
end
