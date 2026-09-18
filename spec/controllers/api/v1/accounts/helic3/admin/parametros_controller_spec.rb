require 'rails_helper'

RSpec.describe 'Helic3 administracion de parametros (ADM-01)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  let!(:umbral) do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_verde_pqr', valor: '8', unidad: 'dias_habiles')
  end

  let(:base) { "/api/v1/accounts/#{account.id}/helic3/admin/parametros" }

  it 'un agente puede leer los parametros' do
    get base, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.first['clave']).to eq('umbral_verde_pqr')
  end

  it 'un administrador edita el valor de un umbral' do
    patch "#{base}/#{umbral.id}",
          params: { parametro: { valor: '15' } },
          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:success)
    expect(umbral.reload.valor).to eq('15')
  end

  it 'un agente que intenta editar recibe 401' do
    patch "#{base}/#{umbral.id}",
          params: { parametro: { valor: '15' } },
          headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(umbral.reload.valor).to eq('8')
  end

  it 'la clave es inmutable: no se puede cambiar' do
    patch "#{base}/#{umbral.id}",
          params: { parametro: { clave: 'otra_clave', valor: '10' } },
          headers: admin.create_new_auth_token, as: :json

    expect(umbral.reload.clave).to eq('umbral_verde_pqr')
  end

  it 'rechaza un valor vacio (el dominio lo lee como obligatorio)' do
    patch "#{base}/#{umbral.id}",
          params: { parametro: { valor: '' } },
          headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(umbral.reload.valor).to eq('8')
  end
end
