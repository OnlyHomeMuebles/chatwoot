require 'rails_helper'

RSpec.describe 'Helic3 Bandeja de PQR (BAN-01)', type: :request do
  let(:account) { create(:account) }
  let(:motivo_garantia) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
  let(:motivo_logistica) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'error_despacho_entrega') }
  let(:motivo_info) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'informacion_general') }
  let(:categoria_garantia) { Helic3::Catalogo::Categoria.find_by!(account: account, codigo: 'garantia') }
  let(:agent) { create(:user, account: account, role: :agent) }

  before { Helic3::Catalogo::SeederService.new(account).sembrar! }

  def radicar(**)
    Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', origen: :humano, **).call
  end

  def get_pqr(query = {})
    get "/api/v1/accounts/#{account.id}/helic3/pqr", params: query,
                                                     headers: agent.create_new_auth_token, as: :json
  end

  it 'exige autenticacion' do
    get "/api/v1/accounts/#{account.id}/helic3/pqr"

    expect(response).to have_http_status(:unauthorized)
  end

  it 'devuelve los expedientes de la cuenta con su total' do
    radicar(motivo_pqr: motivo_garantia)
    radicar(motivo_pqr: motivo_logistica)

    get_pqr

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['meta']['count']).to eq(2)
    expect(response.parsed_body['payload'].size).to eq(2)
  end

  it 'filtra por categoria' do
    radicar(motivo_pqr: motivo_garantia)
    radicar(motivo_pqr: motivo_logistica)

    get_pqr(categoria_id: categoria_garantia.id)

    payload = response.parsed_body['payload']
    expect(payload.size).to eq(1)
    expect(payload.first['categoria']['codigo']).to eq('garantia')
  end

  it 'combina dos filtros: categoria y responsable' do
    asignado = radicar(motivo_pqr: motivo_garantia)
    asignado.update!(assignee: agent)
    radicar(motivo_pqr: motivo_garantia) # misma categoria pero sin asignar

    get_pqr(categoria_id: categoria_garantia.id, assignee_id: agent.id)

    expect(response.parsed_body['payload'].size).to eq(1)
    expect(response.parsed_body['payload'].first['id']).to eq(asignado.id)
  end

  it 'vencidas=true solo trae las de plazo pasado y sin responder' do
    vencida = radicar(motivo_pqr: motivo_garantia)
    vencida.update!(plazo_respuesta_vence_at: 3.days.ago) # nace sin responder
    radicar(motivo_pqr: motivo_garantia) # al dia

    get_pqr(vencidas: true)

    payload = response.parsed_body['payload']
    expect(payload.size).to eq(1)
    expect(payload.first['id']).to eq(vencida.id)
  end

  it 'q busca por numero de radicado' do
    objetivo = radicar(motivo_pqr: motivo_garantia)
    radicar(motivo_pqr: motivo_garantia)

    get_pqr(q: objetivo.display_id.to_s)

    expect(response.parsed_body['payload'].map { |f| f['id'] }).to include(objetivo.id)
  end

  it 'pagina: con 30 sembrados la primera pagina trae 25 y el total es 30' do
    30.times { radicar(motivo_pqr: motivo_garantia) }

    get_pqr

    expect(response.parsed_body['meta']['count']).to eq(30)
    expect(response.parsed_body['payload'].size).to eq(25)
  end

  it 'un expediente de categoria Informacion muestra numero_radicado nulo (Sin radicado)' do
    radicar(motivo_pqr: motivo_info)

    get_pqr

    fila = response.parsed_body['payload'].first
    expect(fila['categoria']['codigo']).to eq('informacion')
    expect(fila['numero_radicado']).to be_nil
  end

  it 'no muestra expedientes de otra cuenta' do
    otra = create(:account)
    Helic3::Catalogo::SeederService.new(otra).sembrar!
    Helic3::Casos::Radicar.new(
      account: otra, titulo: 'Ajeno', origen: :humano,
      motivo_pqr: Helic3::Catalogo::MotivoPqr.find_by!(account: otra, codigo: 'garantia_producto')
    ).call
    radicar(motivo_pqr: motivo_garantia)

    get_pqr

    expect(response.parsed_body['meta']['count']).to eq(1)
  end
end
