# COR-04: Karen edita el asunto/cuerpo de cualquier plantilla de correo, la
# prende o la apaga, la ve tal como llega y se envia una prueba -- sin pedirle
# nada a desarrollo. Solo administradores, mismo criterio que
# Admin::CatalogosController (lectura y escritura aqui son ambas admin-only:
# a diferencia de un catalogo, el texto de un correo no lo necesita ver un
# agente para operar el expediente).
class Api::V1::Accounts::Helic3::Admin::PlantillasCorreoController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :set_registro, only: %i[update vista_previa prueba]

  def index
    @registros = Helic3::PlantillaCorreo.where(account: Current.account)
                                        .includes(:proceso_garantia).order(:id)
  end

  # Para un disparador sin plantilla todavia (p. ej. garantia_negada, D2).
  def create
    @registro = Helic3::PlantillaCorreo.new(plantilla_params.merge(account: Current.account))
    @registro.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render_invalido(e.record)
  end

  # disparador y proceso_garantia_id no se editan: cambiar a que dispara una
  # plantilla ya creada es borrarla y crear otra, no una edicion.
  def update
    @registro.update!(plantilla_params.except(:disparador, :proceso_garantia_id))
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render_invalido(e.record)
  end

  # HTML tal como le llegaria al cliente, con los datos de ejemplo del
  # diccionario de marcadores (sin necesitar un caso real).
  def vista_previa
    render json: {
      asunto: Helic3::Correos::Renderizar.asunto(@registro.asunto, datos_de_ejemplo),
      cuerpo_html: Helic3::Correos::Renderizar.cuerpo_html(@registro.cuerpo, datos_de_ejemplo)
    }
  end

  def prueba
    Helic3::NotificacionesMailer.with(account: Current.account)
                                .correo_proceso(
                                  destinatario: Current.user.email,
                                  asunto: "[PRUEBA] #{Helic3::Correos::Renderizar.asunto(@registro.asunto, datos_de_ejemplo)}",
                                  cuerpo_html: Helic3::Correos::Renderizar.cuerpo_html(@registro.cuerpo, datos_de_ejemplo)
                                ).deliver_now
    head :ok
  rescue *ExceptionList::SMTP_EXCEPTIONS
    render json: { error: I18n.t('helic3.correos.smtp_no_configurado') }, status: :unprocessable_entity
  end

  private

  def datos_de_ejemplo
    Helic3::Formatos::DatosDelFormato::DATOS_DE_EJEMPLO
  end

  def set_registro
    @registro = Helic3::PlantillaCorreo.find_by!(account: Current.account, id: params[:id])
  end

  def plantilla_params
    params.require(:plantilla_correo).permit(:asunto, :cuerpo, :activo, :disparador, :proceso_garantia_id)
  end

  # Un marcador desconocido ({{CLIETNE}}) es el error esperable aqui: se
  # traduce a 422 con el mensaje de la validacion, no a un 500.
  def render_invalido(record)
    render json: { error: record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end
end
