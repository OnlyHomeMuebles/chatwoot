# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 catalogo de agentes (H3A-03)', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:base) { "/api/v1/accounts/#{account.id}/helic3/agentes/catalogo" }

  it 'expone las herramientas y las reglas duras, de solo lectura' do
    get base, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body['herramientas']).to be_an(Array)
    expect(body['herramientas'].first.keys).to include('clave', 'etiqueta', 'ayuda', 'escribe_expediente')
    expect(body['reglas_duras']).to eq(Helic3::Agents::CoreRules::GUIDE)
  end

  it 'requiere autenticacion' do
    get base, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
