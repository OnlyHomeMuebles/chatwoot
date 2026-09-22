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

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets/{ticket_id}/documentos (EVI-03, carga manual)' do
    let(:archivo) do
      fixture_file_upload(Rails.root.join('spec/assets/avatar.png'), 'image/png')
    end

    def post_documento(ticket_id: ticket.id, headers: agent.create_new_auth_token, params: { archivo: archivo })
      post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket_id}/documentos", params: params, headers: headers
    end

    context 'when the uploader is a participant of the case (assignee)' do
      before { ticket.update!(assignee: agent) }

      it 'crea el documento con clase evidencia, origen operador y el usuario como remitente' do
        post_documento

        expect(response).to have_http_status(:success)
        documento = ticket.documentos.last
        expect(documento).to have_attributes(clase: 'evidencia', origen: 'operador', remitente_user: agent,
                                             remitente_nombre: agent.name, titulo: 'avatar.png')
        expect(documento.archivo).to be_attached
      end
    end

    context 'when the agent is not a participant of the case' do
      it 'no puede subir (update? = participante)' do
        post_documento

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.documentos).to be_empty
      end
    end

    context 'when the assignee sends a non-file value for archivo' do
      before { ticket.update!(assignee: agent) }

      it 'responde 422 en vez de reventar con 500' do
        post_documento(params: { archivo: 'esto no es un archivo' })

        expect(response).to have_http_status(:unprocessable_entity)
        expect(ticket.documentos).to be_empty
      end
    end
  end
end
