# frozen_string_literal: true

# ERP-14: cache por cuenta+cedula del resultado del ERP (cliente + compras), serializado
# a jsonb. Una fila por cuenta+cedula; NO guarda el payload crudo de Siesa.
class Helic3::ErpConsulta < ApplicationRecord
  # El inflector no pluraliza "consulta"; se fija la tabla a mano.
  self.table_name = 'helic3_erp_consultas'

  belongs_to :account
end
