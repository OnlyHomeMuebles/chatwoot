# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Cargas::ImportarFacturas do
  let(:account) { create(:account) }
  let(:usuario) { create(:user, account: account) }

  def csv(contenido)
    StringIO.new(contenido)
  end

  def importar(contenido, modo: 'anexar')
    described_class.call(account: account, archivo: csv(contenido), modo: modo, usuario: usuario,
                         nombre_archivo: 'facturas.csv')
  end

  it 'crea la carga y las facturas con las columnas confirmadas del Dash CX' do
    # separador ';' porque el valor trae coma decimal (formato colombiano):
    # con ',' como separador de columnas, la propia coma decimal partiria la fila.
    carga = importar(<<~CSV)
      Nro documento;Desc. C.O.;Fecha;Valor subtotal
      FV-001;Armenia;2026-09-01;1.234.567,89
    CSV

    expect(carga).to be_persisted
    expect(carga).to have_attributes(tipo: 'facturas', modo: 'anexar', estado: 'completado', usuario: usuario)
    expect(carga.filas_leidas).to eq(1)
    expect(carga.filas_insertadas).to eq(1)

    factura = Helic3::FacturaVenta.sole
    expect(factura).to have_attributes(
      numero_documento: 'FV-001', centro_operacion: 'Armenia', fecha: Date.new(2026, 9, 1)
    )
    expect(factura.valor_subtotal).to eq(1_234_567.89)
  end

  it 'detecta el separador ; cuando el CSV viene en ese formato' do
    carga = importar(<<~CSV)
      Nro documento;Desc. C.O.;Fecha;Valor subtotal
      FV-002;Manizales;2026-09-02;500000
    CSV

    expect(carga.filas_insertadas).to eq(1)
    expect(Helic3::FacturaVenta.sole.valor_subtotal).to eq(500_000)
  end

  it 'rechaza el archivo completo si falta una columna requerida, nombrandola' do
    expect do
      importar(<<~CSV)
        Nro documento,Desc. C.O.,Fecha
        FV-003,Cali,2026-09-01
      CSV
    end.to raise_error(described_class::ColumnasFaltantes, /Valor subtotal/)

    expect(Helic3::Carga.count).to eq(0)
  end

  it 'omite filas con fecha o valor ilegible y las lista con su numero de fila; el resto se carga' do
    carga = importar(<<~CSV)
      Nro documento,Desc. C.O.,Fecha,Valor subtotal
      FV-004,Cali,fecha-invalida,100000
      FV-005,Cali,2026-09-03,100000
    CSV

    expect(carga.filas_leidas).to eq(2)
    expect(carga.filas_insertadas).to eq(1)
    expect(carga.filas_omitidas).to eq(1)
    expect(carga.errores.first['fila']).to eq(2)
    expect(Helic3::FacturaVenta.pluck(:numero_documento)).to eq(['FV-005'])
  end

  describe 'modo de duplicados (criterio del Dash CX)' do
    let(:csv_inicial) { "Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-006,Cali,2026-09-01,100000\n" }
    let(:csv_repetido) { "Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-006,Cali,2026-09-01,200000\n" }

    it '"sobrescribir": el mismo numero de documento actualiza el valor' do
      importar(csv_inicial, modo: 'sobrescribir')
      carga = importar(csv_repetido, modo: 'sobrescribir')

      expect(carga.filas_actualizadas).to eq(1)
      expect(Helic3::FacturaVenta.sole.valor_subtotal).to eq(200_000)
    end

    it '"anexar": el mismo numero de documento se omite, no duplica ni actualiza' do
      importar(csv_inicial, modo: 'anexar')
      carga = importar(csv_repetido, modo: 'anexar')

      expect(carga.filas_omitidas).to eq(1)
      expect(Helic3::FacturaVenta.count).to eq(1)
      expect(Helic3::FacturaVenta.sole.valor_subtotal).to eq(100_000)
    end
  end

  it 'aisla por cuenta: el mismo numero de documento en otra cuenta no choca' do
    otra_cuenta = create(:account)
    described_class.call(
      account: otra_cuenta, archivo: csv("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-007,Cali,2026-09-01,100000\n"),
      modo: 'anexar', nombre_archivo: 'facturas.csv'
    )

    carga = importar("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-007,Cali,2026-09-01,200000\n")

    expect(carga.filas_insertadas).to eq(1)
    expect(Helic3::FacturaVenta.where(account: account).count).to eq(1)
  end
end
