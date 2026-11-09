# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::ExpedienteVigente do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }

  def para
    described_class.para(account: account, conversation_id: conversation.id)
  end

  it 'sin conversation_id, es nil' do
    expect(described_class.para(account: account, conversation_id: nil)).to be_nil
  end

  it 'un expediente vigente (sin responder) lo devuelve' do
    ticket = create(:ticket, account: account, conversation: conversation)

    expect(para).to eq(ticket)
  end

  it 'respondido hace 5 minutos (dentro de la ventana por defecto, 10), lo devuelve' do
    ticket = create(:ticket, account: account, conversation: conversation)
    ticket.update_columns(respondida_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(para).to eq(ticket)
  end

  it 'respondido hace 20 minutos (fuera de la ventana por defecto), es nil' do
    ticket = create(:ticket, account: account, conversation: conversation)
    ticket.update_columns(respondida_at: 20.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(para).to be_nil
  end

  it 'con el parametro en 30 minutos, uno respondido hace 20 minutos SI bloquea' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'ventana_doble_radicacion_minutos',
                                        valor: '30', unidad: 'cantidad')
    ticket = create(:ticket, account: account, conversation: conversation)
    ticket.update_columns(respondida_at: 20.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(para).to eq(ticket)
  end

  it 'sin el parametro sembrado en la cuenta, usa 10 minutos por defecto' do
    ticket = create(:ticket, account: account, conversation: conversation)
    ticket.update_columns(respondida_at: 9.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

    expect(Helic3::Catalogo::Parametro.where(account: account,
                                             clave: 'ventana_doble_radicacion_minutos')).to be_none
    expect(para).to eq(ticket)
  end

  it 'con varios expedientes vigentes, devuelve el mas antiguo' do
    viejo = create(:ticket, account: account, conversation: conversation, created_at: 2.days.ago)
    create(:ticket, account: account, conversation: conversation, created_at: 1.day.ago)

    expect(para).to eq(viejo)
  end
end
