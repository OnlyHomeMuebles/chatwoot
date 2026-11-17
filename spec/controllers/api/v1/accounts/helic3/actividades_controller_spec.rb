# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 Actividades API', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  # un agente que no es creador ni asignado: registrar seguimiento solo pide ver el caso
  let(:agent) { create(:user, account: account, role: :agent, name: 'Karen Vanegas') }
  let(:url) { "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/actividades" }

  describe 'POST /api/v1/accounts/{account.id}/helic3/tickets/{ticket_id}/actividades' do
    it 'responde 401 sin autenticacion' do
      post url, params: { actividad: { titulo: 'Llamada', detalle: 'x' } }, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'crea la actividad con el autor y la fecha del servidor y devuelve el expediente' do
      freeze_time do
        post url,
             params: { actividad: { titulo: 'Llamada al cliente', detalle: 'Agenda visita el jueves',
                                    autor_nombre: 'Otro', autor_id: 999, created_at: 1.year.ago } },
             headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        actividad = ticket.actividades.sole
        expect(actividad.autor).to eq(agent)
        expect(actividad.autor_nombre).to eq('Karen Vanegas')
        expect(actividad.created_at).to eq(Time.current)
        expect(response.parsed_body['id']).to eq(ticket.id)
        expect(response.parsed_body['actividades'].first).to include(
          'id' => actividad.id, 'titulo' => 'Llamada al cliente',
          'detalle' => 'Agenda visita el jueves', 'autor_nombre' => 'Karen Vanegas'
        )
      end
    end

    it 'responde 422 sin titulo o sin detalle y no crea nada' do
      post url, params: { actividad: { titulo: '', detalle: 'x' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      post url, params: { actividad: { titulo: 'Llamada' } }, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)

      expect(ticket.actividades).to be_empty
    end

    it 'responde 422 sin el bloque actividad' do
      post url, params: {}, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'responde 404 con un expediente de otra cuenta y no crea nada' do
      otra = create(:account)
      ajeno = create(:ticket, account: otra)

      post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ajeno.id}/actividades",
           params: { actividad: { titulo: 'Llamada', detalle: 'x' } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(Helic3::Actividad.count).to eq(0)
    end
  end

  describe 'GET del expediente' do
    it 'trae las actividades de la mas nueva a la mas antigua, junto a los eventos' do
      vieja = ticket.actividades.create!(autor: agent, titulo: 'Llamada', detalle: 'x', created_at: 1.day.ago)
      nueva = ticket.actividades.create!(autor: agent, titulo: 'Llamada', detalle: 'y')

      get "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}", headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body).to have_key('eventos')
      expect(response.parsed_body['actividades'].pluck('id')).to eq([nueva.id, vieja.id])
      expect(response.parsed_body['actividades'].first.keys)
        .to match_array(%w[id titulo detalle autor_nombre created_at])
    end
  end
end
