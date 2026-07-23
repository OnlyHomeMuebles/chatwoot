# frozen_string_literal: true

class OnlyHome::RunnerService
  def initialize(model: nil)
    @model = model
  end

  def run(message, context: {})
    runner.run(message, context: context)
  end

  private

  def build_agents
    triage       = OnlyHome::TriageAgent.build(model: @model)
    faq          = OnlyHome::FaqAgent.build(model: @model)
    pqrs         = OnlyHome::PqrsAgent.build(model: @model)
    logistica    = OnlyHome::LogisticaAgent.build(model: @model)
    cotizaciones = OnlyHome::CotizacionesAgent.build(model: @model)

    triage.register_handoffs(faq, pqrs, logistica, cotizaciones)
    faq.register_handoffs(triage)
    pqrs.register_handoffs(triage)
    logistica.register_handoffs(triage)
    cotizaciones.register_handoffs(triage)

    [triage, faq, pqrs, logistica, cotizaciones]
  end

  def runner
    @runner ||= Agents::Runner.with_agents(*build_agents)
  end
end
