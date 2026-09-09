# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::Resolver do
  let(:account) { create(:account) }

  # la etapa que detiene el reloj: responder! la busca con find_by!
  let!(:respondida) do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                       detiene_reloj: true)
  end

  # resultados con distintas marcas del catalogo
  let(:con_info) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Resuelta con información',
                                        codigo: 'resuelta_info', cierra_pqr: true)
  end
  let(:trasladada) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Trasladada a otra área',
                                        codigo: 'trasladada_otra_area', cierra_pqr: false)
  end
  let(:garantia_negada) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'No procede garantía',
                                        codigo: 'garantia_negada', cierra_pqr: true,
                                        aprobacion_humana: true)
  end

  let(:ticket) { create(:ticket, account: account) }

  def resolver(resultado:, origen: :humano)
    described_class.new(ticket: ticket, resultado: resultado, origen: origen).call
  end

  describe 'un resultado que cierra la PQR' do
    it 'sella respondida_at, deja la etapa que detiene el reloj y lo marca detenido' do
      resolver(resultado: con_info)

      expect(ticket.respondida_at).to be_present
      expect(ticket.etapa).to eq(respondida)
      expect(ticket).to be_reloj_detenido
      expect(ticket.resultado).to eq(con_info)
    end
  end

  describe 'un resultado que NO cierra la PQR' do
    it 'no detiene el reloj ni sella respondida_at, pero si asigna el resultado' do
      resolver(resultado: trasladada)

      expect(ticket.respondida_at).to be_nil
      expect(ticket).not_to be_reloj_detenido
      expect(ticket.resultado).to eq(trasladada)
    end
  end

  describe 'aprobacion humana propuesta por el agente' do
    it 'no aplica el resultado, guarda la propuesta y deja el reloj corriendo' do
      resolver(resultado: garantia_negada, origen: :agente)

      expect(ticket.resultado_id).to be_nil
      expect(ticket.respondida_at).to be_nil
      expect(ticket).not_to be_reloj_detenido
      expect(ticket.pqrs_metadata['resultado_propuesto_id']).to eq(garantia_negada.id)
    end
  end

  describe 'aprobacion humana aplicada por un humano' do
    it 'si aplica el resultado y detiene el reloj' do
      resolver(resultado: garantia_negada, origen: :humano)

      expect(ticket.resultado).to eq(garantia_negada)
      expect(ticket).to be_reloj_detenido
    end

    it 'limpia una propuesta que el agente habia dejado antes' do
      resolver(resultado: garantia_negada, origen: :agente) # el agente propone
      resolver(resultado: garantia_negada, origen: :humano) # el humano aprueba

      expect(ticket.pqrs_metadata).not_to have_key('resultado_propuesto_id')
    end
  end

  describe 'idempotencia' do
    it 'resolver dos veces no cambia respondida_at' do
      resolver(resultado: con_info)
      sello = ticket.respondida_at

      resolver(resultado: con_info)
      expect(ticket.reload.respondida_at).to eq(sello)
    end
  end
end
