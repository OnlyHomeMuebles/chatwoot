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

  describe 'GET helic3/erp/clientes/:cedula/facturas (ERP-15)' do
    def facturas(cedula, modo: 'simulado', headers: agent.create_new_auth_token)
      with_modified_env HELIC3_ERP_MODO: modo do
        get "/api/v1/accounts/#{account.id}/helic3/erp/clientes/#{cedula}/facturas", headers: headers, as: :json
      end
    end

    it 'exige autenticacion' do
      get "/api/v1/accounts/#{account.id}/helic3/erp/clientes/1032456789/facturas"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'CA1: con el simulado, devuelve las facturas con sus productos para una cedula conocida' do
      facturas('1.032.456.789')

      expect(response).to have_http_status(:success)
      lista = response.parsed_body['facturas']
      expect(lista.map { |f| f['numero'] }).to contain_exactly('FV-1001', 'FV-1002')

      con_dos = lista.find { |f| f['numero'] == 'FV-1001' }
      expect(con_dos).to include('fecha', 'total', 'centro_operacion' => 'Armenia Centro')
      expect(con_dos['items'].size).to eq(2)
      expect(con_dos['items'].first).to include('referencia' => 'MIL-200', 'descripcion' => 'Puerta Milano',
                                                'cantidad' => 2, 'valor' => 900_000)
    end

    it 'CA1: una cedula sin facturas devuelve lista vacia (no es error)' do
      facturas('99999999')

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['facturas']).to eq([])
    end

    it 'responde 422 cedula_invalida para una cedula fuera de rango' do
      facturas('123')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('cedula_invalida')
    end

    it 'CA2: con el ERP desactivado responde 503 erp_desactivado' do
      facturas('1032456789', modo: nil)

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body['error']).to eq('erp_desactivado')
    end

    it 'cuando el adaptador no esta disponible responde 503 erp_no_disponible' do
      allow(Helic3::Erp).to receive(:adapter).and_raise(Helic3::Erp::NoDisponible)
      facturas('1032456789')

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

  describe 'POST create con consultado_erp (end-to-end)' do
    before { Helic3::Catalogo::SeederService.new(account).sembrar! }

    let(:motivo) { Helic3::Catalogo::MotivoPqr.find_by!(account: account, codigo: 'garantia_producto') }

    it 'CA3: radica con consultado_erp y marca erp lo de Siesa, humano lo que el agente corrigio' do
      with_modified_env HELIC3_ERP_MODO: 'simulado' do
        post "/api/v1/accounts/#{account.id}/helic3/tickets",
             params: { ticket: { title: 'Caso', motivo_pqr_id: motivo.id, consultado_erp: true,
                                 datos: { cedula: '1032456789', cliente_nombre: 'Ana Ruiz',
                                          cliente_telefono: '3001112233', direccion: 'Correccion 1' } } },
             headers: agent.create_new_auth_token, as: :json
      end

      expect(response).to have_http_status(:success)
      ficha = Helic3::Ticket.find(response.parsed_body['id']).datos
      expect(ficha.fuentes['cliente_nombre']).to eq('erp')
      expect(ficha.fuentes['direccion']).to eq('humano')
      expect(ficha.direccion).to eq('Correccion 1')
    end
  end
end
