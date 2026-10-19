# frozen_string_literal: true

# Remapea las PQR existentes de las 4 etapas viejas a las 3 del mockup, por cuenta:
#   Nueva        -> Nuevo        (+ inicial)
#   En análisis  -> En gestión
#   Respondida   -> Solucionado  (conserva detiene_reloj)
#   Cerrada      -> se funde en Solucionado (re-apunta sus tickets y se elimina)
#
# Renombra IN SITU (conserva el etapa_id de los tickets viejos). Si el codigo
# destino ya existe en la cuenta (cuenta mixta), en vez de renombrar FUNDE:
# re-apunta los tickets de la vieja a la superviviente y elimina la vieja, para no
# chocar con el indice unico (account_id, codigo). Idempotente: una cuenta que ya
# tiene las 3 nuevas no se toca.
#
# Invariantes que deja garantizados por cuenta: exactamente UNA etapa inicial
# (Nuevo) y exactamente UNA que detiene el reloj (Solucionado).
#
# Irreversible: no se puede reconstruir el nombre/estado original de una etapa
# fundida ni des-fundir los tickets.
class RemapeaEtapasPqrATresHelic3 < ActiveRecord::Migration[7.2]
  # vieja => atributos nuevos (renombrado in situ). El orden importa: 'cerrada' se
  # procesa como fusion aparte (abajo), no aqui.
  RENOMBRES = {
    'nueva' => { codigo: 'nuevo', nombre: 'Nuevo', inicial: true },
    'en_analisis' => { codigo: 'en_gestion', nombre: 'En gestión' },
    'respondida' => { codigo: 'solucionado', nombre: 'Solucionado' }
  }.freeze

  # vieja => codigo destino con el que se funde (re-apuntar tickets + eliminar).
  # 'cerrada' no existe en el flujo nuevo; sus tickets pasan a Solucionado.
  FUSIONES = { 'cerrada' => 'solucionado' }.freeze

  def up
    modelo = Helic3::Catalogo::EtapaPqr
    modelo.reset_column_information
    # por cuenta: el indice unico es (account_id, codigo), asi que se remapea
    # cuenta por cuenta. Solo las cuentas que todavia tienen alguna etapa vieja.
    cuentas = modelo.where(codigo: RENOMBRES.keys + FUSIONES.keys).distinct.pluck(:account_id)
    cuentas.each { |cuenta_id| remapear_cuenta(cuenta_id) }
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'No se puede reconstruir una etapa fundida ni el nombre original.'
  end

  private

  # Renombres PRIMERO (respondida -> solucionado), para que exista el destino de
  # las fusiones. Fusiones DESPUES (cerrada -> solucionado): re-apunta los tickets
  # y elimina la etapa vieja.
  def remapear_cuenta(cuenta_id)
    modelo = Helic3::Catalogo::EtapaPqr
    RENOMBRES.each do |codigo_viejo, atributos|
      modelo.find_by(account_id: cuenta_id, codigo: codigo_viejo)&.update_columns(atributos)
    end
    FUSIONES.each do |codigo_viejo, codigo_destino|
      vieja = modelo.find_by(account_id: cuenta_id, codigo: codigo_viejo)
      destino = modelo.find_by(account_id: cuenta_id, codigo: codigo_destino)
      next unless vieja && destino

      execute("UPDATE helic3_tickets SET etapa_id = #{destino.id} WHERE etapa_id = #{vieja.id}")
      say "FUNDE #{codigo_viejo} -> #{codigo_destino} (cuenta #{cuenta_id})"
      vieja.delete
    end
  end
end
