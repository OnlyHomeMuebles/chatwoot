# frozen_string_literal: true

# MIG-02 (Pieza 5): la pantalla de migración de garantías en Super Admin. Hereda de
# SuperAdmin::ApplicationController (ya exige super admin). Orquesta el flujo por
# botones: subir el CSV del DataGrid, simular (sin guardar), confirmar y vaciar los
# PQR de prueba. El trabajo pesado corre en Sidekiq; la página solo lanza y consulta.
#
# NOTA: el actor es un super_admin (tabla aparte de users); subido_por/confirmado_por
# quedan en nil hasta reapuntar esas FK a super_admins (TODO).
class Helic3::SuperAdmin::MigracionesController < SuperAdmin::ApplicationController
  before_action :set_cuenta, only: %i[index create vaciar]
  before_action :set_corrida, only: %i[show simular confirmar revertir destroy]

  def index
    @corridas = Helic3::Migracion::Corrida.where(account: @cuenta).order(created_at: :desc)
    @tiene_migracion = @corridas.migraciones.completadas.exists?
  end

  def show; end

  # subir: crea la corrida con el CSV adjunto y lanza la simulación.
  def create
    corrida = Helic3::Migracion::Corrida.create!(account: @cuenta, tipo: 'migracion', estado: 'pendiente',
                                                 archivo_nombre: params[:archivo]&.original_filename)
    corrida.archivo.attach(params[:archivo])
    Helic3::MigrarGarantiasJob.perform_later(corrida, simulacion: true)
    redirect_to helic3_admin_migracione_path(corrida)
  end

  def simular
    Helic3::MigrarGarantiasJob.perform_later(@corrida, simulacion: true)
    redirect_to helic3_admin_migracione_path(@corrida)
  end

  def confirmar
    Helic3::MigrarGarantiasJob.perform_later(@corrida, simulacion: false)
    redirect_to helic3_admin_migracione_path(@corrida)
  end

  def vaciar
    corrida = Helic3::Migracion::Corrida.create!(account: @cuenta, tipo: 'vaciado', estado: 'pendiente')
    Helic3::VaciarCasosJob.perform_later(corrida)
    redirect_to helic3_admin_migraciones_path(account_id: @cuenta.id)
  end

  def revertir
    redirect_to helic3_admin_migracione_path(@corrida), alert: 'Revertir aún no está implementado.'
  end

  def destroy
    @corrida.archivo.purge_later if @corrida.archivo.attached?
    @corrida.update!(estado: 'descartada')
    redirect_to helic3_admin_migraciones_path(account_id: @corrida.account_id)
  end

  private

  # Administrate deriva el "namespace" del nombre de la clase (Helic3::SuperAdmin::...),
  # y con ese namespace el menú lateral trataría 'migraciones' como un recurso suyo y
  # buscaría un dashboard inexistente. Lo forzamos a :super_admin —el namespace real del
  # panel, donde esta página no figura como recurso— para que el menú se dibuje normal.
  def namespace
    :super_admin
  end

  def set_cuenta
    @cuentas = Account.order(:name)
    @cuenta = params[:account_id].present? ? Account.find(params[:account_id]) : @cuentas.first
  end

  def set_corrida
    @corrida = Helic3::Migracion::Corrida.find(params[:id])
    @cuenta = @corrida.account
  end
end
