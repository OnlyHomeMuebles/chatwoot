# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::ParametrosGarantia do
  let(:account) { create(:account) }

  def sembrar(clave, valor)
    Helic3::Catalogo::Parametro.create!(account: account, clave: clave, valor: valor.to_s,
                                        unidad: 'dias_habiles')
  end

  describe '.desde_catalogo' do
    it 'con ambito garantia lee su propio juego de claves' do
      sembrar('plazo_total_garantia', 30)
      sembrar('umbral_verde_garantia', 15)
      sembrar('umbral_amarillo_garantia', 5)

      parametros = described_class.desde_catalogo(account, ambito: :garantia)

      expect(parametros.to_h).to eq(total_dias: 30, umbral_verde: 15, umbral_amarillo: 5)
    end

    it 'con ambito pqr lee el otro juego: dos relojes, dos escalas' do
      sembrar('plazo_respuesta_pqr', 15)
      sembrar('umbral_verde_pqr', 8)
      sembrar('umbral_amarillo_pqr', 3)

      parametros = described_class.desde_catalogo(account, ambito: :pqr)

      expect(parametros.to_h).to eq(total_dias: 15, umbral_verde: 8, umbral_amarillo: 3)
    end

    it 'si falta un parametro, el error nombra la clave exacta y la cuenta' do
      sembrar('plazo_respuesta_pqr', 15)
      sembrar('umbral_amarillo_pqr', 3)

      expect { described_class.desde_catalogo(account, ambito: :pqr) }
        .to raise_error(described_class::ParametroFaltante, /umbral_verde_pqr.*#{account.id}/)
    end

    it 'un ambito desconocido revienta con los validos en el mensaje' do
      expect { described_class.desde_catalogo(account, ambito: :inventado) }
        .to raise_error(ArgumentError, /garantia, pqr/)
    end

    it 'devuelve un Struct que PresupuestoGarantia acepta sin cambios' do
      sembrar('plazo_total_garantia', 30)
      sembrar('umbral_verde_garantia', 15)
      sembrar('umbral_amarillo_garantia', 5)
      parametros = described_class.desde_catalogo(account, ambito: :garantia)

      presupuesto = Helic3::PresupuestoGarantia.new(
        fecha_inicio: Helic3::CalendarioHabil.hoy,
        plazo_etapa_vigente: 8,
        parametros: parametros
      )

      expect(presupuesto.estado).to include(:consumidos, :saldo, :fecha_etapa_vigente, :semaforo)
      expect(presupuesto.semaforo).to eq(:verde)
    end
  end
end
