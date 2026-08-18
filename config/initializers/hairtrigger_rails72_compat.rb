# frozen_string_literal: true

# Compatibilidad: hairtrigger 1.0.0 llama `connection.schema_migration`, un método que Rails 7.2
# eliminó del adaptador (ahora vive en el pool de conexiones). Sin esto, `db:schema:dump` (y por
# ende `db:migrate` en desarrollo y la preparación del esquema de test) revienta con
# NoMethodError. Restauramos la API delegando al pool.
ActiveSupport.on_load(:active_record) do
  adapter = ActiveRecord::ConnectionAdapters::AbstractAdapter
  # Métodos que Rails 7.2 movió del adaptador al pool de conexiones y que hairtrigger 1.0.0 aún
  # invoca sobre la conexión. Se delegan al pool para restaurar la API que el gem espera.
  %i[schema_migration internal_metadata migration_context db_config with_connection].each do |meth|
    adapter.define_method(meth) { |*args, **kwargs, &block| pool.public_send(meth, *args, **kwargs, &block) } unless adapter.method_defined?(meth)
  end
end
