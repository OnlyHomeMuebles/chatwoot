require 'rails_helper'

RSpec.describe 'Helic3 administracion de catalogos (ADM-01)', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:categoria) { Helic3::Catalogo::Categoria.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }

  let(:base) { "/api/v1/accounts/#{account.id}/helic3/admin/catalogos/motivos_pqr" }

  def crear_motivo(codigo: 'garantia_producto', nombre: 'Garantía de producto')
    Helic3::Catalogo::MotivoPqr.create!(account: account, categoria: categoria, codigo: codigo, nombre: nombre)
  end

  describe 'lectura' do
    it 'un agente puede LEER el catalogo' do
      crear_motivo

      get base, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.first['codigo']).to eq('garantia_producto')
    end
  end

  describe 'escritura (solo administradores)' do
    it 'un administrador crea un motivo nuevo' do
      post base,
           params: { catalogo: { nombre: 'Retracto', codigo: 'retracto', categoria_id: categoria.id } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(Helic3::Catalogo::MotivoPqr.find_by(account: account, codigo: 'retracto')).to be_present
    end

    it 'un agente que intenta escribir recibe 401' do
      post base,
           params: { catalogo: { nombre: 'Retracto', codigo: 'retracto', categoria_id: categoria.id } },
           headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'el codigo es inmutable: no cambia al actualizar' do
      motivo = crear_motivo

      patch "#{base}/#{motivo.id}",
            params: { catalogo: { codigo: 'otro', nombre: 'Nombre nuevo' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(motivo.reload.codigo).to eq('garantia_producto')
      expect(motivo.nombre).to eq('Nombre nuevo')
    end

    it 'desactivar oculta el motivo sin borrarlo' do
      motivo = crear_motivo

      patch "#{base}/#{motivo.id}",
            params: { catalogo: { activo: false } },
            headers: admin.create_new_auth_token, as: :json

      expect(motivo.reload.activo).to be(false)
      expect(Helic3::Catalogo::MotivoPqr.activos.where(account: account)).to be_empty
    end
  end

  describe 'borrado' do
    it 'borra un motivo que nadie usa' do
      motivo = crear_motivo

      delete "#{base}/#{motivo.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Helic3::Catalogo::MotivoPqr.exists?(motivo.id)).to be(false)
    end

    it 'rechaza borrar un motivo referenciado por un expediente y pide desactivarlo' do
      motivo = crear_motivo
      create(:ticket, account: account, motivo_pqr: motivo)

      delete "#{base}/#{motivo.id}", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Helic3::Catalogo::MotivoPqr.exists?(motivo.id)).to be(true)
    end
  end

  describe 'acotado a la cuenta y al catalogo' do
    it 'un catalogo desconocido responde 404' do
      get "/api/v1/accounts/#{account.id}/helic3/admin/catalogos/inexistente",
          headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'no se puede editar una fila de otra cuenta' do
      otra = create(:account)
      ajeno = Helic3::Catalogo::MotivoPqr.create!(
        account: otra, codigo: 'ajeno', nombre: 'Ajeno',
        categoria: Helic3::Catalogo::Categoria.create!(account: otra, nombre: 'G', codigo: 'g')
      )

      patch "#{base}/#{ajeno.id}",
            params: { catalogo: { nombre: 'Hackeado' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
