# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Migracion::LectorDataGrid do
  # 22 columnas con tildes, como las descarga el CRM anterior. Las fechas vienen
  # "dd/mm/aaaa, h:mm" (con coma, entre comillas) y las observaciones con comas.
  subject(:resultado) { described_class.leer(csv) }

  let(:csv) do
    <<~CSV
      Consecutivo,Fecha de creación,Prioridad,Centros de operacion,Etapa del Caso,Proceso PQR,Motivo,Detalle Tipificado,Telefono de contacto,Fecha de Finalizacion,productos,Seguimiento u/o Observaciones,Identificación,Nombre del Cliente,Apellido del Cliente,Correo Electrónico,Direccion,Factura / Pedido / Orden de Compra,nro factura,Ciudad,Fecha Última Compra,Tipo Identificación
      100,"21/10/2026, 9:48",Media,OH CALI,En gestión,CAMBIO PRODUCTO,Devoluciones - Primera Entrega,Producto desajustado,3136141853 ,,MESA A,"Cliente pide cambio, urgente",30280717 ,Ana,Perez,ana@mail.com,Calle 1,DEJAR EN TIENDA,FVE-00000828,Cali,06/07/2026,Cedula de ciudadania
      100,"21/10/2026, 9:48",Media,OH CALI,En gestión,CAMBIO PRODUCTO,Devoluciones - Primera Entrega,Producto desajustado,3136141853 ,,SILLA B,"Cliente pide cambio, urgente",30280717 ,Ana,Perez,ana@mail.com,Calle 1,DEJAR EN TIENDA,FVE-00000828,Cali,06/07/2026,Cedula de ciudadania
      100,"21/10/2026, 9:48",Media,OH CALI,En gestión,CAMBIO PRODUCTO,Devoluciones - Primera Entrega,Producto desajustado,3136141853 ,,MESA A,"Cliente pide cambio, urgente",30280717 ,Ana,Perez,ana@mail.com,Calle 1,DEJAR EN TIENDA,FVE-00000828,Cali,06/07/2026,Cedula de ciudadania
      200,"15/08/2026, 10:00",Baja,OH BOGOTA,Solucionado,,Calidad - Producto Comprado,Producto roto,3001112233,19/08/2026,CAMA C,Caso resuelto,123456,Juan,Lopez,juan@mail.com,Calle 2,,FVE-00001111,Bogotá,01/06/2026,Cedula de ciudadania
      300,"01/01/2026, 8:00",,,En gestión,RECOLECCION,Calidad - Producto Comprado,Producto rayado,3000000000,,PRODUCTO X,PRUEBA CON LA DIRECTORA,999,Test,User,test@mail.com,Calle 3,,,Cali,,Cedula de ciudadania
      400,"10/09/2026, 11:00",Alta,--,En gestión,VISITA TECNICA,,Producto sucio,3002223344,30/9/2026,,Cliente molesto,555,Maria,Ruiz,maria@mail.com,Calle 4,,,Cali,15/08/2026,Cedula de ciudadania
    CSV
  end

  it 'valida que estén las 22 columnas' do
    expect(resultado[:columnas_ok]).to be(true)
  end

  it 'agrupa las filas por consecutivo y omite el duplicado exacto' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 100 }
    expect(caso[:productos].map { |p| p[:nombre] }).to contain_exactly('MESA A', 'SILLA B')
  end

  it 'une nombre y apellido y quita los espacios de la cédula' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 100 }
    expect(caso[:cliente_nombre]).to eq('Ana Perez')
    expect(caso[:cedula]).to eq('30280717')
  end

  it 'lee la fecha con coma (entre comillas) sin romper las columnas' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 100 }
    expect(caso[:fecha_creacion]).to eq('21/10/2026, 9:48')
    expect(caso[:tipo_identificacion]).to eq('Cedula de ciudadania')
  end

  it 'excluye los casos de prueba' do
    expect(resultado[:casos].map { |c| c[:consecutivo] }).not_to include(300)
    expect(resultado[:excluidos].map { |c| c[:consecutivo] }).to include(300)
  end

  it 'pone PQR FINALIZADA a un caso solucionado sin proceso' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 200 }
    expect(caso[:proceso]).to eq('PQR FINALIZADA')
    expect(caso[:ajustes]).to include(a_string_matching(/solucionado sin proceso/))
  end

  it 'rellena motivo vacío, quita la fecha de finalización en gestión y marca el producto vacío' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 400 }
    expect(caso[:motivo]).to eq('Calidad - Producto Comprado')
    expect(caso[:fecha_finalizacion]).to be_nil
    expect(caso[:productos].first[:nombre]).to eq('Producto no registrado en la migración')
    expect(caso[:ajustes].size).to eq(3)
  end

  it 'convierte -- en vacío (centro de operación)' do
    caso = resultado[:casos].find { |c| c[:consecutivo] == 400 }
    expect(caso[:centro_operacion]).to be_nil
  end

  it 'reporta las columnas faltantes si el CSV no tiene las 22' do
    sin_columna = csv.sub(',Ciudad,', ',')
    res = described_class.leer(sin_columna)
    expect(res[:columnas_ok]).to be(false)
    expect(res[:columnas_faltantes]).to include('ciudad')
  end

  describe 'casos puntuales de MIG-01' do
    let(:csv_puntuales) do
      <<~CSV
        Consecutivo,Fecha de creación,Prioridad,Centros de operacion,Etapa del Caso,Proceso PQR,Motivo,Detalle Tipificado,Telefono de contacto,Fecha de Finalizacion,productos,Seguimiento u/o Observaciones,Identificación,Nombre del Cliente,Apellido del Cliente,Correo Electrónico,Direccion,Factura / Pedido / Orden de Compra,nro factura,Ciudad,Fecha Última Compra,Tipo Identificación
        2927,"21/9/2026, 15:50",Media,OH CALI,En gestión,--,Devoluciones - Primera Entrega,Variación en el tono,3001112233,,,Caso,1,Ana,Perez,a@mail.com,Calle 1,,,Cali,,Cedula de ciudadania
        2976,"26/9/2026, 9:32",Media,OH CALI,En gestión,PQR FINALIZADA ,Calidad - Producto Comprado,Baja densidad de espuma,3001112233,,,Caso,2,Ana,Perez,a@mail.com,Calle 1,,,Cali,,Cedula de ciudadania
        3249,"28/10/2026, 12:40",Media,OH CALI,En gestión,--,Calidad - Producto Comprado,Chapilla levantada,3001112233,,,Caso,3,Ana,Perez,a@mail.com,Calle 1,,,Cali,,Cedula de ciudadania
      CSV
    end
    let(:casos) { described_class.leer(csv_puntuales)[:casos].index_by { |c| c[:consecutivo] } }

    it 'cierra el 2927 en Garantía Finalizada el 04/11/2026' do
      expect(casos[2927]).to include(etapa_caso: 'Solucionado', proceso: 'PQR FINALIZADA', fecha_finalizacion: '04/11/2026')
      expect(casos[2927][:ajustes]).to include(%r{corrección MIG-01: cerrada .* 04/11/2026})
    end

    it 'cierra el 2976 en Garantía Finalizada el 26/11/2026' do
      expect(casos[2976]).to include(etapa_caso: 'Solucionado', proceso: 'PQR FINALIZADA', fecha_finalizacion: '26/11/2026')
      expect(casos[2976][:ajustes]).to include(%r{corrección MIG-01: cerrada .* 26/11/2026})
    end

    it 'deja el 3249 abierto en Recolección' do
      expect(casos[3249]).to include(etapa_caso: 'En gestión', proceso: 'RECOLECCION')
      expect(casos[3249][:ajustes]).to include('corrección MIG-01: abierta en Recolección')
    end
  end
end
