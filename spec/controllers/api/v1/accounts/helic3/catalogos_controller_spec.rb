# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 Catalogos API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { Helic3::Catalogo::SeederService.new(account).sembrar! }

  describe 'GET /api/v1/accounts/{account.id}/helic3/catalogos' do
    context 'when the user is unauthenticated' do
      it 'responde 401' do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the user is authenticated' do
      it 'devuelve los cuatro catalogos con sus campos' do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body.keys).to include('tipos', 'motivos_pqr', 'etapas_pqr', 'resultados')
        expect(body['tipos'].first.keys).to match_array(%w[id codigo nombre plazo_dias_habiles])
        expect(body['etapas_pqr'].first.keys).to match_array(%w[id codigo nombre detiene_reloj visible_cliente])
        expect(body['resultados'].first.keys).to match_array(%w[id codigo nombre cierra_pqr abre_garantia aprobacion_humana])
      end

      it 'devuelve cada catalogo en el orden de posicion' do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos",
            headers: agent.create_new_auth_token, as: :json

        esperado = Helic3::Catalogo::Tipo.where(account: account).activos.pluck(:codigo)
        expect(response.parsed_body['tipos'].map { |tipo| tipo['codigo'] }).to eq(esperado)
      end

      it 'trae la categoria embebida en cada motivo, no solo el categoria_id' do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos",
            headers: agent.create_new_auth_token, as: :json

        motivo = response.parsed_body['motivos_pqr'].find { |mot| mot['codigo'] == 'garantia_producto' }
        expect(motivo).not_to have_key('categoria_id')
        expect(motivo['categoria']).to include('codigo' => 'garantia')
        expect(motivo['categoria'].keys).to match_array(%w[id codigo nombre])
      end

      it 'no incluye una fila desactivada' do
        Helic3::Catalogo::Tipo.find_by!(account: account, codigo: 'peticion').update!(activo: false)

        get "/api/v1/accounts/#{account.id}/helic3/catalogos",
            headers: agent.create_new_auth_token, as: :json

        expect(response.parsed_body['tipos'].map { |tipo| tipo['codigo'] }).not_to include('peticion')
      end

      it 'no expone los catalogos de otra cuenta' do
        otra_cuenta = create(:account)
        otro_agente = create(:user, account: otra_cuenta, role: :agent)

        get "/api/v1/accounts/#{otra_cuenta.id}/helic3/catalogos",
            headers: otro_agente.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['tipos']).to eq([])
      end
    end
  end
end
