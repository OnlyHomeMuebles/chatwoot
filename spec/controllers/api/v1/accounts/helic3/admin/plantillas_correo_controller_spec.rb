# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 admin plantillas de correo (COR-04)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:visita) do
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Visita técnica', codigo: 'visita_tecnica',
                                              posicion: 0)
  end
  let(:plantilla) do
    Helic3::PlantillaCorreo.create!(account: account, proceso_garantia: visita, disparador: 'proceso_garantia',
                                    asunto: 'Tu PQR #{{RADICADO_PQR}}', cuerpo: 'Hola {{CLIENTE}}')
  end

  def url(sufijo)
    "/api/v1/accounts/#{account.id}/helic3/admin/plantillas_correo#{sufijo}"
  end

  describe 'GET index' do
    it 'lista las plantillas de la cuenta, con el nombre del proceso [admin]' do
      plantilla
      get url(''), headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      fila = response.parsed_body.first
      expect(fila).to include('disparador' => 'proceso_garantia', 'proceso_nombre' => 'Visita técnica')
    end

    it 'un agente no puede entrar (solo admin, a diferencia del catalogo generico)' do
      get url(''), headers: agente.create_new_auth_token

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'crea una plantilla para un disparador que todavia no tenia (p. ej. garantia_negada, D2)' do
      negada = Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Garantía negada',
                                                         codigo: 'garantia_negada', posicion: 1, es_terminal: true)

      post url(''), params: { plantilla_correo: { disparador: 'proceso_garantia', proceso_garantia_id: negada.id,
                                                  asunto: 'Tu PQR #{{RADICADO_PQR}} no procede',
                                                  cuerpo: 'Lo sentimos {{CLIENTE}}.' } },
                    headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
    end

    it 'un marcador desconocido responde 422 con un mensaje legible, no 500' do
      post url(''), params: { plantilla_correo: { disparador: 'proceso_garantia', proceso_garantia_id: visita.id,
                                                  asunto: 'Hola {{CLIETNE}}', cuerpo: 'x' } },
                    headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('CLIETNE')
    end
  end

  describe 'PATCH update' do
    it 'Karen edita el asunto y el cuerpo' do
      patch url("/#{plantilla.id}"), params: { plantilla_correo: { asunto: 'Nuevo asunto' } },
                                     headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      expect(plantilla.reload.asunto).to eq('Nuevo asunto')
    end

    it 'apaga una plantilla (activo: false)' do
      patch url("/#{plantilla.id}"), params: { plantilla_correo: { activo: false } },
                                     headers: admin.create_new_auth_token

      expect(plantilla.reload.activo).to be(false)
    end

    it 'no permite cambiar el proceso ni el disparador de una plantilla ya creada' do
      otro = Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: 'Recolección', codigo: 'recoleccion',
                                                       posicion: 1)

      patch url("/#{plantilla.id}"), params: { plantilla_correo: { proceso_garantia_id: otro.id } },
                                     headers: admin.create_new_auth_token

      expect(plantilla.reload.proceso_garantia_id).to eq(visita.id)
    end
  end

  describe 'POST vista_previa' do
    it 'devuelve el asunto y el cuerpo con los datos de ejemplo del diccionario' do
      post url("/#{plantilla.id}/vista_previa"), headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['asunto']).to include('1234') # RADICADO_PQR de ejemplo
      expect(body['cuerpo_html']).to include('Cliente de Ejemplo')
    end
  end

  describe 'POST prueba' do
    # config/initializers/mailer.rb (upstream) fuerza :sendmail sin
    # SMTP_ADDRESS en cualquier ambiente, pisando el :test de
    # config/environments/test.rb -- ver el mismo comentario en
    # notificar_cambio_proceso_spec.rb.
    around do |example|
      original = ActionMailer::Base.delivery_method
      ActionMailer::Base.delivery_method = :test
      with_modified_env(SMTP_ADDRESS: 'smtp.example.com') { example.run }
      ActionMailer::Base.delivery_method = original
    end

    it 'envia la plantilla de ejemplo al correo del administrador' do
      post url("/#{plantilla.id}/prueba"), headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      mail = ActionMailer::Base.deliveries.last
      expect(mail.to).to eq([admin.email])
      expect(mail.subject).to include('[PRUEBA]')
    end
  end
end
