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
  end

  describe 'POST /super_admin/app_config?config=helic3_ia' do
    it 'guarda la llave de OpenAI' do
      post '/super_admin/app_config?config=helic3_ia',
           params: { app_config: { HELIC3_OPENAI_API_KEY: 'sk-nueva' } }

      expect(response).to redirect_to(super_admin_settings_path)
      expect(InstallationConfig.find_by(name: 'HELIC3_OPENAI_API_KEY')&.value).to eq('sk-nueva')
    end

    it 'ignora una clave ajena a la pagina (FB_APP_ID)' do
      post '/super_admin/app_config?config=helic3_ia',
           params: { app_config: { FB_APP_ID: 'no-permitido' } }

      expect(InstallationConfig.find_by(name: 'FB_APP_ID')).to be_nil
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
  end
end
