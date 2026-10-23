# frozen_string_literal: true

# Remapea las PQR existentes de las 4 etapas viejas a las 3 del mockup, por cuenta:
#   Nueva        -> Nuevo        (+ inicial)
#   En análisis  -> En gestión
#   Respondida   -> Solucionado  (conserva detiene_reloj)
#   Cerrada      -> se funde en Solucionado (re-apunta sus tickets y se elimina)
#
# Renombra IN SITU (conserva el etapa_id de los tickets viejos). 'Cerrada' es la
# unica que no se renombra: se FUNDE en Solucionado (re-apunta sus tickets y se
# elimina). Asume el estado real de produccion: cuentas con las 4 etapas viejas y
# SIN las nuevas, por lo que el renombrado nunca colisiona con un codigo destino ya
# existente. Idempotente: una cuenta que ya tiene las 3 nuevas (sin viejas) no se
# toca. Si por un error de datos coexistieran viejas y nuevas, el renombrado
# abortaria por el indice unico (account_id, codigo): es un estado que no debe
# existir y se resuelve a mano, no en silencio.
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
    cuentas = modelo.where('btrim(lower(codigo)) IN (?)', RENOMBRES.keys + FUSIONES.keys)
                    .distinct.pluck(:account_id)
    cuentas.each { |cuenta_id| remapear_cuenta(cuenta_id) }
    # Blindaje (revision de Jhan en PR #141): el renombrado de arriba solo deja la
    # etapa inicial cuando la cuenta tenia 'nueva' intacta. Una cuenta que ya venia
    # con 'nuevo' (sin 'nueva') NO la toca el bloque anterior y quedaria sin ninguna
    # etapa inicial -> el 422 de radicacion sobreviviria al deploy. Por eso se cierran
    # las invariantes en TODAS las cuentas con etapas, no solo en las que tenian viejas.
    modelo.distinct.pluck(:account_id).each { |cuenta_id| garantizar_invariantes(cuenta_id) }
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
    RENOMBRES.each { |codigo_viejo, atributos| renombrar_o_fundir(cuenta_id, codigo_viejo, atributos) }
    FUSIONES.each { |codigo_viejo, codigo_destino| fundir_por_codigo(cuenta_id, codigo_viejo, codigo_destino) }
  end

  # Renombra la etapa vieja a sus atributos nuevos. Pero si el codigo destino YA existe en
  # la cuenta (coexisten 'nueva' y 'nuevo', p.ej. alguien creo 'nuevo' desde el admin),
  # renombrar chocaria con el indice unico (account_id, codigo) y tumbaria el deploy con
  # RecordNotUnique: en ese caso se FUNDE en el destino (revision de Jhan). Las banderas
  # las cierra garantizar_invariantes despues.
  def renombrar_o_fundir(cuenta_id, codigo_viejo, atributos)
    modelo = Helic3::Catalogo::EtapaPqr
    vieja = etapa_por_codigo(modelo, cuenta_id, codigo_viejo)
    return unless vieja

    destino = etapa_por_codigo(modelo, cuenta_id, atributos[:codigo])
    if destino && destino.id != vieja.id
      fundir(vieja, destino, cuenta_id)
    else
      vieja.update_columns(atributos)
    end
  end

  def fundir_por_codigo(cuenta_id, codigo_viejo, codigo_destino)
    modelo = Helic3::Catalogo::EtapaPqr
    vieja = etapa_por_codigo(modelo, cuenta_id, codigo_viejo)
    destino = etapa_por_codigo(modelo, cuenta_id, codigo_destino)
    return unless vieja && destino

    fundir(vieja, destino, cuenta_id)
  end

  # Re-apunta los tickets de la etapa vieja al destino y borra la vieja. Seguro porque
  # helic3_tickets es la unica tabla con FK hacia helic3_catalogo_etapas_pqr.
  def fundir(vieja, destino, cuenta_id)
    execute("UPDATE helic3_tickets SET etapa_id = #{destino.id} WHERE etapa_id = #{vieja.id}")
    say "FUNDE #{vieja.codigo} -> #{destino.codigo} (cuenta #{cuenta_id})"
    vieja.delete
  end

  # Busca por el codigo NORMALIZADO (btrim + lower): en produccion los codigos viejos
  # pueden traer espacios o mayusculas (asi entro el 'nueva ' que rompio la radicacion),
  # y el remapeo no debe depender de que ya esten limpios. Compara contra la clave ya
  # normalizada de RENOMBRES/FUSIONES.
  def etapa_por_codigo(modelo, cuenta_id, codigo)
    modelo.where(account_id: cuenta_id).where('btrim(lower(codigo)) = ?', codigo).first
  end

  # Invariantes que esta migracion PROMETE por cuenta: exactamente UNA etapa inicial
  # activa y exactamente UNA que detiene el reloj. El renombrado solo las garantiza
  # cuando la cuenta tenia las 4 viejas intactas; esto las asegura tambien cuando los
  # datos venian raros (ya migrados, etapas inactivas, o la bandera duplicada).
  def garantizar_invariantes(cuenta_id)
    asegurar_una(cuenta_id, :inicial, :asc)        # inicial = la primera (menor posicion)
    asegurar_una(cuenta_id, :detiene_reloj, :desc) # final   = la ultima (mayor posicion)
  end

  # Deja EXACTAMENTE una etapa activa con la bandera dada:
  # - si hay varias, conserva una (segun `orden` de posicion) y apaga el resto;
  # - si no hay ninguna, promueve una candidata: para `inicial`, la primera activa
  #   que NO detiene el reloj; para `detiene_reloj`, la ultima activa;
  # - si no hay ninguna etapa activa elegible, aborta nombrando la cuenta (no en silencio).
  def asegurar_una(cuenta_id, bandera, orden)
    modelo = Helic3::Catalogo::EtapaPqr
    cuenta = modelo.where(account_id: cuenta_id)
    activas = cuenta.where(activo: true)
    activas_marcadas = activas.where(bandera => true).order(posicion: orden).to_a

    # ya esta bien: exactamente UNA activa con la bandera y ninguna inactiva la lleva.
    # Lo segundo importa por el indice unico parcial de `inicial` (una sola fila con
    # inicial=true por cuenta): si la unica marcada quedo inactiva, hay que moverla.
    return if activas_marcadas.size == 1 && cuenta.where(:activo => false, bandera => true).none?

    # normalizar: apagar la bandera en TODAS (resuelve duplicados, el indice unico y las
    # inactivas que la llevaban) y encender UNA activa elegible. Para `inicial`, la primera
    # activa que no detiene el reloj; para `detiene_reloj`, la ultima activa.
    cuenta.where(bandera => true).update_all(bandera => false)
    candidata = if bandera == :inicial
                  activas.where(detiene_reloj: false).order(posicion: :asc).first
                else
                  activas.order(posicion: :desc).first
                end
    unless candidata
      raise "la cuenta #{cuenta_id} no tiene ninguna etapa activa para marcar #{bandera}: " \
            'siembra los catalogos antes de migrar'
    end
    candidata.update_columns(bandera => true)
  end
end
