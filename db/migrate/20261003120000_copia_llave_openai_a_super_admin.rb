# frozen_string_literal: true

# CFG-01: copia a Super Admin (installation_configs) la llave de OpenAI que hoy
# usa el programa, para que la pantalla nazca llena. Corre sola en el deploy.
# Idempotente: solo escribe si la clave no existe o esta vacia; nunca pisa.
# Nombres fijos a proposito: una migracion no depende de codigo de la app.
class CopiaLlaveOpenaiASuperAdmin < ActiveRecord::Migration[7.2]
  CLAVE = 'HELIC3_OPENAI_API_KEY'

  def up
    registro = InstallationConfig.find_or_initialize_by(name: CLAVE)
    return if registro.value.present?

    valor = ENV['OPENAI_API_KEY'].presence ||
            InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')
                              &.value.presence
    return if valor.blank?

    registro.value = valor
    registro.locked = false
    registro.save!
  end

  def down; end
end
