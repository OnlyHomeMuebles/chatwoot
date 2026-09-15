# RES-01 (respuesta de Jhan, 10-sep): "quien puede FIRMAR cada resultado" es un
# valor de negocio, no codigo. Sale del policy y entra al catalogo.
#   default: true  -> comportamiento identico al de hoy (solo admin): riesgo cero
#                     al desplegar. Karen lo afloja por resultado desde ADM-01,
#                     sin volver a desplegar.
# NO reusa aprobacion_humana: esa pregunta si la IA puede sola; esta, que humano
# lo firma. Solo toca helic3_catalogo_resultados (tabla propia); nada upstream.
class AgregaRequiereAdminAHelic3CatalogoResultados < ActiveRecord::Migration[7.2]
  def change
    add_column :helic3_catalogo_resultados, :requiere_admin, :boolean, default: true, null: false
  end
end
