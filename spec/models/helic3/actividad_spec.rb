# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Actividad do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:autor) { create(:user, account: account, name: 'Karen Vanegas') }

  it 'toma la cuenta del expediente y guarda la instantanea del nombre del autor' do
    actividad = ticket.actividades.create!(autor: autor, titulo: 'Llamada al cliente', detalle: 'Agenda visita')

    expect(actividad.account).to eq(account)
    expect(actividad.autor_nombre).to eq('Karen Vanegas')
  end

  it 'conserva el nombre del autor si el usuario se borra' do
    actividad = ticket.actividades.create!(autor: autor, titulo: 'Llamada', detalle: 'Agenda visita')

    autor.destroy!

    expect(actividad.reload.autor_id).to be_nil
    expect(actividad.autor_nombre).to eq('Karen Vanegas')
  end

  it 'exige titulo y detalle' do
    actividad = ticket.actividades.build(autor: autor, titulo: '', detalle: ' ')

    expect(actividad).not_to be_valid
    expect(actividad.errors.attribute_names).to contain_exactly(:titulo, :detalle)
  end

  it 'limita el titulo a 120 caracteres y el detalle a 2000' do
    valida = ticket.actividades.build(autor: autor, titulo: 'a' * 120, detalle: 'b' * 2000)
    larga = ticket.actividades.build(autor: autor, titulo: 'a' * 121, detalle: 'b' * 2001)

    expect(valida).to be_valid
    expect(larga).not_to be_valid
    expect(larga.errors.attribute_names).to contain_exactly(:titulo, :detalle)
  end

  it 'recientes las ordena de la mas nueva a la mas antigua' do
    vieja = ticket.actividades.create!(autor: autor, titulo: 'Vieja', detalle: 'x', created_at: 2.days.ago)
    nueva = ticket.actividades.create!(autor: autor, titulo: 'Nueva', detalle: 'x')

    expect(ticket.actividades.recientes).to eq([nueva, vieja])
  end

  it 'se borran con el expediente' do
    ticket.actividades.create!(autor: autor, titulo: 'Llamada', detalle: 'x')

    expect { ticket.destroy! }.to change(described_class, :count).by(-1)
  end
end
