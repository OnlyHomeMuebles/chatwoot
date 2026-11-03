# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::NotificarCambioProcesoJob do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:evento) do
    Helic3::Evento.registrar!(ticket: ticket, tipo: 'proceso_avanzado', origen: 'humano', garantia: garantia,
                              payload: { 'item_id' => 1, 'proceso_id' => 1, 'proceso_anterior_id' => nil })
  end

  it 'delega en Helic3::Correos::NotificarCambioProceso con el evento' do
    expect(Helic3::Correos::NotificarCambioProceso).to receive(:call).with(evento: evento)

    described_class.perform_now(evento.id)
  end

  it 'si el evento ya no existe (se borro entre el encolado y la ejecucion), no hace nada' do
    expect(Helic3::Correos::NotificarCambioProceso).not_to receive(:call)

    expect { described_class.perform_now(-1) }.not_to raise_error
  end
end
