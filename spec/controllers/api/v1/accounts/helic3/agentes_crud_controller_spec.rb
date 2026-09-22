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
                           criterio_ruteo: 'Información general', prompt: 'p', activo: true)
  end
  let!(:triage) do
    Helic3::Agente.create!(account: account, codigo: 'agente_triage', nombre: 'Triage',
                           es_sistema: true, prompt: 'p', activo: true)
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
                                     criterio_ruteo: 'x', prompt: 'p', activo: true)

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
                                     criterio_ruteo: 'Recompra de usados',
                                     prompt: 'Especialista de recompra', inbox_ids: [inbox.id] } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['codigo']).to eq('agente_reventa')
      expect(response.parsed_body['bandejas'].first['inbox_id']).to eq(inbox.id)
      expect(Helic3::Agente.find_by(account: account, codigo: 'agente_reventa').creado_por).to eq(admin)
    end

    # revision Jhan (no bloqueante 1): no recortar bandejas ajenas en silencio
    it 'rechaza con 422 si alguna bandeja no es de la cuenta, y no crea el agente' do
      inbox_ajeno = create(:inbox, account: create(:account))

      post base, params: { agente: { codigo: 'agente_x', nombre: 'X', criterio_ruteo: 'y',
                                     prompt: 'p', inbox_ids: [inbox.id, inbox_ajeno.id] } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Agente.exists?(account: account, codigo: 'agente_x')).to be(false)
    end

    # revision Jhan (no bloqueante 2): create transaccional. La asociacion crea la
    # bandeja con save!, asi que se stubea el save! de la instancia para simular el fallo.
    it 'no deja un agente a medias si falla la creacion de una bandeja' do
      allow_any_instance_of(Helic3::AgenteBandeja).to receive(:save!) # rubocop:disable RSpec/AnyInstance
        .and_raise(ActiveRecord::RecordInvalid.new(Helic3::AgenteBandeja.new))

      expect do
        post base, params: { agente: { codigo: 'agente_x', nombre: 'X', criterio_ruteo: 'y',
                                       prompt: 'p', inbox_ids: [inbox.id] } },
                   headers: admin.create_new_auth_token, as: :json
      end.not_to change(Helic3::Agente, :count)
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

    it 'no cambia el codigo: es inmutable tras crear' do
      patch "#{base}/#{faq.id}", params: { agente: { codigo: 'otro_codigo', nombre: 'FAQ v2' } },
                                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(faq.reload.codigo).to eq('agente_faq')
      expect(faq.nombre).to eq('FAQ v2')
    end

    # inbox_ids: [] es desasignar todo (legitimo), distinto de "mandé IDs invalidos"
    it 'con inbox_ids vacio desasigna todas las bandejas (200)' do
      Helic3::AgenteBandeja.create!(agente: faq, inbox: inbox)

      patch "#{base}/#{faq.id}", params: { agente: { inbox_ids: [] } },
                                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(faq.agente_bandejas.count).to eq(0)
    end
  end

  # Endurecimiento anti-bloqueante (cacería previa al PR): el agente de sistema es
  # el hub de ruteo; pausarlo o renombrar su código rompería la orquesta.
  describe 'protección del agente de sistema' do
    it 'no deja pausar el triage con toggle (422, sigue activo)' do
      patch "#{base}/#{triage.id}/toggle", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(triage.reload.activo).to be(true)
    end

    it 'no deja apagar el triage con update activo=false (422)' do
      patch "#{base}/#{triage.id}", params: { agente: { activo: false } },
                                    headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(triage.reload.activo).to be(true)
    end
  end

  describe 'aislamiento de cuenta' do
    it 'rechaza un team de otra cuenta con 422' do
      team_ajeno = create(:team, account: create(:account))

      post base, params: { agente: { codigo: 'agente_x', nombre: 'X',
                                     criterio_ruteo: 'y', team_id: team_ajeno.id } },
                 headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Agente.exists?(account: account, codigo: 'agente_x')).to be(false)
    end
  end
end
