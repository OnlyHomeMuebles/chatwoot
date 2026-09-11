require 'rails_helper'

RSpec.describe 'Garantia items API', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                              codigo: 'visita_tecnica', posicion: 0)
  end
  let(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 2, es_terminal: true)
  end
  let(:item) { garantia.items.create!(account: account, producto_nombre: 'Sofá', proceso: visita) }

  # el JSON de respuesta trae la garantia, cuyo presupuesto lee los umbrales del
  # semaforo del catalogo (ambito garantia): sin ellos el serializador revienta.
  before do
    { plazo_total_garantia: 30, umbral_verde_garantia: 15, umbral_amarillo_garantia: 5 }.each do |clave, valor|
      Helic3::Catalogo::Parametro.create!(account: account, clave: clave.to_s,
                                          valor: valor.to_s, unidad: 'dias_habiles')
    end
  end

  def path(garantia_id: garantia.id, item_id: item.id)
    "/api/v1/accounts/#{account.id}/helic3/garantias/#{garantia_id}/items/#{item_id}"
  end

  describe 'PATCH /api/v1/accounts/{account.id}/helic3/garantias/{garantia_id}/items/{id}' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch path

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when an administrator advances the product to a terminal process' do
      it 'sella el producto, cierra el radicado y lo devuelve en el JSON' do
        patch path,
              params: { proceso_id: entrega.id },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(item.reload.proceso).to eq(entrega)
        expect(garantia.reload.cerrada_at).to be_present
        expect(response.parsed_body['garantia']['cerrada_at']).to be_present
      end
    end

    context 'when the proceso belongs to another account' do
      it 'responde 404 y no cambia el producto' do
        otra = create(:account)
        ajeno = Helic3::Catalogo::ProcesoGarantia.create!(account: otra, nombre: 'x', codigo: 'x',
                                                          posicion: 0, es_terminal: true)

        patch path,
              params: { proceso_id: ajeno.id },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:not_found)
        expect(item.reload.proceso).to eq(visita)
      end
    end

    context 'when an agent is not a participant of the expediente' do
      it 'no puede avanzar el proceso (update? = participante)' do
        patch path,
              params: { proceso_id: entrega.id },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(item.reload.proceso).to eq(visita)
      end
    end
  end
end
