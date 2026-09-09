# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Casos::Radicar do
  let(:account) { create(:account) }

  # la porcion minima del catalogo que la radicacion necesita
  let!(:etapa_nueva) do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
  end
  let(:garantia) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia')
  end
  let(:comercial) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Comercial', codigo: 'comercial')
  end
  let(:informacion) do
    Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Información', codigo: 'informacion',
                                        genera_radicado: false)
  end
  let(:reclamo) do
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo',
                                   plazo_dias_habiles: 15)
  end
  let(:sugerencia) do
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Sugerencia', codigo: 'sugerencia')
  end
  let(:motivo_garantia) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)
  end
  let(:motivo_retracto) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Retracto de compra',
                                        codigo: 'retracto_compra', categoria: comercial,
                                        plazo_dias_habiles: 5)
  end
  let(:motivo_informacion) do
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Información general',
                                        codigo: 'informacion_general', categoria: informacion)
  end

  def radicar(**argumentos)
    described_class.new(account: account, titulo: 'Sofá con chapilla levantada', **argumentos).call
  end

  describe 'el reloj legal' do
    it 'vence 15 dias habiles despues, saltando fines de semana y festivos, en zona Bogota' do
      # viernes 9 de octubre de 2026, 4:00 p.m. en Bogota
      travel_to Time.find_zone!('America/Bogota').local(2026, 10, 9, 16, 0) do
        ticket = radicar(tipo: reclamo, motivo_pqr: motivo_garantia)

        calendario = Helic3::CalendarioHabil.new
        expect(ticket.radicada_at).to be_present
        expect(calendario.dias_habiles_entre(Date.new(2026, 10, 9),
                                             ticket.plazo_respuesta_vence_at.to_date)).to eq(15)
        expect(calendario.es_habil?(ticket.plazo_respuesta_vence_at.to_date)).to be(true)
      end
    end

    it 'salta el festivo: radicado la vispera de Navidad con 1 dia de plazo, vence el lunes 28' do
      tipo_un_dia = Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Express', codigo: 'express',
                                                   plazo_dias_habiles: 1)
      # jueves 24 de diciembre de 2026; el viernes 25 es Navidad y el fin de
      # semana no cuenta: el siguiente dia habil es el lunes 28
      travel_to Time.find_zone!('America/Bogota').local(2026, 12, 24, 10, 0) do
        ticket = radicar(tipo: tipo_un_dia)

        expect(ticket.plazo_respuesta_vence_at.to_date).to eq(Date.new(2026, 12, 28))
      end
    end

    it 'el motivo le gana al tipo: un retracto vence a 5 dias habiles, no a 15' do
      ticket = radicar(tipo: reclamo, motivo_pqr: motivo_retracto)

      calendario = Helic3::CalendarioHabil.new
      radicada = ticket.radicada_at.in_time_zone('America/Bogota').to_date
      expect(calendario.dias_habiles_entre(radicada, ticket.plazo_respuesta_vence_at.to_date)).to eq(5)
    end

    it 'sin plazo en motivo ni tipo, cae al parametro de cuenta' do
      Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_respuesta_pqr',
                                          valor: '10', unidad: 'dias_habiles')
      ticket = radicar(tipo: sugerencia)

      calendario = Helic3::CalendarioHabil.new
      radicada = ticket.radicada_at.in_time_zone('America/Bogota').to_date
      expect(calendario.dias_habiles_entre(radicada, ticket.plazo_respuesta_vence_at.to_date)).to eq(10)
    end

    it 'si falta el parametro y ningun catalogo trae plazo, el error nombra la clave' do
      expect { radicar(tipo: sugerencia) }
        .to raise_error(Helic3::Casos::Radicar::ParametroFaltante, /plazo_respuesta_pqr/)
    end
  end

  describe 'el caso de Informacion' do
    it 'se crea sin plazo y sin numero de radicado, pero se crea' do
      ticket = radicar(motivo_pqr: motivo_informacion)

      expect(ticket).to be_persisted
      expect(ticket.plazo_respuesta_vence_at).to be_nil
      expect(ticket.numero_radicado).to be_nil
      expect(ticket.display_id).to be_present
    end
  end

  describe 'la clasificacion' do
    it 'deriva la categoria del motivo: no hay forma de pasarla por fuera' do
      ticket = radicar(tipo: reclamo, motivo_pqr: motivo_retracto)

      expect(ticket.categoria).to eq(comercial)
      expect(described_class.instance_method(:initialize).parameters.map(&:last))
        .not_to include(:categoria)
    end

    it 'un motivo de otra cuenta hace fallar la creacion' do
      otra = create(:account)
      cat_ajena = Helic3::Catalogo::Categoria.create!(account: otra, nombre: 'Garantía', codigo: 'garantia')
      motivo_ajeno = Helic3::Catalogo::MotivoPqr.create!(account: otra, nombre: 'Garantía de producto',
                                                         codigo: 'garantia_producto', categoria: cat_ajena)

      expect { radicar(tipo: reclamo, motivo_pqr: motivo_ajeno) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'los sellos y el origen' do
    it 'nace en etapa Nueva, con radicada_at sellado' do
      ticket = radicar(tipo: reclamo)

      expect(ticket.etapa).to eq(etapa_nueva)
      expect(ticket.radicada_at).to be_present
    end

    it 'guarda el origen y el numero de orden en pqrs_metadata, distinguibles' do
      del_agente = radicar(tipo: reclamo, origen: :agente, numero_orden: 'OH-4471')
      de_persona = radicar(tipo: reclamo)

      expect(del_agente.pqrs_metadata).to include('origen' => 'agente', 'numero_orden' => 'OH-4471')
      expect(de_persona.pqrs_metadata).to include('origen' => 'humano')
      expect(de_persona.pqrs_metadata).not_to have_key('numero_orden')
    end

    it 'si la cuenta no tiene la etapa "nueva", revienta en vez de silenciarse' do
      etapa_nueva.update!(activo: false)

      expect { radicar(tipo: reclamo) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
