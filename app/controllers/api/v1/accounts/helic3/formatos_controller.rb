# frozen_string_literal: true

# FMT-04: generar formatos desde el expediente. La operadora ve que formatos
# tienen plantilla activa, que datos faltan por item, y genera el PDF, que
# queda en «Documentos del caso». Autoriza sobre el ticket igual que la carga
# manual (EVI-03): leer es show?, generar es update?. No confundir con el
# Admin::FormatosController, que administra las plantillas en Catalogos.
class Api::V1::Accounts::Helic3::FormatosController < Api::V1::Accounts::BaseController
  before_action :fetch_ticket
  before_action :check_authorization

  # GET: formatos con su plantilla activa (+marcadores) y los items de la
  # garantia con su formato sugerido y los marcadores que les quedan vacios.
  # El front calcula los faltantes cruzando ambos.
  def index
    @formatos = Helic3::Catalogo::Formato.where(account: Current.account)
                                         .includes(:plantillas).order(:posicion)
    @items = items_con_vacios
  end

  # POST vista_previa: PDF con los datos reales del item; NO se guarda.
  def vista_previa
    return render_item_ajeno unless item.garantia&.ticket_id == @ticket.id
    return render_sin_plantilla if plantilla_activa.nil?

    salida = Helic3::Formatos::VistaPrevia.call(plantilla: plantilla_activa, item: item,
                                                user: Current.user, formato: :pdf)
    send_data salida[:bytes], type: salida[:tipo_mime], disposition: 'inline'
  end

  # POST: genera y deja el documento en el expediente (201 con el parcial de
  # documento, el mismo que usa la carga manual). Generar valida el caso y
  # levanta Error -> 422 si no esta listo (sin garantia, sin plantilla, item ajeno).
  def create
    @documento = Helic3::Formatos::Generar.call(ticket: @ticket, item: item,
                                                formato: formato, user: Current.user)
    render 'api/v1/accounts/helic3/documentos/create', formats: [:json], status: :created
  rescue Helic3::Formatos::Generar::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # scope por cuenta: un expediente de otra cuenta no existe aqui -> 404.
  def fetch_ticket
    @ticket = Current.account.tickets.find(params[:ticket_id])
  end

  # leer lo disponible es como leer el expediente (show?); generar es un acto
  # operativo, como editar la ficha (update?). Pundit -> 403 sin permiso.
  def check_authorization
    authorize(@ticket, action_name == 'index' ? :show? : :update?)
  end

  # por cuenta, no por la garantia del ticket: un item de otra garantia de la
  # MISMA cuenta se encuentra y Generar lo rechaza con 422; uno de otra cuenta
  # no existe aqui -> 404.
  def item
    @item ||= Helic3::GarantiaItem.find_by!(account: Current.account, id: params[:item_id])
  end

  def formato
    @formato ||= Helic3::Catalogo::Formato.find_by!(account: Current.account, id: params[:formato_id])
  end

  def plantilla_activa
    @plantilla_activa ||= formato.plantillas.activa.first
  end

  # cada item con los marcadores cuyo valor resuelto quedo vacio. El front los
  # cruza con los marcadores de cada plantilla para mostrar solo lo que falta.
  def items_con_vacios
    (@ticket.garantia&.items || []).map do |it|
      datos = Helic3::Formatos::DatosDelFormato.call(item: it, user: Current.user)
      { item: it, vacios: datos.select { |_clave, valor| valor.to_s.strip.empty? }.keys }
    end
  end

  def render_sin_plantilla
    render json: { error: 'el formato no tiene una plantilla activa' }, status: :unprocessable_entity
  end

  def render_item_ajeno
    render json: { error: 'el item no pertenece a una garantia de este expediente' },
           status: :unprocessable_entity
  end
end
