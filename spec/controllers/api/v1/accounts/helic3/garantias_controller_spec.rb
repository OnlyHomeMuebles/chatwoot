require 'rails_helper'

# GAR-08: anexar/corregir la observacion de una garantia YA cerrada.
RSpec.describe 'Garantias API', type: :request do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  let(:entrega) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Entrega de producto',
                                              codigo: 'entrega_producto', posicion: 2, es_terminal: true)
  end

  # el JSON de respuesta (tickets/show) trae la garantia, cuyo presupuesto lee los
  # umbrales del semaforo del catalogo: sin ellos el serializador revienta.
  before do
    { plazo_total_garantia: 30, umbral_verde_garantia: 15, umbral_amarillo_garantia: 5 }.each do |clave, valor|
      Helic3::Catalogo::Parametro.create!(account: account, clave: clave.to_s,
                                          valor: valor.to_s, unidad: 'dias_habiles')
    end
  end

  # una garantia cerrada SIN observacion (como las anteriores al despliegue).
  def cerrar_garantia!
    garantia.items.create!(account: account, producto_nombre: 'Sofá', proceso: entrega)
    garantia.cerrar!
    garantia
  end

  def path(garantia_id: garantia.id)
    "/api/v1/accounts/#{account.id}/helic3/garantias/#{garantia_id}/observacion"
  end

  describe 'PATCH /api/v1/accounts/{account.id}/helic3/garantias/{id}/observacion' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch path

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the warranty is closed without observacion (closed before the deploy)' do
      it 'anexa la observacion con su autor y registra el evento (CA#5)' do
        cerrar_garantia!

        patch path,
              params: { observacion: 'Se cerró antes; se adjunta ahora.' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:success)
        expect(garantia.reload.observacion_cierre).to eq('Se cerró antes; se adjunta ahora.')
        expect(garantia.observacion_cierre_por).to eq(administrator)
        expect(garantia.ticket.eventos.find_by(tipo: 'garantia_finalizada')).to be_present
      end
    end

    context 'when the observacion is blank' do
      it 'responde 422 y no cambia la garantia' do
        cerrar_garantia!

        patch path,
              params: { observacion: '   ' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(garantia.reload.observacion_cierre).to be_nil
      end
    end

    context 'when the warranty is not closed yet' do
      it 'responde 422 (no hay cierre que observar)' do
        patch path,
              params: { observacion: 'Texto cualquiera.' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(garantia.reload.observacion_cierre).to be_nil
      end
    end

    context 'when the warranty belongs to another account' do
      it 'responde 404' do
        otra_cuenta = create(:account)
        ajena = Helic3::Garantia.create!(account: otra_cuenta, ticket: create(:ticket, account: otra_cuenta))

        patch path(garantia_id: ajena.id),
              params: { observacion: 'Texto.' },
              headers: administrator.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when an agent is not a participant of the expediente' do
      it 'no puede anexar la observacion (update? = participante)' do
        cerrar_garantia!

        patch path,
              params: { observacion: 'Texto.' },
              headers: agent.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(garantia.reload.observacion_cierre).to be_nil
      end
    end
  end
end
