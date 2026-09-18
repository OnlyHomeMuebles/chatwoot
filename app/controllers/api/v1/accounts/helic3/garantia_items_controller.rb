class Api::V1::Accounts::Helic3::GarantiaItemsController < Api::V1::Accounts::BaseController
  before_action :fetch_item
  before_action :check_authorization

  # PATCH /api/v1/accounts/:account_id/helic3/garantias/:garantia_id/items/:id
  #
  # Avanza un producto de proceso (GAR-03). Delega en Helic3::Casos::AvanzarGarantia:
  # aqui solo se traduce (ids -> objetos de la cuenta) y se responde el expediente
  # con su garantia refrescada, para que el panel actualice proceso y barra.
  def update
    Helic3::Casos::AvanzarGarantia.new(item: @item, proceso: proceso_de_cuenta,
                                       decision: params[:decision]).call
    @ticket = @item.garantia.ticket
    render 'api/v1/accounts/helic3/tickets/show', formats: [:json]
  end

  private

  # garantia e item acotados a la cuenta: una garantia o un item de otra cuenta
  # no existen aqui (404), igual que el resultado en resoluciones.
  def fetch_item
    garantia = Helic3::Garantia.find_by!(account: Current.account, id: params[:garantia_id])
    @item = garantia.items.find(params[:id])
  end

  # avanzar el producto es un acto operativo (no el resultado legal de la PQR):
  # lo puede hacer quien participa del expediente, como cualquier edicion.
  def check_authorization
    authorize(@item.garantia.ticket, :update?)
  end

  # un proceso de otra cuenta no existe aqui: RecordNotFound (404).
  def proceso_de_cuenta
    Helic3::Catalogo::ProcesoGarantia.find_by!(account: Current.account, id: params.require(:proceso_id))
  end
end
