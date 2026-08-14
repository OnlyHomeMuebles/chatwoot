require 'rails_helper'

RSpec.describe 'Tickets API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/{account.id}/tickets' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/tickets"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let!(:ticket) { create(:ticket, account: account) }

      it 'returns all the tickets of the account' do
        get "/api/v1/accounts/#{account.id}/tickets",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.first['id']).to eq(ticket.id)
        expect(response.parsed_body.first['ticket_number']).to eq("##{ticket.display_id}")
      end

      it 'filters by status' do
        create(:ticket, account: account, status: :resolved)

        get "/api/v1/accounts/#{account.id}/tickets",
            params: { status: 'resolved' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.length).to eq(1)
        expect(response.parsed_body.first['status']).to eq('resolved')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/tickets' do
    context 'when it is an authenticated user' do
      it 'creates a ticket with a sequential ticket number and sets the creator' do
        post "/api/v1/accounts/#{account.id}/tickets",
             params: { ticket: { title: 'Printer on fire', description: 'Third floor' } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['display_id']).to eq(1)
        expect(response.parsed_body['creator']['id']).to eq(agent.id)
      end

      it 'rejects a ticket without title' do
        post "/api/v1/accounts/#{account.id}/tickets",
             params: { ticket: { description: 'no title' } },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/tickets/{id}/assign' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the ticket creator' do
      it 'assigns an agent of the account' do
        post "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}/assign",
             params: { assignee_id: agent.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.assignee_id).to eq(agent.id)
        expect(response.parsed_body['assignee']['id']).to eq(agent.id)
      end

      it 'unassigns when assignee_id is empty' do
        ticket.update!(assignee: agent)

        post "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}/assign",
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

        post "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}/assign",
             params: { assignee_id: other_agent.id },
             headers: other_agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.assignee_id).to be_nil
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account, creator: agent) }

    context 'when it is the assigned agent' do
      it 'updates the status' do
        assignee = create(:user, account: account, role: :agent)
        ticket.update!(assignee: assignee)

        patch "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}",
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

        patch "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: other_agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.status).to eq('open')
      end
    end

    context 'when it is an administrator' do
      it 'updates any ticket' do
        patch "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}",
              params: { ticket: { status: 'closed' } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(ticket.reload.status).to eq('closed')
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/tickets/{id}' do
    let!(:ticket) { create(:ticket, account: account) }

    context 'when it is an agent and the ticket is not theirs' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent and the ticket was created by them' do
      it 'deletes the ticket' do
        own_ticket = create(:ticket, account: account, creator: agent)

        delete "/api/v1/accounts/#{account.id}/tickets/#{own_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Ticket.exists?(own_ticket.id)).to be(false)
      end
    end

    context 'when it is an agent and the ticket is only assigned to them' do
      it 'returns unauthorized' do
        assigned_ticket = create(:ticket, account: account, assignee: agent)

        delete "/api/v1/accounts/#{account.id}/tickets/#{assigned_ticket.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(Ticket.exists?(assigned_ticket.id)).to be(true)
      end
    end

    context 'when it is an administrator' do
      it 'deletes any ticket' do
        delete "/api/v1/accounts/#{account.id}/tickets/#{ticket.id}",
               headers: administrator.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:success)
        expect(Ticket.exists?(ticket.id)).to be(false)
      end
    end
  end
end
