class Api::V1::Accounts::Helic3::CatalogosController < Api::V1::Accounts::BaseController
  # Catalogos de clasificacion de solo lectura para poblar los selectores del
  # panel (API-01). Un unico GET devuelve los catalogos, cada uno acotado a la
  # cuenta actual y solo con las filas activas, en su orden de posicion. Las tres
  # ultimas listas (ciudad, motivo y detalle de garantia) las agrega GAR-05: son
  # las que alimenta el formulario de apertura de garantia, en la misma peticion.
  def show
    @tipos = Helic3::Catalogo::Tipo.where(account: Current.account).activos
    @motivos_pqr = Helic3::Catalogo::MotivoPqr.where(account: Current.account).activos.includes(:categoria)
    @etapas_pqr = Helic3::Catalogo::EtapaPqr.where(account: Current.account).activos
    @resultados = Helic3::Catalogo::Resultado.where(account: Current.account).activos
    @coberturas_ciudad = Helic3::Catalogo::CoberturaCiudad.where(account: Current.account).activos
    @motivos_garantia = Helic3::Catalogo::MotivoGarantia.where(account: Current.account).activos
    @detalles_tipificados = Helic3::Catalogo::DetalleTipificado.where(account: Current.account).activos
  end
end
