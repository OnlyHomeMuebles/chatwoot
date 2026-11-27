# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin · Helic3 Migración de garantías', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }
  let(:archivo) { Rack::Test::UploadedFile.new(StringIO.new('csv'), 'text/csv', original_filename: 'datagrid.csv') }

  describe 'sin sesión de super admin' do
    it 'redirige al login' do
      get "/helic3-admin/migraciones?account_id=#{account.id}"

      expect(response).to have_http_status(:redirect)
    end

    it 'redirige a un usuario normal sin crear la corrida' do
      sign_in(create(:user, account: account), scope: :user)
      post "/helic3-admin/migraciones?account_id=#{account.id}", params: { archivo: archivo }

      expect(response).to have_http_status(:redirect)
      expect(Helic3::Migracion::Corrida.count).to eq(0)
    end
  end

  describe 'con super admin' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'muestra cuánto borraría el vaciado' do
      get "/helic3-admin/migraciones?account_id=#{account.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Garantías:', 'Archivos:', 'Escribe el nombre de la cuenta')
    end

    it 'muestra el reporte de una migración completada con el conteo por proceso' do
      corrida = Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'completada')
      get "/helic3-admin/migraciones/#{corrida.id}"

      expect(response).to have_http_status(:success)
      expect(response.body).to include('Garantías por proceso', 'Revertir esta migración')
    end

    it 'sube el archivo, guarda quién lo subió y lanza la simulación' do
      expect do
        post "/helic3-admin/migraciones?account_id=#{account.id}", params: { archivo: archivo }
      end.to have_enqueued_job(Helic3::MigrarGarantiasJob)

      expect(Helic3::Migracion::Corrida.last.subido_por_id).to eq(super_admin.id)
    end

    it 'no deja lanzar otra corrida mientras hay una en curso' do
      Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'simulando')

      expect do
        post "/helic3-admin/migraciones?account_id=#{account.id}", params: { archivo: archivo }
      end.not_to have_enqueued_job(Helic3::MigrarGarantiasJob)
      expect(flash[:alert]).to include('en curso')
    end

    it 'no deja vaciar sin escribir el nombre de la cuenta' do
      expect do
        post "/helic3-admin/migraciones/vaciar?account_id=#{account.id}", params: { confirmacion: 'otra' }
      end.not_to have_enqueued_job(Helic3::VaciarCasosJob)
    end

    it 'vacía al escribir el nombre exacto de la cuenta' do
      expect do
        post "/helic3-admin/migraciones/vaciar?account_id=#{account.id}", params: { confirmacion: account.name }
      end.to have_enqueued_job(Helic3::VaciarCasosJob)
    end

    describe 'confirmar' do
      let(:corrida) do
        Helic3::Migracion::Corrida.create!(account: account, tipo: 'migracion', estado: 'simulado', total_fallidos: 2)
      end

      it 'exige marcar que se entiende que los fallidos no se migran' do
        expect { post "/helic3-admin/migraciones/#{corrida.id}/confirmar" }.not_to have_enqueued_job(Helic3::MigrarGarantiasJob)
      end

      it 'confirma, guarda quién confirmó y lanza la migración real' do
        expect do
          post "/helic3-admin/migraciones/#{corrida.id}/confirmar", params: { entiendo: '1' }
        end.to have_enqueued_job(Helic3::MigrarGarantiasJob).with(corrida, simulacion: false)

        expect(corrida.reload).to have_attributes(estado: 'confirmando', confirmado_por_id: super_admin.id)
      end
    end
  end
end
