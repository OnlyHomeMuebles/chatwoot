# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20261105130000_agrega_consultar_cliente_erp_a_agente_pqrs.rb')

# ERP-06/T3: migracion idempotente que pone al dia un agente_pqrs sembrado ANTES
# de que este ticket agregara consultar_cliente_erp a su lista de herramientas
# (Helic3::Agents::SeederService#sembrar! solo crea, no pisa lo que ya existe).
RSpec.describe AgregaConsultarClienteErpAAgentePqrs do
  let(:migration) { described_class.new }
  let(:account) { create(:account) }

  def correr
    migration.suppress_messages { migration.up }
  end

  def crear_agente(codigo:, herramientas:)
    es_sistema = codigo == 'agente_triage'
    Helic3::Agente.create!(account: account, codigo: codigo, nombre: codigo, herramientas: herramientas,
                           prompt: 'prompt', es_sistema: es_sistema, criterio_ruteo: es_sistema ? nil : 'criterio')
  end

  it 'un agente_pqrs sin la herramienta la recibe' do
    agente = crear_agente(codigo: 'agente_pqrs', herramientas: %w[buscar_conocimiento radicar_pqr])

    correr

    expect(agente.reload.herramientas).to match_array(%w[buscar_conocimiento radicar_pqr consultar_cliente_erp])
  end

  it 'un agente_pqrs que ya la tiene no queda con la clave duplicada' do
    agente = crear_agente(codigo: 'agente_pqrs', herramientas: %w[buscar_conocimiento consultar_cliente_erp])

    correr

    expect(agente.reload.herramientas).to eq(%w[buscar_conocimiento consultar_cliente_erp])
  end

  it 'correrla dos veces da el mismo resultado' do
    agente = crear_agente(codigo: 'agente_pqrs', herramientas: %w[radicar_pqr])

    correr
    correr

    expect(agente.reload.herramientas).to match_array(%w[radicar_pqr consultar_cliente_erp])
  end

  it 'otros agentes (triage, logistica) no cambian' do
    triage = crear_agente(codigo: 'agente_triage', herramientas: %w[registrar_consentimiento])
    logistica = crear_agente(codigo: 'agente_logistica', herramientas: %w[buscar_conocimiento])

    correr

    expect(triage.reload.herramientas).to eq(%w[registrar_consentimiento])
    expect(logistica.reload.herramientas).to eq(%w[buscar_conocimiento])
  end

  it 'una cuenta sin agente_pqrs no falla' do
    crear_agente(codigo: 'agente_triage', herramientas: %w[registrar_consentimiento])

    expect { correr }.not_to raise_error
  end
end
