# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Evento do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:actor) { create(:user, account: account) }

  describe '.registrar!' do
    it 'persiste el evento con actor, origen y payload; la cuenta sale del ticket' do
      evento = described_class.registrar!(ticket: ticket, tipo: 'radicada', origen: :humano,
                                          actor: actor, payload: { 'motivo' => 'garantia_producto' })

      expect(evento).to have_attributes(tipo: 'radicada', origen: 'humano', actor: actor, account: account)
      expect(evento.payload).to eq('motivo' => 'garantia_producto')
      expect(ticket.reload.eventos).to include(evento)
    end

    it 'rechaza un tipo fuera de la lista cerrada' do
      expect { described_class.registrar!(ticket: ticket, tipo: 'inventado', origen: :humano) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'rechaza un origen que no sea humano ni agente' do
      expect { described_class.registrar!(ticket: ticket, tipo: 'radicada', origen: :marciano) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'integracion con Resolver' do
    let(:resultado) do
      Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Resuelta con información',
                                          codigo: 'resuelta_info', cierra_pqr: true)
    end

    before do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                         detiene_reloj: true)
    end

    it 'registra resultado_aplicado y respondida al resolver, con el actor' do
      Helic3::Casos::Resolver.new(ticket: ticket, resultado: resultado, actor: actor, origen: :humano).call

      tipos = ticket.reload.eventos.pluck(:tipo)
      expect(tipos).to include('resultado_aplicado', 'respondida')
      expect(ticket.eventos.find_by(tipo: 'resultado_aplicado').actor).to eq(actor)
    end

    it 'no duplica eventos al resolver dos veces (idempotente)' do
      2.times { Helic3::Casos::Resolver.new(ticket: ticket, resultado: resultado, origen: :humano).call }

      expect(ticket.reload.eventos.where(tipo: 'resultado_aplicado').count).to eq(1)
      expect(ticket.eventos.where(tipo: 'respondida').count).to eq(1)
    end

    it 'registra solo resultado_propuesto cuando el agente propone algo que exige aprobacion' do
      pendiente = Helic3::Catalogo::Resultado.create!(account: account, nombre: 'No procede garantía',
                                                      codigo: 'no_procede', cierra_pqr: true,
                                                      aprobacion_humana: true)

      Helic3::Casos::Resolver.new(ticket: ticket, resultado: pendiente, origen: :agente).call

      expect(ticket.reload.eventos.pluck(:tipo)).to eq(['resultado_propuesto'])
    end
  end

  describe 'integracion con la apertura de garantia' do
    let(:procede) do
      Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Procede garantía',
                                          codigo: 'procede_garantia', cierra_pqr: true, abre_garantia: true)
    end

    before do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                         detiene_reloj: true)
      Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                                codigo: 'visita_tecnica', posicion: 0)
      Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales',
                                                tecnico_propio: true, origen_ruta: 'visita_tecnica')
    end

    it 'registra garantia_abierta apuntando a la garantia creada' do
      ciudad = Helic3::Catalogo::CoberturaCiudad.find_by(account: account, codigo: 'manizales')
      Helic3::Casos::Resolver.new(ticket: ticket, resultado: procede, origen: :agente,
                                  garantia: { cobertura_ciudad: ciudad,
                                              items: [{ producto_nombre: 'Sofá' }] }).call

      evento = ticket.reload.eventos.find_by(tipo: 'garantia_abierta')
      expect(evento).to be_present
      expect(evento.garantia).to eq(ticket.garantia)
    end
  end

  describe 'integracion con Radicar' do
    it 'registra radicada con el creator como actor' do
      Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
      tipo = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo',
                                            plazo_dias_habiles: 15)

      nuevo = Helic3::Casos::Radicar.new(account: account, titulo: 'Sofá con falla',
                                         tipo: tipo, creator: actor, origen: :humano).call

      evento = nuevo.eventos.find_by(tipo: 'radicada')
      expect(evento).to be_present
      expect(evento).to have_attributes(actor: actor, origen: 'humano')
    end
  end
end
