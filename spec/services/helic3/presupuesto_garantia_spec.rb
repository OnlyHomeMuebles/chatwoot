# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::PresupuestoGarantia do
  # Parámetros inyectados (en producción vienen de la tabla de CAT-02). Ningún
  # número de negocio vive en el servicio.
  let(:parametros) { Helic3::ParametrosGarantia.new(total_dias: 30, umbral_verde: 10, umbral_amarillo: 3) }
  let(:calendario) { Helic3::CalendarioHabil.new }
  let(:inicio) { Date.new(2026, 1, 2) }
  # 23 días hábiles consumidos (como el ejemplo de Only Home: 8 de visita + 15 de recolección).
  let(:hoy) { calendario.sumar_dias_habiles(inicio, 23) }

  def presupuesto(plazo_etapa_vigente:)
    described_class.new(fecha_inicio: inicio, plazo_etapa_vigente: plazo_etapa_vigente,
                        parametros: parametros, calendario: calendario, hoy: hoy)
  end

  it 'se puede instanciar y probar solo, sin la entidad Ticket ni agentes' do
    expect { presupuesto(plazo_etapa_vigente: 5) }.not_to raise_error
  end

  describe 'consumidos y saldo' do
    it 'cuenta los días hábiles consumidos desde el inicio' do
      expect(presupuesto(plazo_etapa_vigente: 5).consumidos).to eq(23)
    end

    it 'calcula el saldo contra el presupuesto total' do
      expect(presupuesto(plazo_etapa_vigente: 5).saldo).to eq(7)
    end

    it 'deja el saldo negativo cuando la garantía se pasó del presupuesto (vencida)' do
      vencido = described_class.new(fecha_inicio: inicio, plazo_etapa_vigente: 5, parametros: parametros,
                                    calendario: calendario, hoy: calendario.sumar_dias_habiles(inicio, 35))
      expect(vencido.saldo).to eq(-5)
    end
  end

  describe '#fecha_etapa_vigente' do
    it 'topa el plazo de la etapa al saldo: 20 días de etapa pero 7 de saldo => promete a 7' do
      expect(presupuesto(plazo_etapa_vigente: 20).fecha_etapa_vigente).to eq(calendario.sumar_dias_habiles(hoy, 7))
    end

    it 'usa el plazo de la etapa cuando cabe dentro del saldo' do
      expect(presupuesto(plazo_etapa_vigente: 5).fecha_etapa_vigente).to eq(calendario.sumar_dias_habiles(hoy, 5))
    end
  end

  describe '#semaforo' do
    it 'se calcula contra el saldo total, con los umbrales de los parámetros' do
      verde = described_class.new(fecha_inicio: inicio, plazo_etapa_vigente: 5, parametros: parametros,
                                  calendario: calendario, hoy: calendario.sumar_dias_habiles(inicio, 5))
      expect(verde.semaforo).to eq(:verde)     # saldo 25 >= 10
      expect(presupuesto(plazo_etapa_vigente: 5).semaforo).to eq(:amarillo) # saldo 7 (entre 3 y 10)

      rojo = described_class.new(fecha_inicio: inicio, plazo_etapa_vigente: 5, parametros: parametros,
                                 calendario: calendario, hoy: calendario.sumar_dias_habiles(inicio, 28))
      expect(rojo.semaforo).to eq(:rojo)       # saldo 2 < 3
    end

    it 'depende de los parámetros inyectados, no de números fijos en el código' do
      estrictos = Helic3::ParametrosGarantia.new(total_dias: 30, umbral_verde: 8, umbral_amarillo: 5)
      caso = described_class.new(fecha_inicio: inicio, plazo_etapa_vigente: 5, parametros: estrictos,
                                 calendario: calendario, hoy: hoy)
      expect(caso.semaforo).to eq(:amarillo) # saldo 7: verde con umbral 10, amarillo con umbral 8
    end
  end

  describe '#estado' do
    it 'devuelve consumidos, saldo, fecha de la etapa vigente y semáforo' do
      expect(presupuesto(plazo_etapa_vigente: 20).estado).to eq(
        consumidos: 23,
        saldo: 7,
        fecha_etapa_vigente: calendario.sumar_dias_habiles(hoy, 7),
        semaforo: :amarillo
      )
    end
  end
end
