# frozen_string_literal: true

require 'rails_helper'

# ERP-08 (endpoint): el wizard consulta un cliente por cedula contra el ERP. El modo lo
# decide HELIC3_ERP_MODO (ERP-04); aqui se prueba contra el adaptador simulado.
RSpec.describe 'ERP clientes API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def consultar(cedula, modo: 'simulado', headers: agent.create_new_auth_token)
    with_modified_env HELIC3_ERP_MODO: modo do
      get "/api/v1/accounts/#{account.id}/helic3/erp/clientes/#{cedula}", headers: headers, as: :json
    end
  end

  describe 'GET helic3/erp/clientes/:cedula' do
    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/erp/clientes/1032456789"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'CA1: con el simulado, devuelve el cliente para una cedula conocida (con puntos)' do
      consultar('1.032.456.789')

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body['encontrado']).to be(true)
      expect(body['cliente']).to include('nombre' => 'Ana Ruiz', 'ciudad' => 'Armenia')
      expect(body['cliente']).to include('cedula', 'telefono', 'email', 'direccion')
    end

    it 'CA1: encontrado false para una cedula desconocida' do
      consultar('99999999')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['encontrado']).to be(false)
    end

    it 'responde 422 cedula_invalida para una cedula fuera de rango' do
      consultar('123')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('cedula_invalida')
    end

    it 'CA2: con el ERP desactivado responde 503 erp_desactivado' do
      consultar('1032456789', modo: nil)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('erp_desactivado')
    end

    it 'cuando el adaptador no esta disponible responde 503 erp_no_disponible' do
      allow(Helic3::Erp).to receive(:adapter).and_raise(Helic3::Erp::NoDisponible)
      consultar('1032456789')

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('erp_no_disponible')
    end
  end

  describe 'GET helic3/catalogos' do
    it 'CA2: incluye erp_habilitado (false cuando el ERP esta desactivado)' do
      with_modified_env HELIC3_ERP_MODO: nil do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos", headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['erp_habilitado']).to be(false)
    end

    it 'erp_habilitado es true cuando el ERP esta en simulado' do
      with_modified_env HELIC3_ERP_MODO: 'simulado' do
        get "/api/v1/accounts/#{account.id}/helic3/catalogos", headers: agent.create_new_auth_token, as: :json
      end

      expect(response.parsed_body['erp_habilitado']).to be(true)
    end
  end
end
