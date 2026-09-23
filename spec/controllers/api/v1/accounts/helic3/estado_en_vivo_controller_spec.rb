# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 estado en vivo (H3A-15)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/helic3/estado-en-vivo" }

  let!(:activa) do
    create(:conversation, account: account, inbox: inbox,
                          custom_attributes: { 'helic3_agente_activo' => 'agente_pqrs' })
  end
  let!(:pausada) do
    create(:conversation, account: account, inbox: inbox,
                          custom_attributes: { 'helic3_agente_activo' => 'agente_faq', 'helic3_ia_pausada' => true })
  end
  let!(:sin_ia) { create(:conversation, account: account, inbox: inbox) }

  describe 'GET index' do
    it 'lista solo las conversaciones atendidas por IA y no pausadas (crit 1)' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.map { |c| c['conversation_id'] }
      expect(ids).to include(activa.display_id)
      expect(ids).not_to include(pausada.display_id, sin_ia.display_id)
    end

    it 'un agente (no admin) recibe 401' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST intervenir' do
    it 'pausa la IA en la conversación (crit 2)' do
      post "#{base}/#{activa.display_id}/intervenir", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(activa.reload.custom_attributes['helic3_ia_pausada']).to be(true)
    end
  end
end
