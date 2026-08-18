# frozen_string_literal: true

class OnlyHome::RunnerService
  def initialize(model: nil, provider: nil, assume_model_exists: false, single: false)
    @model = model
    @provider = provider
    @assume_model_exists = assume_model_exists
    @single = single
  end

  def run(message, context: {})
    runner.run(message, context: context)
  end

  private

  def build_agents
    opts = { model: @model, provider: @provider, assume_model_exists: @assume_model_exists }
    # Modo RAG (open source local): un solo agente que recibe el conocimiento relevante inyectado,
    # en vez del multiagente con handoffs (que los modelos locales pequeños no manejan bien).
    return [OnlyHome::SoloAgent.build(**opts)] if @single

    triage       = OnlyHome::TriageAgent.build(**opts)
    faq          = OnlyHome::FaqAgent.build(**opts)
    pqrs         = OnlyHome::PqrsAgent.build(**opts)
    logistica    = OnlyHome::LogisticaAgent.build(**opts)
    cotizaciones = OnlyHome::CotizacionesAgent.build(**opts)

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
