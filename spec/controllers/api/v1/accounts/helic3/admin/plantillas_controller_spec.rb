# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 admin plantillas (FMT-02)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:formato) { Helic3::Catalogo::Formato.create!(account: account, nombre: 'F', codigo: 'f', posicion: 0) }

  def docx
    Rack::Test::UploadedFile.new(StringIO.new("PK\x03\x04x"), nil, original_filename: 'p.docx')
  end

  def url(sufijo)
    "/api/v1/accounts/#{account.id}/helic3/admin/#{sufijo}"
  end

  before do
    allow(Helic3::Formatos::Conversor).to receive(:a_fodt).and_return('<office/>')
    allow(Helic3::Formatos::LlenarPlantilla).to receive(:marcadores_de).and_return(%w[CLIENTE])
  end

  it 'POST crea una plantilla y devuelve 201 [CA1]' do
    post url("formatos/#{formato.id}/plantillas"), params: { archivo: docx }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:created)
  end

  it 'sin rol administrador devuelve 401 [CA9]' do
    post url("formatos/#{formato.id}/plantillas"), params: { archivo: docx }, headers: agente.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
  end

  it 'una colision de version concurrente devuelve 422, no 500 [N1 Jhan]' do
    allow(Helic3::Formatos::SubirPlantilla).to receive(:call).and_raise(ActiveRecord::RecordNotUnique)
    post url("formatos/#{formato.id}/plantillas"), params: { archivo: docx }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'una plantilla de otra cuenta devuelve 404 [CA9]' do
    otra = Helic3::PlantillaFormato.create!(account: create(:account), formato: formato, version: 1, estado: 'borrador')
    delete url("plantillas/#{otra.id}"), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'activar retira la anterior y nunca hay dos activas [CA5]' do
    v1 = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    v2 = formato.plantillas.create!(account: account, version: 2, estado: 'borrador')

    post url("plantillas/#{v2.id}/activar"), headers: admin.create_new_auth_token

    expect(response).to have_http_status(:ok)
    expect(v1.reload.estado).to eq('retirada')
    expect(v2.reload.estado).to eq('activa')
  end

  it 'borrar una activa devuelve 422 [CA6]' do
    v1 = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    delete url("plantillas/#{v1.id}"), headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'vista_previa ?formato=docx devuelve un .docx [CA11]' do
    plantilla = formato.plantillas.create!(account: account, version: 1, estado: 'activa')
    allow(Helic3::Formatos::VistaPrevia).to receive(:call).and_return(
      { bytes: "PK\x03\x04", tipo_mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        extension: 'docx' }
    )

    get url("plantillas/#{plantilla.id}/vista_previa?formato=docx"), headers: admin.create_new_auth_token

    expect(response.media_type).to eq('application/vnd.openxmlformats-officedocument.wordprocessingml.document')
  end
end
