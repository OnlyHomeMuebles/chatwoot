# frozen_string_literal: true

# Juegos de datos simulados del ERP (ERP-02): representan los casos reales que la operación
# encontrará, usando los objetos de valor del contrato (ERP-01). El adaptador simulado (ERP-03)
# consulta estos datos, para desarrollar sin el API de Siesa.
#
# Casos cubiertos:
#   - Cliente al día (todas sus facturas pagadas)
#   - Cliente con una factura pendiente
#   - Cliente en mora (factura vencida)
#   - Cliente con mezcla (pagada + pendiente + vencida)
#   - Cliente inexistente: lo maneja el adaptador devolviendo nil (cédula fuera de este conjunto)
module Helic3::Erp::SimulatedData
  module_function

  # cédula => Customer
  def customers
    {
      # Armenia: ciudad con visita técnica (cobertura directa de Only Home).
      '1032456789' => Helic3::Erp::Customer.new(cedula: '1032456789', nombre: 'Ana Ruiz',
                                                email: 'ana.ruiz@correo.com', telefono: '3001112233',
                                                ciudad: 'Armenia', direccion: 'Cra 14 # 10-25, Barrio Centro'),
      # Bogotá: fuera de la cobertura con técnico propio (la garantía va por recolección).
      '79856231' => Helic3::Erp::Customer.new(cedula: '79856231', nombre: 'Carlos Díaz',
                                              email: 'carlos.diaz@correo.com', telefono: '3014445566',
                                              ciudad: 'Bogotá', direccion: 'Calle 100 # 15-30, Chicó'),
      # Pereira: ciudad con visita técnica.
      '52998877' => Helic3::Erp::Customer.new(cedula: '52998877', nombre: 'Laura Gómez',
                                              email: 'laura.gomez@correo.com', telefono: '3027778899',
                                              ciudad: 'Pereira', direccion: 'Av Circunvalar # 8-40'),
      # Medellín: fuera de la cobertura con técnico propio.
      '1098765432' => Helic3::Erp::Customer.new(cedula: '1098765432', nombre: 'Pedro Martínez',
                                                email: 'pedro.martinez@correo.com', telefono: '3106667788',
                                                ciudad: 'Medellín', direccion: 'Cra 43A # 5-15, El Poblado')
    }
  end

  # cédula => [Invoice]. Cada factura trae su centro de operación (tienda) e ítems con
  # referencia, como el Diseño de ERP-15; los totales cuadran con la suma de las líneas.
  def item(referencia, descripcion, cantidad, valor)
    Helic3::Erp::InvoiceItem.new(referencia: referencia, descripcion: descripcion, cantidad: cantidad, valor: valor)
  end

  def invoices # rubocop:disable Metrics/MethodLength
    {
      # Ana: al día (todo pagado). FV-1001 tiene DOS productos (caso del selector ERP-15).
      '1032456789' => [
        Helic3::Erp::Invoice.new(numero: 'FV-1001', fecha: '2026-05-10', total: 1_800_000, saldo: 0, estado: 'pagada',
                                 centro_operacion: 'Armenia Centro',
                                 items: [item('MIL-200', 'Puerta Milano', 2, 900_000),
                                         item('CER-050', 'Cerradura Premium', 1, 900_000)]),
        Helic3::Erp::Invoice.new(numero: 'FV-1002', fecha: '2026-06-02', total: 450_000, saldo: 0, estado: 'pagada',
                                 centro_operacion: 'Armenia Centro',
                                 items: [item('MES-120', 'Mesa de Centro Nogal', 1, 450_000)])
      ],
      # Carlos: una pendiente
      '79856231' => [
        Helic3::Erp::Invoice.new(numero: 'FV-1050', fecha: '2026-06-20', total: 3_200_000, saldo: 3_200_000, estado: 'pendiente',
                                 centro_operacion: 'Bogotá Norte',
                                 items: [item('COC-900', 'Cocina Integral', 1, 3_200_000)])
      ],
      # Laura: en mora (vencida)
      '52998877' => [
        Helic3::Erp::Invoice.new(numero: 'FV-0980', fecha: '2026-03-15', total: 1_200_000, saldo: 1_200_000, estado: 'vencida',
                                 centro_operacion: 'Pereira Principal',
                                 items: [item('SOF-300', 'Sofá 3 Puestos', 1, 1_200_000)])
      ],
      # Pedro: mezcla
      '1098765432' => [
        Helic3::Erp::Invoice.new(numero: 'FV-1100', fecha: '2026-04-01', total: 800_000, saldo: 0, estado: 'pagada',
                                 centro_operacion: 'Medellín El Poblado',
                                 items: [item('COM-600', 'Comedor 6 Sillas', 1, 800_000)]),
        Helic3::Erp::Invoice.new(numero: 'FV-1101', fecha: '2026-06-28', total: 1_500_000, saldo: 1_500_000, estado: 'pendiente',
                                 centro_operacion: 'Medellín El Poblado',
                                 items: [item('CLO-400', 'Closet Multiuso', 1, 1_500_000)]),
        Helic3::Erp::Invoice.new(numero: 'FV-1102', fecha: '2026-02-10', total: 600_000, saldo: 600_000, estado: 'vencida',
                                 centro_operacion: 'Medellín El Poblado',
                                 items: [item('NOC-100', 'Nochero', 2, 600_000)])
      ]
    }
  end

  def cedulas
    customers.keys
  end

  def customer(cedula)
    customers[cedula]
  end

  def invoices_for(cedula)
    invoices.fetch(cedula, [])
  end

  def invoice(number)
    invoices.values.flatten.find { |factura| factura.numero == number }
  end

  # Estado de cuenta derivado de las facturas, para que sea consistente con el caso del cliente.
  def statement(cedula)
    return nil unless customers.key?(cedula)

    facturas = invoices_for(cedula)
    pendientes = facturas.reject { |factura| factura.estado == 'pagada' }
    Helic3::Erp::AccountStatement.new(
      cedula: cedula,
      saldo_total: pendientes.sum(&:saldo),
      facturas_pendientes: pendientes.size,
      al_dia: facturas.none? { |factura| factura.estado == 'vencida' }
    )
  end
end
