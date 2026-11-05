# frozen_string_literal: true

# Normaliza codigos y nombres de los catalogos Helic3 que se cargaron con espacios
# o fuera del formato slug (p. ej. la etapa "nueva " con espacio final, que hacia
# que Radicar#etapa_inicial -> find_by!(codigo: 'nueva') fallara con 404 y ninguna
# PQR nueva se pudiera crear en produccion).
#
# Es una migracion de DATOS (no cambia estructura):
# - Quita espacios y pasa el codigo a slug (minusculas, numeros, guion bajo).
# - Si el codigo limpio chocaria con otra fila de la misma cuenta (duplicado), NO
#   lo toca: lo REPORTA para fusionarlo a mano revisando sus referencias (tickets,
#   ficha, garantia_items), porque fusionar sin revisar perderia datos.
class NormalizaCodigosHelic3Catalogos < ActiveRecord::Migration[7.2]
  MODELOS = %w[
    Categoria Tipo EtapaPqr MotivoPqr Resultado
    MotivoGarantia DetalleTipificado ProcesoGarantia CoberturaCiudad Formato
  ].freeze

  def up
    MODELOS.each do |nombre_modelo|
      modelo = "Helic3::Catalogo::#{nombre_modelo}".constantize
      modelo.reset_column_information

      modelo.find_each do |fila|
        codigo_limpio = fila.codigo.to_s.strip.parameterize(separator: '_')
        nombre_limpio = fila.nombre.to_s.strip
        next if codigo_limpio == fila.codigo && nombre_limpio == fila.nombre

        choca = codigo_limpio != fila.codigo &&
                modelo.where(account_id: fila.account_id, codigo: codigo_limpio)
                      .where.not(id: fila.id).exists?

        if choca
          say "DUPLICADO #{nombre_modelo} id=#{fila.id}: " \
              "'#{fila.codigo}' -> '#{codigo_limpio}' ya existe. " \
              'Fusionar a mano revisando referencias; aqui solo se limpia el nombre.'
          fila.update_columns(nombre: nombre_limpio) if nombre_limpio != fila.nombre
        else
          # update_columns: salta validaciones/normalizes (ya normalizamos aqui) y
          # no dispara callbacks; es lo correcto para una migracion de datos.
          fila.update_columns(codigo: codigo_limpio, nombre: nombre_limpio)
        end
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          'No se puede reconstruir el espacio o la mayuscula original de un codigo.'
  end
end
