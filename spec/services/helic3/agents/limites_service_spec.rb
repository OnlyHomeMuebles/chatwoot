# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Agents::LimitesService do
  def agente(horario: 'siempre', max_respuestas: nil, team_id: nil, mensaje_handoff: nil)
    instance_double(Helic3::Agente, horario: horario, max_respuestas: max_respuestas,
                                    team_id: team_id, mensaje_handoff: mensaje_handoff)
  end

  def inbox_con_horario(habilitado:, cerrado: false)
    inbox = instance_double(Inbox, working_hours_enabled?: habilitado)
    relacion = instance_double(ActiveRecord::Relation)
    allow(inbox).to receive(:working_hours).and_return(relacion)
    allow(relacion).to receive(:find_by).and_return(instance_double(WorkingHour, closed_now?: cerrado))
    inbox
  end

  def decision(agente:, inbox: nil, respuestas_previas: 0)
    described_class.new(agente: agente, inbox: inbox, respuestas_previas: respuestas_previas).evaluar
  end

  describe 'horario (crit 2)' do
    it 'deja sin IA cuando el agente es horario_atencion y el inbox esta cerrado' do
      d = decision(agente: agente(horario: 'horario_atencion'),
                   inbox: inbox_con_horario(habilitado: true, cerrado: true))

      expect(d.accion).to eq(:dejar_sin_ia)
      expect(d.motivo).to match(/horario/)
    end

    it 'responde si el agente es horario_atencion pero el inbox esta abierto' do
      d = decision(agente: agente(horario: 'horario_atencion'),
                   inbox: inbox_con_horario(habilitado: true, cerrado: false))

      expect(d.accion).to eq(:responder)
    end

    it "responde siempre si el agente es 'siempre', aunque el inbox este cerrado" do
      d = decision(agente: agente(horario: 'siempre'),
                   inbox: inbox_con_horario(habilitado: true, cerrado: true))

      expect(d.accion).to eq(:responder)
    end

    it 'responde si el inbox no tiene horario habilitado' do
      d = decision(agente: agente(horario: 'horario_atencion'),
                   inbox: inbox_con_horario(habilitado: false, cerrado: true))

      expect(d.accion).to eq(:responder)
    end
  end

  describe 'max_respuestas (crit 1)' do
    it 'deriva al equipo al alcanzar el tope de respuestas' do
      d = decision(agente: agente(max_respuestas: 3), respuestas_previas: 3)

      expect(d.accion).to eq(:derivar_equipo)
      expect(d.motivo).to match(/máximo de 3/)
    end

    it 'responde si aun no llega al tope' do
      d = decision(agente: agente(max_respuestas: 3), respuestas_previas: 2)

      expect(d.accion).to eq(:responder)
    end

    it 'sin tope configurado, responde siempre' do
      d = decision(agente: agente(max_respuestas: nil), respuestas_previas: 50)

      expect(d.accion).to eq(:responder)
    end
  end

  it 'el horario tiene prioridad sobre el tope de respuestas' do
    d = decision(agente: agente(horario: 'horario_atencion', max_respuestas: 1),
                 inbox: inbox_con_horario(habilitado: true, cerrado: true),
                 respuestas_previas: 5)

    expect(d.accion).to eq(:dejar_sin_ia)
  end
end
