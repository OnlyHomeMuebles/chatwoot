# frozen_string_literal: true

require 'rails_helper'

# Integration test for the hub-and-spoke flow: the real ai-agents Runner drives an actual
# handoff from the triage agent to a specialist. Only the LLM layer (RubyLLM::Chat) is
# stubbed with a scripted chat — the triage turn invokes the real handoff tool (which sets
# the real pending_handoff), and the specialist turn returns the final answer.
RSpec.describe Helic3::Agents::RunnerService do
  subject(:service) { described_class.new(model: 'gpt-4.1-mini') }

  let(:final_response) do
    instance_double(
      RubyLLM::Message,
      content: 'Las puertas Milano son de MDF enchapado.',
      tool_call?: false,
      tool_calls: {},
      input_tokens: 5,
      output_tokens: 12
    )
  end

  # Fake RubyLLM chat: turn 1 (triage) calls the FAQ handoff tool; turn 2 (specialist)
  # returns the final answer. `with_tools` captures the wrapped tools so `ask` can fire the
  # real handoff, which mutates the Runner's context via the tool's captured context wrapper.
  let(:chat) do
    captured_tools = []
    fake = instance_double(RubyLLM::Chat)
    allow(fake).to receive_messages(with_instructions: fake, with_temperature: fake, with_model: fake, messages: [])
    allow(fake).to receive(:with_tools) do |*tools, **_kwargs|
      captured_tools.replace(tools)
      fake
    end
    allow(fake).to receive(:ask) do |_input|
      captured_tools.find { |tool| tool.name == 'handoff_to_agente_faq' }.call({})
    end
    allow(fake).to receive(:complete).and_return(final_response)
    fake
  end

  before { allow(RubyLLM::Chat).to receive(:new).and_return(chat) }

  describe '#run con un handoff' do
    it 'enruta desde el triage al especialista de FAQ' do
      result = service.run('¿De qué material son las puertas Milano?')

      # Empieza en el triage (entrada por defecto) y termina en el especialista: hubo handoff.
      expect(result.context[:current_agent]).to eq('agente_faq')
    end

    it 'entrega al usuario solo la respuesta del especialista (handoff transparente)' do
      result = service.run('¿De qué material son las puertas Milano?')

      expect(result.output).to eq('Las puertas Milano son de MDF enchapado.')
      expect(result.output).not_to include('agente_')
      expect(result.output).not_to match(/transfer|handoff/i)
    end

    it 'reutiliza el mismo runner entre conversaciones' do
      allow(Agents::Runner).to receive(:with_agents).and_call_original

      service.run('Primera consulta')
      service.run('Segunda consulta')

      expect(Agents::Runner).to have_received(:with_agents).once
    end
  end
end
