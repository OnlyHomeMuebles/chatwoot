# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 CRUD de agentes (H3A-05)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/helic3/agentes" }

  let!(:faq) do
    Helic3::Agente.create!(account: account, codigo: 'agente_faq', nombre: 'FAQ',
                           criterio_ruteo: 'Información general', activo: true)
  end
  let!(:triage) do
    Helic3::Agente.create!(account: account, codigo: 'agente_triage', nombre: 'Triage', es_sistema: true, activo: true)
  end

  describe 'GET index' do
    before { Helic3::AgenteBandeja.create!(agente: faq, inbox: inbox) }

    it 'lista los agentes de la cuenta con sus bandejas anidadas (crit 4)' do
      get base, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      fila = response.parsed_body.find { |a| a['codigo'] == 'agente_faq' }
      expect(fila['bandejas'].first).to include('inbox_id' => inbox.id, 'inbox_nombre' => inbox.name)
    end

    it 'un agente (no admin) recibe 401 (solo administrador)' do
      get base, headers: agent.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET show' do
    it 'un agente de OTRA cuenta devuelve 404, no 403 (crit 1)' do
      otra_cuenta = create(:account)
      ajeno = Helic3::Agente.create!(account: otra_cuenta, codigo: 'agente_faq', nombre: 'FAQ',
                                     criterio_ruteo: 'x', activo: true)

      get "#{base}/#{ajeno.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST create' do
    it 'sin criterio de ruteo devuelve 422 con el mensaje del campo (crit 2)' do
      post base, params: { agente: { codigo: 'agente_nuevo', nombre: 'Nuevo' } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['attributes']).to include('criterio_ruteo')
      expect(response.parsed_body['message']).to be_present
    end

    it 'un administrador crea un agente y le asigna bandejas' do
      post base, params: { agente: { codigo: 'agente_reventa', nombre: 'Reventa',
                                     criterio_ruteo: 'Recompra de usados', inbox_ids: [inbox.id] } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['codigo']).to eq('agente_reventa')
      expect(response.parsed_body['bandejas'].first['inbox_id']).to eq(inbox.id)
      expect(Helic3::Agente.find_by(account: account, codigo: 'agente_reventa').creado_por).to eq(admin)
    end
  end

  describe 'DELETE destroy' do
    it 'bloquea eliminar un agente de sistema con 422 (crit 3)' do
      delete "#{base}/#{triage.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Agente.exists?(triage.id)).to be(true)
    end

    it 'elimina un agente normal' do
      delete "#{base}/#{faq.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Helic3::Agente.exists?(faq.id)).to be(false)
    end
  end

  describe 'PATCH toggle' do
    it 'prende y apaga el agente' do
      patch "#{base}/#{faq.id}/toggle", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(faq.reload.activo).to be(false)
    end
  end

  describe 'PATCH update' do
    it 'un agente (no admin) no puede actualizar (401)' do
      patch "#{base}/#{faq.id}", params: { agente: { nombre: 'Cambiado' } },
                                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(faq.reload.nombre).to eq('FAQ')
    end
  end
end
