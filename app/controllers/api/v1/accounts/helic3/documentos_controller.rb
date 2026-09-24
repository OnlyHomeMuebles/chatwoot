# EVI-02: consulta de solo lectura del archivo documental del expediente.
class Api::V1::Accounts::Helic3::DocumentosController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/documentos
  #
  # Sincronizacion perezosa antes de listar (EVI-02, punto 3 del cableado):
  # ninguna evidencia deberia faltar aqui aunque un webhook haya fallado.
  def index
    sincronizar_evidencias
    # documento.url/tipo_archivo resuelven contra el blob de ActiveStorage de
    # cualquiera de las dos procedencias: sin este preload, cada fila dispara
    # su propia consulta (N+1) al armar la URL de descarga.
    @documentos = @ticket.documentos
                         .includes(attachment: { file_attachment: :blob })
                         .with_attached_archivo
                         .order(:ocurrido_at)
  end

  # POST /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/documentos
  #
  # Carga manual del operador (EVI-03, 7.2): un documento que llego por fuera
  # del chat. El archivo se adjunta ANTES de guardar porque el modelo exige
  # exactamente una procedencia; sin archivo attached? el create! fallaria la
  # validacion de coherencia.
  def create
    return render_archivo_invalido unless archivo_subido.respond_to?(:original_filename)

    @documento = @ticket.documentos.build(
      account: Current.account, clase: 'evidencia', origen: 'operador',
      remitente_user: Current.user, remitente_nombre: Current.user.name,
      ocurrido_at: Time.current, titulo: archivo_subido.original_filename,
      descripcion: params[:descripcion]
    )
    @documento.archivo.attach(archivo_subido)
    @documento.save!
  end

  private

  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # best-effort (EVI-02/EVI-03): si un documento puntual falla su validacion,
  # el listado debe seguir respondiendo igual -- una evidencia sin sincronizar
  # es un problema de datos, no un endpoint roto. Mismo patron que
  # VincularEvidenciasJob.
  def sincronizar_evidencias
    Helic3::Casos::VincularEvidencias.call(@ticket)
  rescue StandardError => e
    Rails.logger.error("[Helic3] vincular_evidencias (documentos#index) ticket=#{@ticket.id}: #{e.class}: #{e.message}")
  end

  # leer documentos es lo mismo que leer el expediente (show?); subir uno es
  # un acto operativo, como editar la ficha del caso (update?).
  def check_authorization
    authorize(@ticket, action_name == 'create' ? :update? : :show?)
  end

  def archivo_subido
    params.require(:archivo)
  end

  # params.require(:archivo) solo garantiza que la llave vino; si llega un
  # string en vez de un archivo, original_filename explota con 500 mas
  # adelante. Se valida aqui, en el borde, para devolver 422.
  def render_archivo_invalido
    render json: { error: 'archivo debe ser un archivo subido' }, status: :unprocessable_entity
  end
end
