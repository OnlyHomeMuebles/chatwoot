# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::CalendarioHabil do
  subject(:calendario) { described_class.new }

  describe '#festivos' do
    it 'resuelve los 18 festivos de 2026 con los traslados de la Ley 51' do
      festivos = calendario.festivos(2026)

      expect(festivos.size).to eq(18)
      # Fijos
      expect(festivos).to include(Date.new(2026, 1, 1), Date.new(2026, 12, 25))
      # Ley 51: se corren al lunes siguiente
      expect(festivos).to include(Date.new(2026, 1, 12))  # Reyes (6-ene cae martes)
      expect(festivos).to include(Date.new(2026, 8, 17))  # Asunción (15-ago cae sábado)
      expect(festivos).to include(Date.new(2026, 11, 2))  # Todos los Santos (1-nov cae domingo)
      # Móviles por Pascua (Domingo de Resurrección 2026: 5-abr)
      expect(festivos).to include(Date.new(2026, 4, 2), Date.new(2026, 4, 3)) # Jueves y Viernes Santo
      expect(festivos).to include(Date.new(2026, 6, 15)) # Sagrado Corazón, trasladado al lunes
    end

    it 'resuelve los festivos de 2027, incluidos los traslados al lunes' do
      festivos = calendario.festivos(2027)

      expect(festivos.size).to eq(18)
      expect(festivos).to include(Date.new(2027, 1, 11)) # Reyes (6-ene cae miércoles)
      expect(festivos).to include(Date.new(2027, 3, 25), Date.new(2027, 3, 26)) # Semana Santa
      expect(festivos).to include(Date.new(2027, 10, 18)) # Día de la Raza, trasladado
    end

    it 'devuelve el calendario ordenado por fecha para poder auditarlo' do
      fechas = calendario.festivos(2026).keys

      expect(fechas).to eq(fechas.sort)
    end
  end

  describe '#es_habil?' do
    it 'no cuenta sábados ni domingos' do
      expect(calendario.es_habil?(Date.new(2026, 8, 8))).to be(false)  # sábado
      expect(calendario.es_habil?(Date.new(2026, 8, 9))).to be(false)  # domingo
    end

    it 'no cuenta los festivos' do
      expect(calendario.es_habil?(Date.new(2026, 1, 1))).to be(false)
    end

    it 'respeta el traslado de la Ley 51: el 6 de enero es hábil y el 12 es festivo' do
      expect(calendario.es_habil?(Date.new(2026, 1, 6))).to be(true)
      expect(calendario.es_habil?(Date.new(2026, 1, 12))).to be(false)
    end

    it 'cuenta un día laboral normal' do
      expect(calendario.es_habil?(Date.new(2026, 1, 2))).to be(true)
    end
  end

  describe '#sumar_dias_habiles' do
    it 'salta el Jueves y Viernes Santo al cruzar Semana Santa' do
      expect(calendario.sumar_dias_habiles(Date.new(2026, 3, 31), 5)).to eq(Date.new(2026, 4, 9))
    end

    it 'trata el 6 de enero como hábil y salta el festivo de Reyes trasladado al 12' do
      expect(calendario.sumar_dias_habiles(Date.new(2026, 1, 2), 6)).to eq(Date.new(2026, 1, 13))
    end

    it 'cruza el fin de año saltando Navidad y Año Nuevo, usando festivos de ambos años' do
      expect(calendario.sumar_dias_habiles(Date.new(2026, 12, 23), 7)).to eq(Date.new(2027, 1, 5))
    end

    it 'devuelve la misma fecha cuando la cantidad es cero' do
      expect(calendario.sumar_dias_habiles(Date.new(2026, 1, 2), 0)).to eq(Date.new(2026, 1, 2))
    end

    it 'no acepta cantidades negativas' do
      expect { calendario.sumar_dias_habiles(Date.new(2026, 1, 2), -1) }.to raise_error(ArgumentError)
    end
  end

  describe '#dias_habiles_entre' do
    it 'cuenta los días hábiles del intervalo excluyendo el inicio e incluyendo el fin' do
      expect(calendario.dias_habiles_entre(Date.new(2026, 3, 31), Date.new(2026, 4, 9))).to eq(5)
    end

    it 'es cero cuando la fecha final no es posterior a la inicial' do
      expect(calendario.dias_habiles_entre(Date.new(2026, 1, 5), Date.new(2026, 1, 5))).to eq(0)
    end
  end

  describe '.hoy' do
    it 'usa la zona horaria America/Bogota, no la del servidor' do
      # A las 02:00 UTC del 2-ene en Bogotá (UTC-5) todavía es 1-ene.
      travel_to(Time.utc(2026, 1, 2, 2, 0, 0)) do
        expect(described_class.hoy).to eq(Date.new(2026, 1, 1))
      end
    end
  end
end
