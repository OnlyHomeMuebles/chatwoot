require 'rails_helper'

RSpec.describe 'Helic3 Cola de decisiones (DEC-01)', type: :request do
  let(:account) { create(:account) }
  let(:motivo) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }
  let(:no_procede) { Helic3::Catalogo::Resultado.find_by!(account: account, codigo: 'no_procede_garantia') }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  before { Helic3::Catalogo::SeederService.new(account).sembrar! }

  def radicar(**)
    Helic3::Casos::Radicar.new(account: account, titulo: 'Caso', motivo_pqr: motivo, origen: :humano, **).call
  end

  # Simula la propuesta del agente (RES-01 la guarda en pqrs_metadata).
  def proponer(ticket, resultado)
    ticket.update!(pqrs_metadata: ticket.pqrs_metadata.merge(
      'resultado_propuesto_id' => resultado.id,
      'propuesto_at' => Time.current.iso8601,
      'propuesto_por' => 'agente'
    ))
  end

  def pedir_cola
    get "/api/v1/accounts/#{account.id}/helic3/pqr/decisiones",
        headers: agent.create_new_auth_token, as: :json
  end

  it 'un expediente con propuesta de aprobacion_humana aparece con su regla' do
    ticket = radicar
    proponer(ticket, no_procede)

    pedir_cola

    fila = response.parsed_body.first
    expect(fila['id']).to eq(ticket.id)
    expect(fila['propuesta']['codigo']).to eq('no_procede_garantia')
    expect(fila['propuesta']['aprobacion_humana']).to be(true)
  end

  it 'una PQR sin propuesta pendiente no aparece' do
    radicar # sin propuesta

    pedir_cola

    expect(response.parsed_body).to be_empty
  end

  it 'ordena por vencimiento, con las vencidas arriba' do
    lejana = radicar
    proponer(lejana, no_procede)
    lejana.update!(plazo_respuesta_vence_at: 10.days.from_now)
    vencida = radicar
    proponer(vencida, no_procede)
    vencida.update!(plazo_respuesta_vence_at: 2.days.ago)

    pedir_cola

    expect(response.parsed_body.map { |f| f['id'] }).to eq([vencida.id, lejana.id])
  end

  it 'no muestra la cola de otra cuenta' do
    otra = create(:account)
    Helic3::Catalogo::SeederService.new(otra).sembrar!
    ajeno = Helic3::Casos::Radicar.new(
      account: otra, titulo: 'Ajeno', origen: :humano,
      motivo_pqr: Helic3::Catalogo::MotivoPqr.find_by!(account: otra, codigo: 'garantia_producto')
    ).call
    proponer(ajeno, Helic3::Catalogo::Resultado.find_by!(account: otra, codigo: 'no_procede_garantia'))
    propio = radicar
    proponer(propio, no_procede)

    pedir_cola

    expect(response.parsed_body.map { |f| f['id'] }).to eq([propio.id])
  end

  it 'aprobar por la resolucion saca la fila de la cola y NO crea mensaje al cliente' do
    conv = create(:conversation, account: account)
    ticket = radicar(conversation_id: conv.id)
    proponer(ticket, no_procede)

    expect do
      post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/resolucion",
           params: { resultado_id: no_procede.id },
           headers: admin.create_new_auth_token, as: :json
    end.not_to change(conv.messages, :count)

    expect(response).to have_http_status(:success)
    expect(ticket.reload.respondida_at).to be_present

    pedir_cola
    expect(response.parsed_body).to be_empty
  end

  it 'un agente sin permiso no puede aprobar un resultado que exige admin' do
    ticket = radicar
    proponer(ticket, no_procede)

    post "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/resolucion",
         params: { resultado_id: no_procede.id },
         headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(ticket.reload.respondida_at).to be_nil
  end
end
