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

    # Un enum enviado vacio (el select sin tocar) no debe reventar con 500: el campo
    # en blanco se descarta y la columna usa su default.
    it 'crear sin elegir abre_garantia no rompe' do
      post base,
           params: { catalogo: { nombre: 'Retracto', codigo: 'retracto',
                                 categoria_id: categoria.id, abre_garantia: '' } },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
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

  # Las cuatro entradas que sumó ADM-02: mismo contrato del controlador
  # (crear, actualizar, desactivar, rechazar codigo repetido), sin repetir el
  # detalle fila por fila que ya cubren los specs de arriba para motivos_pqr.
  shared_examples 'catalogo con las cuatro operaciones (ADM-02)' do |tipo|
    let(:base_nuevo) { "/api/v1/accounts/#{account.id}/helic3/admin/catalogos/#{tipo}" }

    it 'un administrador crea un registro' do
      post base_nuevo, params: { catalogo: atributos_validos }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:created)
      expect(modelo.find_by(account: account, codigo: atributos_validos[:codigo])).to be_present
    end

    it 'un administrador actualiza el nombre' do
      patch "#{base_nuevo}/#{registro.id}",
            params: { catalogo: { nombre: 'Editado' } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(registro.reload.nombre).to eq('Editado')
    end

    it 'un administrador desactiva el registro sin borrarlo' do
      patch "#{base_nuevo}/#{registro.id}",
            params: { catalogo: { activo: false } },
            headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(registro.reload.activo).to be(false)
    end

    it 'rechaza un codigo repetido' do
      post base_nuevo,
           params: { catalogo: atributos_validos.merge(codigo: registro.codigo) },
           headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'catalogos nuevos (ADM-02)' do
    describe 'categorias' do
      let(:modelo) { Helic3::Catalogo::Categoria }
      let(:atributos_validos) { { nombre: 'Devoluciones', codigo: 'devoluciones' } }
      let(:registro) { modelo.create!(account: account, nombre: 'Garantía', codigo: 'garantia') }

      it_behaves_like 'catalogo con las cuatro operaciones (ADM-02)', 'categorias'

      # genera_radicado nace en true por columna: apagarlo al crear no se
      # puede perder silenciosamente (es la razon de ser del ticket).
      it 'respeta genera_radicado en false al crear' do
        post "/api/v1/accounts/#{account.id}/helic3/admin/catalogos/categorias",
             params: { catalogo: { nombre: 'Información', codigo: 'informacion', genera_radicado: false } },
             headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:created)
        expect(Helic3::Catalogo::Categoria.find_by(account: account, codigo: 'informacion').genera_radicado).to be(false)
      end
    end

    describe 'tipos' do
      let(:modelo) { Helic3::Catalogo::Tipo }
      let(:atributos_validos) { { nombre: 'Sugerencia', codigo: 'sugerencia' } }
      let(:registro) { modelo.create!(account: account, nombre: 'Petición', codigo: 'peticion') }

      it_behaves_like 'catalogo con las cuatro operaciones (ADM-02)', 'tipos'
    end

    describe 'etapas_pqr' do
      let(:modelo) { Helic3::Catalogo::EtapaPqr }
      let(:atributos_validos) { { nombre: 'En trámite', codigo: 'en_tramite' } }
      let(:registro) { modelo.create!(account: account, nombre: 'Radicada', codigo: 'radicada') }

      it_behaves_like 'catalogo con las cuatro operaciones (ADM-02)', 'etapas_pqr'
    end

    describe 'motivos_garantia' do
      let(:modelo) { Helic3::Catalogo::MotivoGarantia }
      let(:atributos_validos) { { nombre: 'Producto incompleto', codigo: 'producto_incompleto' } }
      let(:registro) { modelo.create!(account: account, nombre: 'Error de pedido', codigo: 'error_pedido') }

      it_behaves_like 'catalogo con las cuatro operaciones (ADM-02)', 'motivos_garantia'
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
