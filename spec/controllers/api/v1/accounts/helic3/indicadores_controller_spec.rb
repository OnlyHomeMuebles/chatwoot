# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 Indicadores (IND-01)', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def get_garantias(query = {})
    get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias", params: query,
                                                                       headers: agent.create_new_auth_token, as: :json
  end

  it 'exige autenticacion' do
    get "/api/v1/accounts/#{account.id}/helic3/indicadores/garantias"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devuelve las siete secciones de la respuesta' do
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias

    expect(response).to have_http_status(:success)
    body = response.parsed_body
    expect(body.keys).to match_array(%w[kpis mensual trimestral por_ciudad por_motivo por_detalle por_proceso
                                        por_producto])
    expect(body['kpis']).to eq('garantias' => 1, 'solucionadas' => 0, 'en_proceso' => 1, 'productos' => 0)
  end

  it 'pasa los filtros de la query al servicio' do
    ciudad = Helic3::Catalogo::CoberturaCiudad.create!(account: account, nombre: 'Manizales', codigo: 'manizales')
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1),
                             cobertura_ciudad: ciudad)
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias(cobertura_ciudad_id: ciudad.id)

    expect(response.parsed_body['kpis']['garantias']).to eq(1)
  end

  # N1 (revision de Jhan, PR #113): un anio/mes no numerico tumbaba la consulta con un 500
  # (Postgres comparando numeric con texto) -- ahora se ignora, no se rechaza la peticion.
  it 'no revienta con un anio/mes no numerico, simplemente los ignora' do
    Helic3::Garantia.create!(account: account, ticket: ticket, abierta_at: Time.zone.local(2026, 1, 1, 12, 0))

    get_garantias(anio: 'abc', mes: 'xyz')

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['kpis']['garantias']).to eq(1)
  end

  it 'no expone las garantias de otra cuenta' do
    otra_cuenta = create(:account)
    otro_ticket = create(:ticket, account: otra_cuenta)
    Helic3::Garantia.create!(account: otra_cuenta, ticket: otro_ticket, abierta_at: Time.zone.local(2026, 1, 1))

    get_garantias

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['kpis']['garantias']).to eq(0)
  end
end
