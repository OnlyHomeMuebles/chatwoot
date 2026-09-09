# frozen_string_literal: true

require 'rails_helper'

# CTR-04: prueba de integracion que cruza los dos frentes (agente y panel/API).
# El error de contrato vive en el ENCUENTRO de los frentes: cada lado tenia sus
# specs en verde y ninguno podia verlo. Este spec ejercita la ruta completa, sin
# mockear la tool ni el controlador, y exige que el display_id de la conversacion
# sea distinto del id de base de datos (si coinciden, la prueba pasaria sin probar
# nada — que es exactamente lo que ocurrio hasta ahora).
RSpec.describe 'Helic3 contrato de conversation_id entre el agente y la API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }

  # Fuerza display_id != id: creamos conversaciones en OTRA cuenta para adelantar
  # la secuencia global de ids, y luego la conversacion de prueba nace con
  # display_id 1 (por cuenta) pero id de BD mucho mayor.
  let(:conversation) do
    otra = create(:account)
    3.times { create(:conversation, account: otra) }
    create(:conversation, account: account, inbox: inbox)
  end

  let(:chatwoot) { instance_double(Helic3::ChatwootClient, create_message: nil, toggle_typing: nil) }

  let(:garantia) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }

  before do
    garantia
    Helic3::Catalogo::EtapaPqr.create!(account: account, nombre: 'Nueva', codigo: 'nueva')
    Helic3::Catalogo::Tipo.create!(account: account, nombre: 'Reclamo', codigo: 'reclamo', plazo_dias_habiles: 15)
    Helic3::Catalogo::MotivoPqr.create!(account: account, nombre: 'Garantía de producto',
                                        codigo: 'garantia_producto', categoria: garantia)
    # plazo de respaldo para cuando se radica sin tipo (la creacion por API del panel)
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_respuesta_pqr', valor: '15', unidad: 'dias_habiles')
    # umbrales del semaforo: el detalle del expediente los necesita al renderizar
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_verde_pqr', valor: '8', unidad: 'dias_habiles')
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'umbral_amarillo_pqr', valor: '3', unidad: 'dias_habiles')
  end

  # el nino con dos numeros: sin esto, cualquier coincidencia de secuencia haria
  # pasar el spec sin probar la traduccion
  it 'la conversacion de prueba tiene display_id distinto del id de base de datos' do
    expect(conversation.display_id).not_to eq(conversation.id)
  end

  describe 'radicar con la tool del agente y leer por el filtro de la API' do
    it 'el expediente que radica el agente aparece en el indice filtrado por el display_id' do
      tool_context = Agents::ToolContext.new(run_context: Agents::RunContext.new(
        { account_id: account.id,
          state: { conversation_id: conversation.display_id, chatwoot_client: chatwoot } }
      ))
      Helic3::Agents::Tools::RadicarPqrTool.new.perform(
        tool_context, tipo_codigo: 'reclamo', motivo_codigo: 'garantia_producto',
                      resumen: 'Sofá rayado', descripcion: 'El cliente reporta rayones'
      )
      radicado = Helic3::Ticket.last
      expect(radicado.conversation_id).to eq(conversation.id)

      get "/api/v1/accounts/#{account.id}/helic3/tickets",
          params: { conversation_id: conversation.display_id },
          headers: agent.create_new_auth_token, as: :json

      ids = response.parsed_body.map { |t| t['id'] }
      expect(ids).to include(radicado.id)
    end
  end

  describe 'crear por la API y leer por el filtro de la API' do
    it 'el expediente creado por el panel queda vinculado al id de BD y aparece filtrado por el display_id' do
      motivo = Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto')

      post "/api/v1/accounts/#{account.id}/helic3/tickets",
           params: { ticket: { title: 'Caso panel', motivo_pqr_id: motivo.id, conversation_id: conversation.display_id } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      creado = Helic3::Ticket.find(response.parsed_body['id'])
      expect(creado.conversation_id).to eq(conversation.id)

      get "/api/v1/accounts/#{account.id}/helic3/tickets",
          params: { conversation_id: conversation.display_id },
          headers: agent.create_new_auth_token, as: :json

      ids = response.parsed_body.map { |t| t['id'] }
      expect(ids).to include(creado.id)
    end
  end
end
