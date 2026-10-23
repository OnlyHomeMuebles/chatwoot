# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Cargas::ImportarFacturas do
  let(:account) { create(:account) }
  let(:usuario) { create(:user, account: account) }

  def crear_carga(modo: 'anexar')
    Helic3::Carga.create!(account: account, tipo: 'facturas', modo: modo, usuario: usuario,
                          nombre_archivo: 'facturas.csv', estado: 'procesando')
  end

  def importar(contenido, modo: 'anexar')
    carga = crear_carga(modo: modo)
    carga.archivo.attach(io: StringIO.new(contenido), filename: 'facturas.csv', content_type: 'text/csv')

    described_class.call(carga: carga)
    carga.reload
  end

  it 'crea las facturas con las columnas confirmadas del Dash CX' do
    # separador ';' porque el valor trae coma decimal (formato colombiano):
    # con ',' como separador de columnas, la propia coma decimal partiria la fila.
    carga = importar(<<~CSV)
      Nro documento;Desc. C.O.;Fecha;Valor subtotal
      FV-001;Armenia;2026-09-01;1.234.567,89
    CSV

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

  it 'detecta un encabezado separado por tabulador' do
    carga = importar("Nro documento\tDesc. C.O.\tFecha\tValor subtotal\nFV-010\tCali\t2026-09-06\t500000\n")

    expect(carga.filas_insertadas).to eq(1)
  end

  # Bug real (verificado subiendo un archivo real por la pantalla): ActiveStorage
  # descarga el archivo en BINARY (ASCII-8BIT), no en UTF-8 como un string de Ruby
  # comun. Compararlo contra el literal UTF-8 del BOM revienta con
  # "incompatible character encodings" apenas el CSV trae una tilde o enie.
  it 'no revienta con tildes/enies aunque el archivo llegue en BINARY (como un upload real)' do
    contenido = "Nro documento;Desc. C.O.;Fecha;Valor subtotal\nFV-008;Bogotá;2026-09-04;100000\n"
                .dup.force_encoding('BINARY')
    carga = importar(contenido)

    expect(carga.filas_insertadas).to eq(1)
    expect(Helic3::FacturaVenta.sole.centro_operacion).to eq('Bogotá')
  end

  # Bug real: una factura redonda sin centavos llega como "1.200.000" (el punto
  # SIEMPRE es separador de miles en el formato colombiano, incluso sin coma
  # decimal) -- Float('1.200.000') revienta por tener mas de un punto.
  it 'parsea un valor redondo con puntos de miles y sin coma decimal' do
    carga = importar(<<~CSV)
      Nro documento;Desc. C.O.;Fecha;Valor subtotal
      FV-009;Cali;2026-09-05;1.200.000
    CSV

    expect(carga.filas_insertadas).to eq(1)
    expect(Helic3::FacturaVenta.sole.valor_subtotal).to eq(1_200_000)
  end

  it 'rechaza el archivo completo si falta una columna requerida, nombrandola' do
    carga = crear_carga
    carga.archivo.attach(io: StringIO.new("Nro documento,Desc. C.O.,Fecha\nFV-003,Cali,2026-09-01\n"),
                         filename: 'facturas.csv', content_type: 'text/csv')

    expect { described_class.call(carga: carga) }.to raise_error(described_class::ColumnasFaltantes, /Valor subtotal/)
    expect(carga.reload.estado).to eq('fallido')
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

    # Revision de Jhan: antes se hacia un find_by por fila contra la base; un
    # numero de documento repetido DENTRO del mismo archivo debe reconocerse
    # igual, sin que la segunda fila dispare otra consulta.
    it '"anexar": un numero de documento repetido dentro del MISMO archivo tambien se omite' do
      carga = importar(<<~CSV)
        Nro documento,Desc. C.O.,Fecha,Valor subtotal
        FV-011,Cali,2026-09-01,100000
        FV-011,Cali,2026-09-01,200000
      CSV

      expect(carga.filas_insertadas).to eq(1)
      expect(carga.filas_omitidas).to eq(1)
      expect(Helic3::FacturaVenta.count).to eq(1)
    end
  end

  it 'aisla por cuenta: el mismo numero de documento en otra cuenta no choca' do
    otra_cuenta = create(:account)
    otra_carga = Helic3::Carga.create!(account: otra_cuenta, tipo: 'facturas', modo: 'anexar',
                                       nombre_archivo: 'facturas.csv', estado: 'procesando')
    otra_carga.archivo.attach(
      io: StringIO.new("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-007,Cali,2026-09-01,100000\n"),
      filename: 'facturas.csv', content_type: 'text/csv'
    )
    described_class.call(carga: otra_carga)

    carga = importar("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-007,Cali,2026-09-01,200000\n")

    expect(carga.filas_insertadas).to eq(1)
    expect(Helic3::FacturaVenta.where(account: account).count).to eq(1)
  end

  describe '.verificar_columnas!' do
    def archivo_de(contenido)
      StringIO.new(contenido)
    end

    it 'no revienta y no deja rastro cuando las columnas estan completas' do
      archivo = archivo_de("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Cali,2026-09-01,100000\n")

      expect { described_class.verificar_columnas!(archivo) }.not_to raise_error
      expect(Helic3::Carga.count).to eq(0)
    end

    it 'rechaza antes de crear ninguna Carga si falta una columna' do
      archivo = archivo_de("Nro documento\nFV-001\n")

      expect { described_class.verificar_columnas!(archivo) }.to raise_error(described_class::ColumnasFaltantes)
      expect(Helic3::Carga.count).to eq(0)
    end

    # Revision de Jhan: Siesa no siempre manda el encabezado identico.
    it 'compara encabezados sin tildes ni mayusculas' do
      archivo = archivo_de("NRO DOCUMENTO,DESC. C.O.,FECHA,VALOR SUBTOTAL\nFV-001,Cali,2026-09-01,100000\n")

      expect { described_class.verificar_columnas!(archivo) }.not_to raise_error
    end

    it 'deja el archivo listo para volver a leerse desde el inicio (rewind)' do
      archivo = archivo_de("Nro documento,Desc. C.O.,Fecha,Valor subtotal\nFV-001,Cali,2026-09-01,100000\n")

      described_class.verificar_columnas!(archivo)

      expect(archivo.read).to start_with('Nro documento')
    end
  end
end
