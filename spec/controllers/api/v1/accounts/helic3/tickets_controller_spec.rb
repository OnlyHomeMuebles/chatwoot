require 'rails_helper'

RSpec.describe 'Tickets API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/helic3/tickets' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/helic3/tickets"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:ticket) { create(:ticket, account: account) }

      it 'returns all the tickets of the account' do
        get "/api/v1/accounts/#{account.id}/helic3/tickets",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['id']).to eq(ticket.id)
        expect(response.parsed_body.first['ticket_number']).to eq("##{ticket.display_id}")
      end

      it 'filters by status' do
        create(:ticket, account: account, status: :resolved)

        get "/api/v1/accounts/#{account.id}/helic3/tickets",
            params: { status: 'resolved' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first['status']).to eq('resolved')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets' do
    # create nace por Helic3::Casos::Radicar (API-02), que necesita la etapa
    # inicial y el plazo sembrados en la cuenta.
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    context 'when it is an authenticated user' do
      it 'creates a ticket with a sequential ticket number and sets the creator' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Printer on fire', description: 'Third floor' } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['display_id']).to eq(1)
        expect(response.parsed_body['creator']['id']).to eq(agent.id)
      end

      it 'rejects a ticket without title' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { description: 'no title' } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST create con clasificacion y reloj (API-02)' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:tipo) { Helic3::Catalogo::Tipo.find_by!(account: account, codigo: 'peticion') }
    let(:motivo_garantia) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
    let(:motivo_info) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'informacion_general') }

    def radicar(atributos)
      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso' }.merge(atributos) },
           headers: agent.create_new_auth_token, as: :json
    end

    it 'deriva la categoria del motivo y devuelve numero de radicado y plazo' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['categoria']['codigo']).to eq('garantia')
      expect(body['tipo']['codigo']).to eq('peticion')
      expect(body['motivo_pqr']['codigo']).to eq('garantia_producto')
      expect(body['numero_radicado']).to be_present
      expect(body['plazo_respuesta_vence_at']).to be_present
    end

    it 'incluye semaforo y dias habiles restantes coherentes con el plazo' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      body = response.parsed_body
      expect(body['dias_habiles_restantes']).to be_a(Integer).and(be_positive)
      expect(body['semaforo']).to be_in(%w[verde amarillo rojo])
    end

    it 'marca el origen humano cuando lo radica una persona' do
      radicar(tipo_id: tipo.id, motivo_pqr_id: motivo_garantia.id)

      expect(response.parsed_body['origen']).to eq('humano')
    end

    it 'un expediente de categoria Informacion no lleva numero ni semaforo' do
      radicar(motivo_pqr_id: motivo_info.id)

      body = response.parsed_body
      expect(body['categoria']['codigo']).to eq('informacion')
      expect(body['numero_radicado']).to be_nil
      expect(body['semaforo']).to be_nil
    end

    it 'rechaza un id de catalogo de otra cuenta' do
      otra = create(:account)
      Helic3::Catalogo::SeederService.new(otra).sembrar!
      motivo_otra = Helic3::Catalogo::MotivoPqr.find_by!(account: otra, codigo: 'garantia_producto')

      radicar(motivo_pqr_id: motivo_otra.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET show de un expediente sin clasificar (API-02)' do
    let!(:ticket) { create(:ticket, account: account) }

    it 'devuelve los cinco objetos de clasificacion en nulo sin romper la vista' do
      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      %w[categoria tipo motivo_pqr resultado etapa].each do |llave|
        expect(body[llave]).to be_nil
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets/{id}/assign' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the ticket creator' do
      it 'assigns an agent of the account' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: agent.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.assignee_id).to eq(agent.id)
        expect(response.parsed_body['assignee']['id']).to eq(agent.id)
      end

      it 'unassigns when assignee_id is empty' do
        ticket.update!(assignee: agent)

        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: nil },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.assignee_id).to be_nil
      end
    end

    context 'when it is an agent unrelated to the ticket' do
      it 'returns unauthorized' do
        other_agent = create(:user, account: account, role: :agent)

        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/assign",
             params: { assignee_id: other_agent.id },
             headers: other_agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.assignee_id).to be_nil
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/helic3/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the assigned agent' do
      it 'updates the status' do
        assignee = create(:user, account: account, role: :agent)
        ticket.update!(assignee: assignee)

        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'resolved' } },
              headers: assignee.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.status).to eq('resolved')
      end
    end

    context 'when it is an agent unrelated to the ticket' do
      it 'returns unauthorized' do
        other_agent = create(:user, account: account, role: :agent)

        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: other_agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.status).to eq('open')
      end
    end

    context 'when it is an administrator' do
      it 'updates any ticket' do
        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.status).to eq('closed')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/helic3/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account) }

    context 'when it is an agent and the ticket is not theirs' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent and the ticket was created by them' do
      it 'deletes the ticket' do
        own_ticket = create(:ticket, account: account, creator: agent)

        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{own_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Helic3::Ticket.exists?(own_ticket.id)).to be(false)
      end
    end

    context 'when it is an agent and the ticket is only assigned to them' do
      it 'returns unauthorized' do
        assigned_ticket = create(:ticket, account: account, assignee: agent)

        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{assigned_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Helic3::Ticket.exists?(assigned_ticket.id)).to be(true)
      end
    end

    context 'when it is an administrator' do
      it 'deletes any ticket' do
        delete "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Helic3::Ticket.exists?(ticket.id)).to be(false)
      end
    end
  end
end
