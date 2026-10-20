# frozen_string_literal: true

# FMT-02: catalogo de los formatos de garantia de Karen (visita tecnica, recoleccion,
# etc.). Un formato tiene muchas versiones de plantilla (helic3_plantillas_formato);
# solo una queda activa. Comparte columnas y validaciones con los demas catalogos via
# Helic3::Catalogo::Comun (cuenta, codigo, nombre, posicion, activo).
class Helic3::Catalogo::Formato < ApplicationRecord
  # inflector latino: sin esto Rails buscaria "helic3_catalogo_formatoes".
  self.table_name = 'helic3_catalogo_formatos'

  include Helic3::Catalogo::Comun

  # restrict_with_error: no se borra un formato que tenga plantillas (las referencian PDFs).
  # La FK formato_id la infiere Rails del nombre de esta clase.
  has_many :plantillas, class_name: 'Helic3::PlantillaFormato',
                        inverse_of: :formato, dependent: :restrict_with_error
end
