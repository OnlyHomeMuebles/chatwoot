# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Helic3 Cargas (IND-03, parcial)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agente) { create(:user, account: account, role: :agent) }

  def archivo_csv(contenido)
    Rack::Test::UploadedFile.new(StringIO.new(contenido), 'text/csv', original_filename: 'facturas.csv')
  end

  describe 'POST cargas' do
    def post_carga(usuario, params = {})
      post "/api/v1/accounts/#{account.id}/helic3/cargas", params: params, headers: usuario.create_new_auth_token
    end

    it 'exige autenticacion' do
      post "/api/v1/accounts/#{account.id}/helic3/cargas", params: { tipo: 'facturas' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'un agente no puede cargar (solo administradores)' do
      post_carga(agente, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv('a,b'))

      expect(response).to have_http_status(:unauthorized)
    end

    it 'un administrador carga facturas y recibe el resultado' do
      contenido = "Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Armenia,2026-09-01,100000\n"

      post_carga(admin, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv(contenido))

      expect(response).to have_http_status(:success)
      body = response.parsed_body
      expect(body).to include('tipo' => 'facturas', 'estado' => 'completado', 'filas_insertadas' => 1)
    end

    it 'rechaza un tipo que todavia no tiene parser' do
      post_carga(admin, tipo: 'garantias', modo: 'anexar', archivo: archivo_csv('a,b'))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza un archivo sin las columnas requeridas, nombrandolas' do
      post_carga(admin, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv("Nro documento\nFV-001\n"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Desc. C.O.')
    end

    it 'exige el archivo' do
      post_carga(admin, tipo: 'facturas', modo: 'anexar')

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'GET cargas' do
    def get_cargas(usuario)
      get "/api/v1/accounts/#{account.id}/helic3/cargas", headers: usuario.create_new_auth_token
    end

    it 'un agente no puede listar' do
      get_cargas(agente)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'un administrador ve las cargas de su cuenta, mas recientes primero' do
      vieja = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'completado', created_at: 2.days.ago)
      nueva = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'b.csv', modo: 'anexar',
                                    estado: 'completado')
      otra_cuenta = create(:account)
      Helic3::Carga.create!(account: otra_cuenta, tipo: 'facturas', nombre_archivo: 'c.csv', modo: 'anexar',
                            estado: 'completado')

      get_cargas(admin)

      expect(response).to have_http_status(:success)
      ids = response.parsed_body.pluck('id')
      expect(ids).to eq([nueva.id, vieja.id])
    end
  end
end
