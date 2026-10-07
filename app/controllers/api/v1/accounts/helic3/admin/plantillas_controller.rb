# frozen_string_literal: true

# FMT-02: sube, previsualiza, descarga, activa y borra plantillas. Escritura (crear/
# activar/borrar) solo administradores; lectura (vista previa/original) abierta a agentes.
# Todo acotado por Current.account (una plantilla de otra cuenta da 404).
class Api::V1::Accounts::Helic3::Admin::PlantillasController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?, only: %i[create activar destroy]

  # N1 (revision Jhan #114): dos subidas del mismo formato chocan con el indice
  # unico (formato_id, version) y dos activaciones con el indice parcial de una
  # sola activa. En vez de un 500, se devuelve 422 para que la operadora reintente.
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { errores: ['otra operacion modifico esta plantilla al mismo tiempo; reintenta'] },
           status: :unprocessable_entity
  end

  FORMATOS_SALIDA = %i[pdf docx].freeze

  def create
    formato = Helic3::Catalogo::Formato.find_by!(account: Current.account, id: params[:formato_id])
    resultado = Helic3::Formatos::SubirPlantilla.call(formato: formato, archivo: params[:archivo], user: current_user)
    if resultado.ok?
      render json: carga(resultado.plantilla).merge(advertencias: resultado.advertencias), status: :created
    else
      render json: { errores: resultado.errores }, status: :unprocessable_entity
    end
  end

  def vista_previa
    formato = (params[:formato].presence || 'pdf').to_sym
    return render json: { errores: ['formato no soportado'] }, status: :unprocessable_entity unless FORMATOS_SALIDA.include?(formato)

    salida = Helic3::Formatos::VistaPrevia.call(plantilla: plantilla_de_la_cuenta, item: item_opcional,
                                                user: current_user, formato: formato)
    send_data salida[:bytes], type: salida[:tipo_mime],
                              disposition: formato == :docx ? 'attachment' : 'inline',
                              filename: "formato-#{params[:id]}.#{salida[:extension]}"
  end

  def original
    adjunto = plantilla_de_la_cuenta.original
    send_data adjunto.download, filename: adjunto.filename.to_s, type: adjunto.content_type, disposition: 'attachment'
  end

  def activar
    plantilla = plantilla_de_la_cuenta
    Helic3::PlantillaFormato.transaction do
      # update_all a proposito: retiro en bloque la activa anterior (cambio de estado
      # directo, sin callbacks) antes de activar esta; asi nunca hay dos activas.
      plantilla.formato.plantillas.activa.where.not(id: plantilla.id)
               .update_all(estado: 'retirada') # rubocop:disable Rails/SkipsModelValidations
      plantilla.update!(estado: 'activa', activada_at: Time.current, activada_por_id: current_user.id)
    end
    render json: carga(plantilla)
  end

  def destroy
    plantilla = plantilla_de_la_cuenta
    if plantilla.destroy
      head :no_content
    else
      render json: { errores: plantilla.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def plantilla_de_la_cuenta
    Helic3::PlantillaFormato.find_by!(account: Current.account, id: params[:id])
  end

  def item_opcional
    return nil if params[:item_id].blank?

    Helic3::GarantiaItem.joins(:garantia)
                        .where(helic3_garantias: { account_id: Current.account.id })
                        .find(params[:item_id])
  end

  def carga(plantilla)
    { id: plantilla.id, formato_id: plantilla.formato_id, version: plantilla.version,
      estado: plantilla.estado, marcadores: plantilla.marcadores }
  end
end
