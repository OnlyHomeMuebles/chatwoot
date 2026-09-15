# Administracion de catalogos (ADM-01): CRUD de los catalogos que Karen edita,
# para que cambie el vocabulario y el comportamiento del modulo sin consola y sin
# desplegar. Lectura para agentes; escritura solo para administradores.
#
# Reglas del contrato:
# - Desactivar, no borrar: una fila referenciada por un expediente no se borra, se
#   desactiva (activo: false) y deja de ofrecerse sin romper el historial.
# - El codigo es la llave con la que el agente y el codigo resuelven las filas:
#   se fija al crear y NO se edita despues.
class Api::V1::Accounts::Helic3::Admin::CatalogosController < Api::V1::Accounts::BaseController
  # tipo (segmento de ruta) -> modelo y campos editables de ese catalogo.
  # Agrupados por dominio (ADM-02), como los presenta el menu lateral: PQR
  # primero, Garantia despues.
  CATALOGOS = {
    'categorias' => {
      modelo: Helic3::Catalogo::Categoria,
      campos: %i[nombre codigo activo posicion genera_radicado]
    },
    'tipos' => {
      modelo: Helic3::Catalogo::Tipo,
      campos: %i[nombre codigo activo posicion plazo_dias_habiles]
    },
    'motivos_pqr' => {
      modelo: Helic3::Catalogo::MotivoPqr,
      campos: %i[nombre codigo activo posicion categoria_id abre_garantia plazo_dias_habiles]
    },
    'resultados' => {
      modelo: Helic3::Catalogo::Resultado,
      campos: %i[nombre codigo activo posicion abre_garantia aprobacion_humana cierra_pqr requiere_admin]
    },
    'etapas_pqr' => {
      modelo: Helic3::Catalogo::EtapaPqr,
      campos: %i[nombre codigo activo posicion detiene_reloj visible_cliente]
    },
    'detalles_tipificados' => {
      modelo: Helic3::Catalogo::DetalleTipificado,
      campos: %i[nombre codigo activo posicion motivo_garantia_id]
    },
    'motivos_garantia' => {
      modelo: Helic3::Catalogo::MotivoGarantia,
      campos: %i[nombre codigo activo posicion regla parametro_dias]
    },
    'procesos_garantia' => {
      modelo: Helic3::Catalogo::ProcesoGarantia,
      campos: %i[nombre codigo activo posicion es_terminal plazo_dias_habiles]
    },
    'coberturas_ciudad' => {
      modelo: Helic3::Catalogo::CoberturaCiudad,
      campos: %i[nombre codigo activo posicion origen_ruta tecnico_propio]
    }
  }.freeze

  before_action :set_catalogo
  # Escritura solo administradores: check_admin_authorization? (de Api::BaseController)
  # levanta Pundit::NotAuthorizedError y la app responde 401. Lectura queda abierta
  # a los agentes.
  before_action :check_admin_authorization?, only: [:create, :update, :destroy]
  before_action :set_registro, only: [:update, :destroy]

  def index
    @registros = @modelo.where(account: Current.account).order(:posicion)
  end

  # Se descarta el string vacio (un enum sin elegir, una ruta sin texto) para que
  # la columna use su default o quede NULL en vez de castear "" -> nil sobre una
  # columna NOT NULL (que reventaria con 500). A diferencia de compact_blank,
  # esto SI conserva un booleano en false explicito: genera_radicado y
  # requiere_admin arrancan en true por columna, y apagarlos al crear se debe
  # respetar, no perderse silenciosamente por ser "blank".
  def create
    @registro = @modelo.create!(catalogo_params.reject { |_, v| v == '' }.merge(account: Current.account))
    render :show, status: :created
  end

  # El codigo es inmutable: se descarta si el cliente lo manda.
  def update
    @registro.update!(catalogo_params.except(:codigo))
    render :show
  end

  # Borra si nadie la referencia; si esta en uso, la FK lo impide y se responde
  # 422 pidiendo que se desactive en vez de borrar.
  def destroy
    @registro.destroy!
    head :ok
  rescue ActiveRecord::InvalidForeignKey
    render json: { error: I18n.t('helic3.catalogos.referenciado') }, status: :unprocessable_entity
  end

  private

  def set_catalogo
    entrada = CATALOGOS[params[:tipo]]
    return render_could_not_find unless entrada

    @modelo = entrada[:modelo]
    @campos = entrada[:campos]
  end

  def set_registro
    @registro = @modelo.find_by!(account: Current.account, id: params[:id])
  end

  def render_could_not_find
    render json: { error: I18n.t('helic3.catalogos.tipo_desconocido') }, status: :not_found
  end

  def catalogo_params
    params.require(:catalogo).permit(*@campos)
  end
end
