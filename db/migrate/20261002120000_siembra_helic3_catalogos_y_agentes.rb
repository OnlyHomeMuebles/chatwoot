# frozen_string_literal: true

# SIE-01: conecta la siembra de catalogos, parametros y agentes de Helic3 al
# camino de produccion. En produccion la base ya existe, asi que start.sh solo
# corre migraciones (db:chatwoot_prepare no re-ejecuta db:seed): por eso la
# siembra vive en una migracion y no en un rake de consola.
#
# Reutiliza los seeders, que YA son idempotentes por llave natural (catalogos y
# agentes por (account, codigo); parametros por (account, clave)): llamarlos de
# nuevo no duplica ni pisa ediciones hechas desde el panel. Los casos previsibles
# que tumbarian el arranque (tabla aun inexistente, agente de sistema con otro
# codigo) los cubren guardas dentro de los propios seeders. Un error NO previsto
# debe parar el despliegue y verse: por eso no se atrapan excepciones.
class SiembraHelic3CatalogosYAgentes < ActiveRecord::Migration[7.2]
  MODELOS = %w[
    Helic3::Catalogo::Categoria Helic3::Catalogo::Tipo Helic3::Catalogo::EtapaPqr
    Helic3::Catalogo::MotivoPqr Helic3::Catalogo::Resultado Helic3::Catalogo::MotivoGarantia
    Helic3::Catalogo::DetalleTipificado Helic3::Catalogo::ProcesoGarantia
    Helic3::Catalogo::CoberturaCiudad Helic3::Catalogo::Parametro Helic3::Agente
  ].freeze

  def up
    # una migracion anterior del MISMO despliegue pudo agregar columnas; se limpia
    # el cache de columnas del modelo para que las filas se creen con el esquema
    # real y no con el cacheado al cargar la clase.
    MODELOS.each { |nombre| nombre.constantize.reset_column_information }

    Account.find_each do |cuenta|
      # catalogos primero: siembran el parametro agentes_desde_bd=false antes de
      # que existan los agentes (sembrar agentes no cambia el comportamiento del bot).
      resumen_cat = Helic3::Catalogo::SeederService.new(cuenta).sembrar!
      resumen_ag = Helic3::Agents::SeederService.new(cuenta).sembrar!

      # el resumen por cuenta queda en el log del despliegue: evidencia de que corrio.
      say "Cuenta #{cuenta.id} (#{cuenta.name})"
      resumen_cat.each { |catalogo, total| say("#{catalogo}: #{total}", true) }
      resumen_ag.each { |clave, total| say("#{clave}: #{total}", true) }
    end
  end

  def down
    # No-op a proposito: las filas sembradas pueden estar referenciadas por
    # expedientes y pudieron editarse desde el panel. Revertir borraria datos
    # reales, asi que db:rollback no toca nada (criterio de aceptacion 9).
    say 'SIE-01 no revierte la siembra: las filas pueden estar en uso y editadas.'
  end
end
