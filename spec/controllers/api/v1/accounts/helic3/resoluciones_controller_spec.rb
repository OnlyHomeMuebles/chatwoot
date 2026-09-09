require 'rails_helper'

RSpec.describe 'Resoluciones API', type: :request do
  let(:account) { create(:account) }
  let(:resultado) do
    Helic3::Catalogo::Resultado.create!(account: account, nombre: 'Resuelta con información',
                                        codigo: 'resuelta_info', cierra_pqr: true)
  end
  let(:ticket) { create(:ticket, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  # la etapa que detiene el reloj debe existir en la BD: responder! la busca con
  # find_by!. No se referencia por nombre en los tests, va en un before.
  before do
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Respondida', codigo: 'respondida',
                                       detiene_reloj: true)
  end

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets/{ticket_id}/resolucion' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/resolucion"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      it 'resuelve el expediente: detiene el reloj y devuelve el detalle' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/resolucion",
             params: { resultado_id: resultado.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['reloj_detenido']).to be(true)
        expect(ticket.reload.respondida_at).to be_present
        expect(ticket.resultado).to eq(resultado)
      end

      it 'un resultado de otra cuenta responde 404 y no modifica el expediente' do
        otra = create(:account)
        ajeno = Helic3::Catalogo::Resultado.create!(account: otra, nombre: 'x', codigo: 'x',
                                                    cierra_pqr: true)

        post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/resolucion",
             params: { resultado_id: ajeno.id },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
        expect(ticket.reload.respondida_at).to be_nil
      end
    end
  end

  describe 'la puerta falsa quedo cerrada (RES-01)' do
    it 'un PATCH con resultado_id NO resuelve el expediente' do
      patch "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}",
            params: { ticket: { resultado_id: resultado.id } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(ticket.reload.resultado_id).to be_nil
      expect(ticket.respondida_at).to be_nil
    end
  end
end
