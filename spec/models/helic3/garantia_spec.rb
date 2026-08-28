# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Helic3::Garantia, type: :model do
  let(:account) { create(:account) }
  let(:ticket) { create(:ticket, account: account) }

  # la porcion del catalogo de procesos que estos specs necesitan, con las
  # posiciones y marcas terminales del diseno validado (CAT-02)
  let(:visita) { crear_proceso('Visita técnica', 'visita_tecnica', 1, plazo: 8) }
  let(:reparacion) { crear_proceso('Reparación en fábrica', 'reparacion_fabrica', 3) }
  let(:entrega) { crear_proceso('Entrega de producto', 'entrega_producto', 5, terminal: true) }
  let(:negada) { crear_proceso('Garantía negada', 'garantia_negada', 7, terminal: true) }

  def crear_proceso(nombre, codigo, posicion, plazo: nil, terminal: false)
    Helic3::Catalogo::ProcesoGarantia.create!(account: account, nombre: nombre, codigo: codigo,
                                              posicion: posicion, plazo_dias_habiles: plazo,
                                              es_terminal: terminal)
  end

  def crear_garantia_con(*productos)
    garantia = described_class.create!(account: account, ticket: ticket)
    items = productos.map do |nombre|
      Helic3::GarantiaItem.create!(account: account, garantia: garantia, producto_nombre: nombre)
    end
    [garantia, *items]
  end

  it 'una garantia con dos productos recibe un solo numero de radicado' do
    garantia, cama, nochero = crear_garantia_con('Cama King Sion', 'Nochero Sion')

    expect(garantia.display_id).to be_present
    expect(garantia.items).to contain_exactly(cama, nochero)
    expect(cama.garantia.numero_radicado).to eq(nochero.garantia.numero_radicado)
  end

  it 'cada producto se clasifica con motivo y detalle distintos y avanza independiente' do
    calidad = Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Calidad - producto comprado',
                                                       codigo: 'calidad_producto_comprado')
    reparacion_pe = Helic3::Catalogo::MotivoGarantia.create!(account: account, nombre: 'Reparación - primera entrega',
                                                             codigo: 'reparacion_primera_entrega')
    fractura = Helic3::Catalogo::DetalleTipificado.create!(account: account, nombre: 'Producto fracturado o roto',
                                                           codigo: 'producto_fracturado_o_roto')
    _garantia, cama, nochero = crear_garantia_con('Cama', 'Nochero')

    cama.update!(motivo_garantia: calidad, detalle_tipificado: fractura)
    nochero.update!(motivo_garantia: reparacion_pe)
    cama.avanzar_a!(visita)

    expect(cama.reload.proceso).to eq(visita)
    expect(nochero.reload.proceso).to be_nil
    expect(cama.motivo_garantia).not_to eq(nochero.motivo_garantia)
  end

  it 'el caso de la cama y el nochero: un radicado, dos caminos, cierre solo con ambos terminales' do
    garantia, cama, nochero = crear_garantia_con('Cama King Sion', 'Nochero Sion')

    # la visita tecnica dictamina: la cama a reparacion, el nochero se niega
    cama.avanzar_a!(reparacion)
    nochero.avanzar_a!(negada, decision: 'Garantía negada por mal uso')

    # 1. el radicado muestra el estado del mas atrasado (la cama, pendiente)
    expect(garantia.reload.proceso_visible).to eq(reparacion)

    # 2. la negacion resuelve al nochero, pero NO cierra mientras la cama siga en reparacion
    expect(nochero.reload).to be_resuelto
    expect(garantia).not_to be_resuelta
    expect(garantia.cerrar!).to be(false)

    # 3. cierra cuando ambos quedan en estado terminal
    cama.avanzar_a!(entrega)
    expect(garantia.reload).to be_resuelta
    expect(garantia.cerrar!).to be(true)
    expect(garantia.cerrada_at).to be_present
  end

  it 'el estado visible es el del producto mas atrasado por posicion de catalogo' do
    garantia, cama, nochero = crear_garantia_con('Cama', 'Nochero')

    cama.avanzar_a!(reparacion) # posicion 3
    nochero.avanzar_a!(visita)  # posicion 1: mas atrasado

    expect(garantia.reload.proceso_visible).to eq(visita)
  end

  it 'el consecutivo arranca desde la semilla configurada, no desde 1 por defecto' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'radicado_garantia_inicio',
                                        valor: '5000', unidad: 'cantidad')
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'radicado_garantia_prefijo',
                                        valor: 'GAR-', unidad: 'texto')

    primera = described_class.create!(account: account, ticket: ticket)
    segunda = described_class.create!(account: account, ticket: create(:ticket, account: account))

    expect(primera.display_id).to eq(5000)
    expect(segunda.display_id).to eq(5001)
    expect(primera.numero_radicado).to eq('GAR-5000')
  end

  it 'guarda una sola fecha de apertura para todo el radicado, no una por producto' do
    garantia, = crear_garantia_con('Cama', 'Nochero')

    expect(garantia.abierta_at).to be_present
    expect(Helic3::GarantiaItem.column_names).not_to include('abierta_at')
  end

  it 'copia el presupuesto de dias del parametro al crear y expone el enganche a PLZ-01' do
    Helic3::Catalogo::Parametro.create!(account: account, clave: 'plazo_total_garantia',
                                        valor: '30', unidad: 'dias_habiles')
    garantia, cama, = crear_garantia_con('Cama', 'Nochero')
    cama.avanzar_a!(visita)

    expect(garantia.presupuesto_dias_habiles).to eq(30)

    parametros = Helic3::ParametrosGarantia.new(total_dias: 30, umbral_verde: 15, umbral_amarillo: 5)
    estado = garantia.presupuesto(parametros: parametros).estado
    expect(estado).to include(:consumidos, :saldo, :fecha_etapa_vigente, :semaforo)
  end

  it 'rechaza un ticket o un catalogo de otra cuenta' do
    ajeno = create(:ticket)
    garantia = described_class.new(account: account, ticket: ajeno)

    expect(garantia).not_to be_valid
    expect(garantia.errors[:ticket]).to be_present
  end
end
