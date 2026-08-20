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
module OnlyHome::Erp::SimulatedData
  module_function

  # cédula => Customer
  def customers
    {
      '1032456789' => OnlyHome::Erp::Customer.new(cedula: '1032456789', nombre: 'Ana Ruiz',
                                                  email: 'ana.ruiz@correo.com', telefono: '3001112233'),
      '79856231' => OnlyHome::Erp::Customer.new(cedula: '79856231', nombre: 'Carlos Díaz',
                                                email: 'carlos.diaz@correo.com', telefono: '3014445566'),
      '52998877' => OnlyHome::Erp::Customer.new(cedula: '52998877', nombre: 'Laura Gómez',
                                                email: 'laura.gomez@correo.com', telefono: '3027778899'),
      '1098765432' => OnlyHome::Erp::Customer.new(cedula: '1098765432', nombre: 'Pedro Martínez',
                                                  email: 'pedro.martinez@correo.com', telefono: '3106667788')
    }
  end

  # cédula => [Invoice]
  def invoices
    {
      # Ana: al día (todo pagado)
      '1032456789' => [
        OnlyHome::Erp::Invoice.new(numero: 'FV-1001', fecha: '2026-05-10', total: 1_800_000, saldo: 0, estado: 'pagada',
                                   items: [{ descripcion: 'Puerta Milano', cantidad: 2, valor: 900_000 }]),
        OnlyHome::Erp::Invoice.new(numero: 'FV-1002', fecha: '2026-06-02', total: 450_000, saldo: 0, estado: 'pagada')
      ],
      # Carlos: una pendiente
      '79856231' => [
        OnlyHome::Erp::Invoice.new(numero: 'FV-1050', fecha: '2026-06-20', total: 3_200_000, saldo: 3_200_000, estado: 'pendiente',
                                   items: [{ descripcion: 'Cocina integral', cantidad: 1, valor: 3_200_000 }])
      ],
      # Laura: en mora (vencida)
      '52998877' => [
        OnlyHome::Erp::Invoice.new(numero: 'FV-0980', fecha: '2026-03-15', total: 1_200_000, saldo: 1_200_000, estado: 'vencida')
      ],
      # Pedro: mezcla
      '1098765432' => [
        OnlyHome::Erp::Invoice.new(numero: 'FV-1100', fecha: '2026-04-01', total: 800_000, saldo: 0, estado: 'pagada'),
        OnlyHome::Erp::Invoice.new(numero: 'FV-1101', fecha: '2026-06-28', total: 1_500_000, saldo: 1_500_000, estado: 'pendiente'),
        OnlyHome::Erp::Invoice.new(numero: 'FV-1102', fecha: '2026-02-10', total: 600_000, saldo: 600_000, estado: 'vencida')
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
    OnlyHome::Erp::AccountStatement.new(
      cedula: cedula,
      saldo_total: pendientes.sum(&:saldo),
      facturas_pendientes: pendientes.size,
      al_dia: facturas.none? { |factura| factura.estado == 'vencida' }
    )
  end
end
