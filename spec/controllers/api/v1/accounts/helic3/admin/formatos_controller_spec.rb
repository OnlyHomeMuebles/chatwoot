# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 admin formatos (FMT-02)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:formato) do
    Helic3::Catalogo::Formato.create!(account: account, nombre: 'Visita', codigo: 'visita_tecnica', posicion: 0)
  end

  it 'un agente puede listar los formatos con sus versiones' do
    formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[CLIENTE])

    get "/api/v1/accounts/#{account.id}/helic3/admin/formatos", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.first['codigo']).to eq('visita_tecnica')
    expect(response.parsed_body.first['versiones'].first['estado']).to eq('activa')
  end

  it 'devuelve el diccionario de marcadores' do
    get "/api/v1/accounts/#{account.id}/helic3/admin/formatos/marcadores",
        headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to have_key('CLIENTE')
  end
end
