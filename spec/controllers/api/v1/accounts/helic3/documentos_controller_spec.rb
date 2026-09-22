require 'rails_helper'

RSpec.describe 'Documentos API (EVI-02)', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:ticket) { create(:ticket, account: account, conversation: conversation) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def get_documentos(ticket_id: ticket.id, headers: agent.create_new_auth_token)
    get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket_id}/documentos", headers: headers, as: :json
  end

  describe 'GET /api/v1/accounts/{account.id}/helic3/tickets/{ticket_id}/documentos' do
    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/documentos"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'sincroniza perezosamente y devuelve la lista ordenada por fecha' do
      create(:message, :with_attachment, account: account, conversation: conversation,
                                         message_type: 'incoming', created_at: 2.days.ago)
      create(:message, :with_attachment, account: account, conversation: conversation,
                                         message_type: 'incoming', created_at: 1.day.ago)

      get_documentos

      expect(response).to have_http_status(:success)
      payload = response.parsed_body
      expect(payload.size).to eq(2)
      expect(payload.first['ocurrido_at']).to be < payload.second['ocurrido_at']
      expect(payload.first).to include('id', 'clase', 'origen', 'titulo', 'tipo_archivo', 'url')
    end

    it 'llamar dos veces seguidas no duplica documentos (idempotente)' do
      create(:message, :with_attachment, account: account, conversation: conversation, message_type: 'incoming')

      get_documentos
      get_documentos

      expect(response.parsed_body.size).to eq(1)
    end

    it 'responde 404 si el expediente es de otra cuenta' do
      otra_cuenta = create(:account)
      ajeno = create(:ticket, account: otra_cuenta)

      get_documentos(ticket_id: ajeno.id)

      expect(response).to have_http_status(:not_found)
    end
  end
end
