# frozen_string_literal: true

# ERP-08: consulta de cliente por cedula contra el ERP (simulado o Siesa, segun el
# interruptor de ERP-04). Lo usa el wizard de "Nueva PQR manual" para llenar el paso 2.
# El ERP NUNCA bloquea la radicacion: si falla, el agente sigue a mano, por eso aqui
# los errores se traducen a un 503 claro y el frontend permite continuar.
class Api::V1::Accounts::Helic3::ErpClientesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  # ERP-08/15: en UNA sola consulta devuelve el cliente y sus facturas+productos (el wizard
  # hace una peticion, no dos). El ERP NUNCA bloquea: si falla, 503 y el agente sigue a mano.
  # Una cedula sin cliente/compras no es error (encontrado:false, facturas:[]).
  def show
    return erp_desactivado unless Helic3::Erp.habilitado?

    cedula = Helic3::Erp.normalizar_cedula(params[:cedula])
    return render(json: { error: 'cedula_invalida' }, status: :unprocessable_entity) if cedula.blank?

    resultado = Helic3::Erp::Cache.consultar(account: Current.account, cedula: cedula, refrescar: refrescar?)
    render json: {
      encontrado: resultado.cliente.present?,
      cliente: resultado.cliente && cliente_json(resultado.cliente),
      facturas: resultado.compras.map { |factura| factura_json(factura) }
    }
  rescue Helic3::Erp::ConfiguracionInvalida
    erp_desactivado
  rescue Helic3::Erp::NoDisponible, StandardError => e
    # el ERP nunca debe dejar al agente sin poder seguir: cualquier fallo de la consulta
    # se reporta como no disponible (503), nunca como un 500 inesperado.
    Rails.logger.warn("[ERP-08] consulta fallo: #{e.class.name}") unless e.is_a?(Helic3::Erp::NoDisponible)
    render json: { error: 'erp_no_disponible' }, status: :service_unavailable
  end

  private

  # Misma puerta que radicar: un agente de la cuenta (TicketPolicy#create? es true).
  # No hay un modelo propio, asi que se autoriza explicitamente contra el ticket.
  def check_authorization
    authorize(Helic3::Ticket, :create?)
  end

  # ERP-14: "Volver a consultar" (?refrescar=1) salta el cache y vuelve a llamar a Siesa.
  def refrescar?
    params[:refrescar] == '1'
  end

  def cliente_json(cliente)
    {
      cedula: cliente.cedula, nombre: cliente.nombre, telefono: cliente.telefono,
      email: cliente.email, ciudad: cliente.ciudad, direccion: cliente.direccion
    }
  end

  def erp_desactivado
    render json: { error: 'erp_desactivado' }, status: :service_unavailable
  end

  def factura_json(factura)
    {
      numero: factura.numero, fecha: factura.fecha, total: factura.total,
      saldo: factura.saldo, estado: factura.estado, centro_operacion: factura.centro_operacion,
      items: factura.items.map { |item| item_json(item) }
    }
  end

  def item_json(item)
    { referencia: item.referencia, descripcion: item.descripcion, cantidad: item.cantidad, valor: item.valor }
  end
end
