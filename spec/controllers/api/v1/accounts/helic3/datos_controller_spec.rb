require 'rails_helper'

RSpec.describe 'Datos API', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'PATCH /api/v1/accounts/{account.id}/helic3/tickets/{ticket_id}/datos' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the operator corrects a field' do
      it 'lo guarda con fuente humano y lo devuelve en el JSON' do
        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos",
              params: { datos: { direccion: 'Cra 5 #10-20' } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['datos']['direccion']['valor']).to eq('Cra 5 #10-20')
        expect(response.parsed_body['datos']['direccion']['fuente']).to eq('humano')
        expect(ticket.reload.datos.fuentes['direccion']).to eq('humano')
      end
    end

    context 'when the detalle_tipificado belongs to another account' do
      it 'responde 404 y no crea la ficha' do
        otra = create(:account)
        ajeno = Helic3::Catalogo::DetalleTipificado.create!(account: otra, nombre: 'x', codigo: 'x')

        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos",
              params: { datos: { detalle_tipificado_id: ajeno.id } },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:not_found)
        expect(ticket.reload.datos).to be_nil
      end
    end

    context 'when it is an agent who is not a participant' do
      it 'no puede editar la ficha (update? = participante)' do
        patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/datos",
              params: { datos: { direccion: 'X' } },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(ticket.reload.datos).to be_nil
      end
    end
  end
end
