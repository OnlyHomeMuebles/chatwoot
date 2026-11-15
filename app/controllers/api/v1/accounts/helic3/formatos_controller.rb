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
    # solo formatos activos: uno desactivado (FMT-06) no se ofrece para generar.
    @formatos = Helic3::Catalogo::Formato.where(account: Current.account, activo: true)
                                         .includes(:plantillas).order(:posicion)
    @items = items_con_vacios
  end

  # POST vista_previa: PDF con los datos reales del item; NO se guarda.
  def vista_previa
    return render_item_ajeno unless item.garantia&.ticket_id == @ticket.id
    return render_formato_inactivo unless formato.activo
    return render_sin_plantilla if plantilla_activa.nil?

    salida = Helic3::Formatos::VistaPrevia.call(plantilla: plantilla_activa, item: item,
                                                user: Current.user, formato: :pdf,
                                                valores_producto: valores_producto)
    send_data salida[:bytes], type: salida[:tipo_mime], disposition: 'inline'
  end

  # POST: genera y deja el documento en el expediente (201 con el parcial de
  # documento, el mismo que usa la carga manual). Generar valida el caso y
  # levanta Error -> 422 si no esta listo (sin garantia, sin plantilla, item ajeno).
  def create
    @documento = Helic3::Formatos::Generar.call(ticket: @ticket, item: item, formato: formato,
                                                user: Current.user, valores_producto: valores_producto)
    render 'api/v1/accounts/helic3/documentos/create', formats: [:json], status: :created
  rescue Helic3::Formatos::Generar::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # FMT-07: lo que el operador escribio en el modal. Solo se aceptan las claves de
  # marcadores editables; cualquier otra se descarta aqui mismo (strong params).
  def valores_producto
    crudos = params[:valores_producto]
    return {} unless crudos.respond_to?(:permit)

    crudos.permit(*Helic3::Formatos::Marcadores.editables.keys).to_h
  end

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

  # cada item con los marcadores vacios (para el aviso) y los ultimos valores que
  # el operador escribio al generar ese mismo formato (para prellenar el modal).
  def items_con_vacios
    docs = formato_docs
    (@ticket.garantia&.items || []).map do |it|
      datos = Helic3::Formatos::DatosDelFormato.call(item: it, user: Current.user)
      { item: it,
        vacios: datos.select { |_clave, valor| valor.to_s.strip.empty? }.keys,
        ultimos: ultimos_valores(it, docs) }
    end
  end

  # todos los documentos de formato de la garantia, cargados una sola vez.
  def formato_docs
    @ticket.documentos.where(clase: 'formato', garantia_id: @ticket.garantia&.id).to_a
  end

  # por codigo de formato, los valores EDITABLES de la ultima generacion de ese
  # item: asi el modal arranca con lo de la ultima vez (4.3), no en blanco.
  def ultimos_valores(item, docs)
    editables = Helic3::Formatos::Marcadores.editables.keys
    docs.select { |d| d.metadata['item_id'].to_s == item.id.to_s }
        .group_by { |d| d.metadata['codigo_formato'] }
        .transform_values do |lista|
          ultimo = lista.max_by { |d| d.metadata['generacion'].to_i }
          (ultimo.metadata['valores'] || {}).slice(*editables)
        end
  end

  def render_sin_plantilla
    render json: { error: 'el formato no tiene una plantilla activa' }, status: :unprocessable_entity
  end

  def render_formato_inactivo
    render json: { error: 'el formato esta desactivado' }, status: :unprocessable_entity
  end

  def render_item_ajeno
    render json: { error: 'el item no pertenece a una garantia de este expediente' },
           status: :unprocessable_entity
  end
end
