# frozen_string_literal: true

require 'rails_helper'

# CFG-01: pagina "Helic3 · Agentes IA" en Super Admin. Mismo patron que
# spec/controllers/super_admin/app_config_controller_spec.rb.
RSpec.describe 'Super Admin · Helic3 Agentes IA', type: :request do
  let(:super_admin) { create(:super_admin) }

  before { sign_in(super_admin, scope: :super_admin) }

  describe 'GET /super_admin/app_config?config=helic3_ia' do
    it 'pinta el campo OpenAI API Key' do
      get '/super_admin/app_config?config=helic3_ia'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('OpenAI API Key')
    end

    it 'pinta el campo Modelo de visión para imágenes' do
      get '/super_admin/app_config?config=helic3_ia'

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Modelo de visión para imágenes')
    end
  end

  describe 'POST /super_admin/app_config?config=helic3_ia' do
    it 'guarda la llave de OpenAI' do
      post '/super_admin/app_config?config=helic3_ia',
           params: { app_config: { HELIC3_OPENAI_API_KEY: 'sk-nueva' } }

      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'HELIC3_OPENAI_API_KEY')&.value).to eq('sk-nueva')
    end

    it 'guarda el modelo de visión para imágenes' do
      post '/super_admin/app_config?config=helic3_ia',
           params: { app_config: { HELIC3_VISION_MODELO: 'gpt-6.1-terra' } }

      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'HELIC3_VISION_MODELO')&.value).to eq('gpt-6.1-terra')
    end

    it 'ignora una clave ajena a la pagina (FB_APP_ID)' do
      post '/super_admin/app_config?config=helic3_ia',
           params: { app_config: { FB_APP_ID: 'no-permitido' } }

      expect(InstallationConfig.find_by(name: 'FB_APP_ID')).to be_nil
    end
  end

  # ERP-16: pagina "Helic3 · ERP Siesa" con el modo y la conexion de Siesa HUB.
  describe 'GET /super_admin/app_config?config=helic3_erp' do
    it 'pinta los 8 campos de la conexion' do
      get '/super_admin/app_config?config=helic3_erp'

      expect(response).to have_http_status(:success)
      ['Modo del ERP', 'URL base de Siesa HUB', 'Client ID (Apigee)', 'ConniKey', 'ConniToken', 'Compañía',
       'Consulta de clientes', 'Consultas de compras (separadas por coma)'].each do |titulo|
        expect(response.body).to include(titulo)
      end
    end

    it 'los tres secretos salen ocultos (password) y el modo es un select' do
      get '/super_admin/app_config?config=helic3_erp'

      html = Nokogiri::HTML(response.body)
      %w[HELIC3_SIESA_HUB_CLIENT_ID HELIC3_SIESA_HUB_CONNI_KEY HELIC3_SIESA_HUB_CONNI_TOKEN].each do |clave|
        expect(html.at_css("input[name='app_config[#{clave}]']")['type']).to eq('password')
      end
      opciones = html.css("select[name='app_config[HELIC3_ERP_MODO]'] option").map { |o| o['value'] }
      expect(opciones).to eq(%w[desactivado simulado siesa])
    end
  end

  describe 'POST /super_admin/app_config?config=helic3_erp' do
    it 'guarda el modo y la conexion' do
      post '/super_admin/app_config?config=helic3_erp',
           params: { app_config: { HELIC3_ERP_MODO: 'siesa', HELIC3_SIESA_HUB_CONNI_KEY: 'key-nueva' } }

      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'HELIC3_ERP_MODO')&.value).to eq('siesa')
      expect(InstallationConfig.find_by(name: 'HELIC3_SIESA_HUB_CONNI_KEY')&.value).to eq('key-nueva')
    end

    it 'ignora una clave de la otra pagina de Helic3 (la llave de OpenAI)' do
      post '/super_admin/app_config?config=helic3_erp',
           params: { app_config: { HELIC3_OPENAI_API_KEY: 'sk-no-permitida' } }

      expect(InstallationConfig.find_by(name: 'HELIC3_OPENAI_API_KEY')).to be_nil
    end
  end

  describe 'las demas paginas quedan intactas' do
    it 'GET ?config=facebook sigue respondiendo' do
      get '/super_admin/app_config?config=facebook'
      expect(response).to have_http_status(:success)
    end

    it 'GET ?config=captain sigue respondiendo' do
      get '/super_admin/app_config?config=captain'
      expect(response).to have_http_status(:success)
    end
  end

  describe 'GET /super_admin/settings' do
    it 'muestra la entrada Helic3 · Agentes IA' do
      get '/super_admin/settings'

      expect(response.body).to include('Helic3 · Agentes IA')
    end

    it 'muestra la tarjeta Helic3 · ERP Siesa' do
      get '/super_admin/settings'

      expect(response.body).to include('Helic3 · ERP Siesa', 'Conexión de Helic3 con el ERP Siesa')
    end
  end
end
