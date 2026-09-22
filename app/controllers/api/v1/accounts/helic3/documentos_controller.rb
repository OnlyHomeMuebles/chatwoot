# EVI-02: consulta de solo lectura del archivo documental del expediente.
class Api::V1::Accounts::Helic3::DocumentosController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # GET /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/documentos
  #
  # Sincronizacion perezosa antes de listar (EVI-02, punto 3 del cableado):
  # ninguna evidencia deberia faltar aqui aunque un webhook haya fallado.
  def index
    Helic3::Casos::VincularEvidencias.call(@ticket)
    @documentos = @ticket.documentos.order(:ocurrido_at)
  end

  # POST /api/v1/accounts/:account_id/helic3/tickets/:ticket_id/documentos
  #
  # Carga manual del operador (EVI-03, 7.2): un documento que llego por fuera
  # del chat. El archivo se adjunta ANTES de guardar porque el modelo exige
  # exactamente una procedencia; sin archivo attached? el create! fallaria la
  # validacion de coherencia.
  def create
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

  # leer documentos es lo mismo que leer el expediente (show?); subir uno es
  # un acto operativo, como editar la ficha del caso (update?).
  def check_authorization
    authorize(@ticket, action_name == 'create' ? :update? : :show?)
  end

  def archivo_subido
    params.require(:archivo)
  end
end
