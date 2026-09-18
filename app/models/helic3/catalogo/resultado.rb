# Con que se cierra el tramite. Sus marcas indican si el resultado cierra la
# PQR, si abre un expediente de garantia, y si exige aprobacion de una
# persona con autoridad (CAT-02, frente C): negar una garantia o aprobar un
# retracto que mueve dinero nunca lo decide el agente solo.
#
# requiere_admin (RES-01) responde una pregunta DISTINTA de aprobacion_humana:
# no "puede la IA sola?" sino "que humano puede FIRMARLO?". default true = solo
# admin, como hoy; Karen lo afloja por resultado desde ADM-01 sin desplegar. Lo
# consume Helic3::Catalogo::ResultadoPolicy#aplicar? (la puerta humana; el agente pasa por
# autonomia_resolver_pqr, no por aqui).
# == Schema Information
#
# Table name: helic3_catalogo_resultados
#
#  id                :bigint           not null, primary key
#  abre_garantia     :boolean          default(FALSE), not null
#  activo            :boolean          default(TRUE), not null
#  aprobacion_humana :boolean          default(FALSE), not null
#  cierra_pqr        :boolean          default(FALSE), not null
#  codigo            :string           not null
#  nombre            :string           not null
#  posicion          :integer          default(0), not null
#  requiere_admin    :boolean          default(TRUE), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#
# Indexes
#
#  idx_h3cat_resultados_account         (account_id)
#  idx_h3cat_resultados_account_codigo  (account_id,codigo) UNIQUE
#
class Helic3::Catalogo::Resultado < ApplicationRecord
  include Helic3::Catalogo::Comun
end
