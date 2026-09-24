# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 estado en vivo (H3A-15)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/helic3/estado-en-vivo" }

  # atendida por IA AHORA: en territorio del bot (pending) y con agente activo.
  let!(:activa) do
    create(:conversation, account: account, inbox: inbox, status: :pending,
                          custom_attributes: { 'helic3_agente_activo' => 'agente_pqrs' })
  end
  # ya derivada a un humano: pasó a 'open'. NO debe aparecer aunque conserve el agente activo (B2).
  let!(:intervenida) do
    create(:conversation, account: account, inbox: inbox, status: :open,
                          custom_attributes: { 'helic3_agente_activo' => 'agente_faq' })
  end
  # resuelta: NO debe aparecer (B2 — no es dato vivo).
  let!(:resuelta) do
    create(:conversation, account: account, inbox: inbox, status: :resolved,
                          custom_attributes: { 'helic3_agente_activo' => 'agente_faq' })
  end
  let!(:sin_ia) { create(:conversation, account: account, inbox: inbox, status: :pending) }

  describe 'GET index' do
    it 'lista solo las conversaciones que la IA atiende ahora: pending y con agente activo (crit 1/B2)' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |c| c['conversation_id'] }
      expect(ids).to include(activa.display_id)
      expect(ids).not_to include(intervenida.display_id, resuelta.display_id, sin_ia.display_id)
    end

    it 'un agente (no admin) recibe 401' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST intervenir' do
    # B3: intervenir saca la conversación del territorio del bot y la pone en manos del asesor.
    it 'pasa la conversación a open, la asigna al asesor y marca la pausa (crit 2/B3)' do
      post "#{base}/#{activa.display_id}/intervenir", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      activa.reload
      expect(activa.status).to eq('open')
      expect(activa.assignee).to eq(admin)
      expect(activa.custom_attributes['helic3_ia_pausada']).to be(true)
    end

    it 'la conversación intervenida deja de aparecer en la lista en vivo' do
      post "#{base}/#{activa.display_id}/intervenir", headers: admin.create_new_auth_token, as: :json
      get base, headers: admin.create_new_auth_token, as: :json

      ids = response.parsed_body.map { |c| c['conversation_id'] }
      expect(ids).not_to include(activa.display_id)
    end
  end
end
