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

    # Revision de Jhan (PR #140): el archivo real trae ~33.000 filas, demasiado
    # para procesarse dentro de la peticion. La respuesta llega de inmediato
    # con la carga en "procesando"; el job la completa por fuera.
    it 'un administrador sube el archivo y recibe la carga de inmediato, en estado "procesando"' do
      contenido = "Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Armenia,2026-09-01,100000\n"

      expect do
        post_carga(admin, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv(contenido))
      end.to have_enqueued_job(Helic3::ImportarFacturasJob)

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('tipo' => 'facturas', 'estado' => 'procesando', 'filas_insertadas' => 0)
    end

    it 'el job procesa el archivo en background y deja la carga completada' do
      contenido = "Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Armenia,2026-09-01,100000\n"
      admin # evaluar el factory (dispara su propio job de avatar) ANTES de perform_enqueued_jobs,
      # para que ese bloque solo ejecute el job de esta carga.

      perform_enqueued_jobs do
        post_carga(admin, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv(contenido))
      end

      carga = Helic3::Carga.find(response.parsed_body['id'])
      expect(carga).to have_attributes(estado: 'completado', filas_leidas: 1, filas_insertadas: 1)
      expect(Helic3::FacturaVenta.sole.numero_documento).to eq('FV-001')
    end

    it 'rechaza un tipo que todavia no tiene parser' do
      post_carga(admin, tipo: 'garantias', modo: 'anexar', archivo: archivo_csv('a,b'))

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rechaza un archivo sin las columnas requeridas, nombrandolas, sin crear ninguna Carga' do
      post_carga(admin, tipo: 'facturas', modo: 'anexar', archivo: archivo_csv("Nro documento\nFV-001\n"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('Desc. C.O.')
      expect(Helic3::Carga.count).to eq(0)
    end

    it 'exige el archivo' do
      post_carga(admin, tipo: 'facturas', modo: 'anexar')

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # Revision de Jhan: si "modo" no llega (o llega invalido) hoy revienta con
    # un 500 (ActiveRecord::RecordInvalid sin capturar); debe ser 422.
    it 'rechaza con 422, no 500, cuando falta el modo o llega invalido' do
      post_carga(admin, tipo: 'facturas', archivo: archivo_csv("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Cali,2026-09-01,100000\n"))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Carga.count).to eq(0)
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

  describe 'DELETE cargas/:id' do
    def delete_carga(usuario, id)
      delete "/api/v1/accounts/#{account.id}/helic3/cargas/#{id}", headers: usuario.create_new_auth_token
    end

    it 'un agente no puede borrar' do
      carga = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'fallido')

      delete_carga(agente, carga.id)

      expect(response).to have_http_status(:unauthorized)
      expect(Helic3::Carga.exists?(carga.id)).to be true
    end

    it 'un administrador borra una carga vacia (sin facturas insertadas)' do
      carga = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'fallido')

      delete_carga(admin, carga.id)

      expect(response).to have_http_status(:no_content)
      expect(Helic3::Carga.exists?(carga.id)).to be false
    end

    # Tercera revision de Jhan: si se borra mientras el job de importacion
    # sigue corriendo, el insert_all/upsert_all que esta en curso reventaria
    # por la FK de carga_id apenas intente guardar la primera fila.
    it 'no deja borrar una carga mientras todavia esta "procesando"' do
      carga = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'procesando')

      delete_carga(admin, carga.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Carga.exists?(carga.id)).to be true
    end

    it 'responde 404 si la carga no existe' do
      delete_carga(admin, -1)

      expect(response).to have_http_status(:not_found)
    end

    it 'no deja borrar otra cuenta' do
      otra_cuenta = create(:account)
      carga = Helic3::Carga.create!(account: otra_cuenta, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'fallido')

      delete_carga(admin, carga.id)

      expect(response).to have_http_status(:not_found)
      expect(Helic3::Carga.exists?(carga.id)).to be true
    end

    # Las facturas insertadas son datos reales del negocio: no se van solo
    # porque se limpie el historial de "quien subio que" (dependent:
    # restrict_with_error en el modelo).
    it 'no borra una carga que ya tiene facturas insertadas' do
      carga = Helic3::Carga.create!(account: account, tipo: 'facturas', nombre_archivo: 'a.csv', modo: 'anexar',
                                    estado: 'completado', filas_insertadas: 1)
      Helic3::FacturaVenta.create!(account: account, carga: carga, numero_documento: 'FV-001',
                                   fecha: Date.current, valor_subtotal: 100_000)

      delete_carga(admin, carga.id)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Carga.exists?(carga.id)).to be true
      expect(Helic3::FacturaVenta.exists?(numero_documento: 'FV-001')).to be true
    end
  end
end
