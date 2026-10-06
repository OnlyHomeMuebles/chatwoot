# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 formatos desde el expediente (FMT-04)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:ticket) { create(:ticket, account: account) }
  let(:garantia) { Helic3::Garantia.create!(account: account, ticket: ticket) }
  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica',
                                              codigo: 'visita_tecnica', posicion: 0)
  end
  let(:item) { garantia.items.create!(account: account, producto_nombre: 'Sofá', proceso: visita) }
  let(:formato) do
    Helic3::Catalogo::Formato.create!(account: account, nombre: 'No. 3 · Visita de técnico',
                                      codigo: 'visita_tecnica', posicion: 0)
  end

  def plantilla_activa
    formato.plantillas.create!(account: account, version: 1, estado: 'activa', marcadores: %w[CLIENTE CEDULA])
  end

  def url(sufijo = '')
    "/api/v1/accounts/#{account.id}/helic3/tickets/#{ticket.id}/formatos#{sufijo}"
  end

  before do
    allow(Helic3::Formatos::VistaPrevia).to receive(:call).and_return(
      { bytes: '%PDF-1.4 demo', tipo_mime: 'application/pdf', extension: 'pdf' }
    )
  end

  describe 'GET index' do
    it 'lista los formatos con su plantilla activa y sus marcadores' do
      plantilla_activa
      get url, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      formato_json = response.parsed_body['formatos'].first
      expect(formato_json['codigo']).to eq('visita_tecnica')
      expect(formato_json['plantilla_activa']['marcadores']).to contain_exactly('CLIENTE', 'CEDULA')
    end

    it 'marca el formato sugerido según el proceso del ítem [CA7]' do
      visita.update!(formato_sugerido: formato)
      item
      get url, headers: admin.create_new_auth_token, as: :json

      item_json = response.parsed_body['items'].first
      expect(item_json['formato_sugerido_id']).to eq(formato.id)
    end

    it 'lista CEDULA como marcador vacío de un caso sin ficha [CA6]' do
      item
      get url, headers: admin.create_new_auth_token, as: :json

      item_json = response.parsed_body['items'].first
      expect(item_json['marcadores_vacios']).to include('CEDULA')
    end
  end

  describe 'POST create' do
    it 'genera el formato y devuelve 201 con el documento [CA1]' do
      plantilla_activa
      expect do
        post url, params: { formato_id: formato.id, item_id: item.id }, headers: admin.create_new_auth_token
      end.to change { ticket.documentos.where(clase: 'formato').count }.by(1)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['clase']).to eq('formato')
    end

    it 'sin plantilla activa devuelve 422 [CA5]' do
      post url, params: { formato_id: formato.id, item_id: item.id }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'con un ítem de otra garantía devuelve 422 [CA5]' do
      plantilla_activa
      ajeno = Helic3::Garantia.create!(account: account, ticket: create(:ticket, account: account))
                              .items.create!(account: account, producto_nombre: 'Mesa')
      post url, params: { formato_id: formato.id, item_id: ajeno.id }, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
    end

    # CA5 pide 403, pero Chatwoot mapea Pundit::NotAuthorizedError -> 401 de forma
    # global (request_exception_handler#render_unauthorized). Igual que los demas
    # controllers del modulo (FMT-02). La discrepancia 401/403 queda anotada para Jhan.
    it 'sin permiso sobre el expediente devuelve 401 [CA5]' do
      plantilla_activa
      post url, params: { formato_id: formato.id, item_id: item.id }, headers: agente.create_new_auth_token
      expect(response).to have_http_status(:unauthorized)
    end

    it 'con un expediente de otra cuenta devuelve 404 [CA5]' do
      otra = create(:account)
      otro_admin = create(:user, account: otra, role: :administrator)
      post "/api/v1/accounts/#{otra.id}/helic3/tickets/#{ticket.id}/formatos",
           params: { formato_id: formato.id, item_id: item.id }, headers: otro_admin.create_new_auth_token
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST vista_previa' do
    it 'devuelve un PDF con los datos del ítem [CA1]' do
      plantilla_activa
      post url('/vista_previa'), params: { formato_id: formato.id, item_id: item.id },
                                 headers: admin.create_new_auth_token
      expect(response.media_type).to eq('application/pdf')
    end
  end
end
