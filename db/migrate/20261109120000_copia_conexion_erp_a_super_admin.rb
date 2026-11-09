# frozen_string_literal: true

# ERP-16: copia a Super Admin (installation_configs) el modo y la conexion de Siesa que
# hasta ahora se leian de variables de entorno, para que la pagina "Helic3 · ERP Siesa"
# nazca llena. Corre sola en el deploy. Idempotente: por cada clave, solo escribe si la
# fila no existe o esta vacia y la variable tiene valor; nunca pisa lo ya guardado. Si el
# entorno no tiene nada, no crea filas y el modo queda en desactivado.
# Nombres fijos a proposito: una migracion no depende de codigo de la app (mismo patron que
# 20261003120000_copia_llave_openai_a_super_admin).
class CopiaConexionErpASuperAdmin < ActiveRecord::Migration[7.2]
  # clave en installation_configs => variable de entorno que reemplaza
  CLAVES = {
    'HELIC3_ERP_MODO' => 'HELIC3_ERP_MODO',
    'HELIC3_SIESA_HUB_BASE_URL' => 'SIESA_HUB_BASE_URL',
    'HELIC3_SIESA_HUB_CLIENT_ID' => 'SIESA_HUB_CLIENT_ID',
    'HELIC3_SIESA_HUB_CONNI_KEY' => 'SIESA_HUB_CONNI_KEY',
    'HELIC3_SIESA_HUB_CONNI_TOKEN' => 'SIESA_HUB_CONNI_TOKEN',
    'HELIC3_SIESA_HUB_ID_COMPANIA' => 'SIESA_HUB_ID_COMPANIA',
    'HELIC3_SIESA_HUB_CONSULTA_CLIENTES' => 'SIESA_HUB_CONSULTA_CLIENTES',
    'HELIC3_SIESA_HUB_CONSULTA_COMPRAS' => 'SIESA_HUB_CONSULTA_COMPRAS'
  }.freeze

  def up
    CLAVES.each do |clave, variable|
      valor = ENV[variable].to_s.strip
      next if valor.empty?

      registro = InstallationConfig.find_or_initialize_by(name: clave)
      next if registro.value.present?

      registro.value = valor
      registro.locked = false
      registro.save!
    end
  end

  def down; end
end
