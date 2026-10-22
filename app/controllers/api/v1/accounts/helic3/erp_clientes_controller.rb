# frozen_string_literal: true

# ERP-08: consulta de cliente por cedula contra el ERP (simulado o Siesa, segun el
# interruptor de ERP-04). Lo usa el wizard de "Nueva PQR manual" para llenar el paso 2.
# El ERP NUNCA bloquea la radicacion: si falla, el agente sigue a mano, por eso aqui
# los errores se traducen a un 503 claro y el frontend permite continuar.
class Api::V1::Accounts::Helic3::ErpClientesController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def show
    return erp_desactivado unless Helic3::Erp.habilitado?

    cedula = Helic3::Erp.normalizar_cedula(params[:cedula])
    return render(json: { error: 'cedula_invalida' }, status: :unprocessable_entity) if cedula.blank?

    cliente = Helic3::Erp.adapter.find_customer(cedula: cedula)
    if cliente
      render json: { encontrado: true, cliente: cliente_json(cliente) }
    else
      render json: { encontrado: false }
    end
  rescue Helic3::Erp::ConfiguracionInvalida
    erp_desactivado
  rescue Helic3::Erp::NoDisponible, StandardError => e
    # el ERP nunca debe dejar al agente sin poder seguir: cualquier fallo de la consulta
    # se reporta como no disponible (503), nunca como un 500 inesperado.
    Rails.logger.warn("[ERP-08] consulta de cliente fallo: #{e.class.name}") unless e.is_a?(Helic3::Erp::NoDisponible)
    render json: { error: 'erp_no_disponible' }, status: :service_unavailable
  end

  private

  # Misma puerta que radicar: un agente de la cuenta (TicketPolicy#create? es true).
  # No hay un modelo propio, asi que se autoriza explicitamente contra el ticket.
  def check_authorization
    authorize(Helic3::Ticket, :create?)
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
end
