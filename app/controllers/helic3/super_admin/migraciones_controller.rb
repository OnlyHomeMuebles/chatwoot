# frozen_string_literal: true

# MIG-02 (Pieza 5): la pantalla de migración de garantías en Super Admin. Hereda de
# SuperAdmin::ApplicationController (ya exige super admin). Orquesta el flujo por
# botones: subir el CSV del DataGrid, simular (sin guardar), confirmar, revertir y
# vaciar los PQR de prueba. El trabajo pesado corre en Sidekiq; la página solo lanza
# y consulta. Una sola corrida en curso por cuenta: el estado pasa a "en curso" aquí,
# antes de encolar, para que un doble clic no lance dos.
class Helic3::SuperAdmin::MigracionesController < SuperAdmin::ApplicationController
  before_action :set_cuenta, only: %i[index create vaciar]
  before_action :set_corrida, only: %i[show simular confirmar revertir destroy]
  before_action :exigir_ninguna_en_curso, only: %i[create simular confirmar revertir vaciar]

  def index
    @corridas = Helic3::Migracion::Corrida.where(account: @cuenta).order(created_at: :desc)
    @tiene_migracion = @corridas.migraciones.completadas.exists?
    @en_curso = @corridas.en_curso.exists?
    @conteos_vaciado = Helic3::Migracion::VaciarCasos.conteos(@cuenta) unless @tiene_migracion
  end

  def show
    return unless @corrida.tipo == 'migracion' && @corrida.estado == 'completada'

    garantias = Helic3::Garantia.where(id: @corrida.casos.creados.select(:garantia_id))
    @abiertas = garantias.where(cerrada_at: nil).count
    @cerradas = garantias.where.not(cerrada_at: nil).count
    @por_proceso = Helic3::GarantiaItem.where(garantia: garantias).joins(:proceso)
                                       .group('helic3_catalogo_procesos_garantia.nombre')
                                       .distinct.count(:garantia_id)
  end

  # subir: crea la corrida con el CSV adjunto y lanza la simulación.
  def create
    corrida = Helic3::Migracion::Corrida.create!(account: @cuenta, tipo: 'migracion', estado: 'pendiente',
                                                 subido_por: current_super_admin,
                                                 archivo_nombre: params[:archivo]&.original_filename)
    corrida.archivo.attach(params[:archivo])
    Helic3::MigrarGarantiasJob.perform_later(corrida, simulacion: true)
    redirect_to helic3_admin_migracione_path(corrida)
  end

  def simular
    return volver('Solo se puede volver a simular una corrida simulada.') unless @corrida.estado == 'simulado'

    @corrida.update!(estado: 'simulando')
    Helic3::MigrarGarantiasJob.perform_later(@corrida, simulacion: true)
    redirect_to helic3_admin_migracione_path(@corrida)
  end

  def confirmar
    return volver('Solo se puede confirmar una corrida simulada.') unless @corrida.estado == 'simulado'
    if @corrida.total_fallidos.positive? && params[:entiendo] != '1'
      return volver("Marca que entiendes que #{@corrida.total_fallidos} casos no se migrarán.")
    end

    @corrida.update!(estado: 'confirmando', confirmado_por: current_super_admin)
    Helic3::MigrarGarantiasJob.perform_later(@corrida, simulacion: false)
    redirect_to helic3_admin_migracione_path(@corrida)
  end

  def vaciar
    if Helic3::Migracion::Corrida.where(account: @cuenta).migraciones.completadas.exists?
      return volver('La cuenta ya tiene una migración: no se puede vaciar.')
    end
    return volver('Escribe el nombre exacto de la cuenta para vaciar.') unless params[:confirmacion] == @cuenta.name

    corrida = Helic3::Migracion::Corrida.create!(account: @cuenta, tipo: 'vaciado', estado: 'pendiente',
                                                 subido_por: current_super_admin)
    Helic3::VaciarCasosJob.perform_later(corrida)
    redirect_to helic3_admin_migracione_path(corrida)
  end

  def revertir
    return volver('Solo se puede revertir una migración completada.') unless @corrida.tipo == 'migracion' && @corrida.estado == 'completada'

    @corrida.update!(estado: 'revirtiendo')
    Helic3::RevertirCorridaJob.perform_later(@corrida)
    redirect_to helic3_admin_migracione_path(@corrida)
  end

  def destroy
    return volver('No se puede descartar una corrida en curso.') if @corrida.en_curso?

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

  def exigir_ninguna_en_curso
    return unless Helic3::Migracion::Corrida.where(account: @cuenta).en_curso.exists?

    volver('Ya hay una simulación, migración o vaciado en curso en esta cuenta. Espera a que termine.')
  end

  def volver(alerta)
    destino = @corrida ? helic3_admin_migracione_path(@corrida) : helic3_admin_migraciones_path(account_id: @cuenta.id)
    redirect_to destino, alert: alerta
  end
end
