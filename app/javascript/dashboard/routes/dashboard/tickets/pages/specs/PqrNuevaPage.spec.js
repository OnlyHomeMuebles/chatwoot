import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import PqrNuevaPage from '../PqrNuevaPage.vue';

// MAN-02: el wizard expone su estado/acciones (defineExpose) para probar el flujo
// sin depender del render de los primitivos (shallowMount los stubbea).
const push = vi.fn();
const alert = vi.fn();
const crearApi = vi.fn();
const subirApi = vi.fn();
const consultarErpApi = vi.fn();
// crear() pasa por store.dispatch('tickets/create'); el mock delega en crearApi
// (que los tests configuran) y devuelve el ticket como lo hace el store real
// (response.data). Un rechazo de crearApi se propaga, igual que el store.
const dispatch = vi.fn((action, payload) =>
  action === 'tickets/create'
    ? Promise.resolve(crearApi(payload)).then(r => r?.data)
    : Promise.resolve()
);

const catalogosRef = ref({
  tipos: [{ id: 1, nombre: 'Petición' }],
  motivos_pqr: [
    {
      id: 10,
      nombre: 'Garantía de producto',
      categoria: { nombre: 'Garantía' },
    },
  ],
  detalles_tipificados: [{ id: 100, nombre: 'Tela motosa' }],
});
const agentsRef = ref([{ id: 5, name: 'Agente Uno' }]);
// route mutable: algunos tests abren el wizard desde una conversación (?conversation=)
const routeState = { query: {} };

vi.mock('dashboard/api/tickets', () => ({
  default: {
    create: (...args) => crearApi(...args),
    subirDocumento: (...args) => subirApi(...args),
    consultarErpCliente: (...args) => consultarErpApi(...args),
  },
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'agents/getAgents') return agentsRef;
    return catalogosRef; // tickets/getCatalogos
  },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: (...args) => alert(...args),
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' }, query: routeState.query }),
  useRouter: () => ({ push }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
  }),
}));

const montar = () => shallowMount(PqrNuevaPage);

const llenarMinimo = vm => {
  vm.form.motivo_pqr_id = 10;
  vm.form.description = 'El sofá llegó roto';
  vm.form.cliente_nombre = 'Ana Pérez';
  vm.form.cliente_telefono = '3001234567';
};

beforeEach(() => {
  push.mockClear();
  dispatch.mockClear();
  alert.mockClear();
  crearApi.mockReset();
  subirApi.mockReset().mockResolvedValue();
  consultarErpApi.mockReset();
  delete catalogosRef.value.erp_habilitado;
  routeState.query = {};
});

describe('PqrNuevaPage.vue — validación por paso (MAN-02)', () => {
  it('«Continuar» no avanza sin motivo o descripción', () => {
    const wrapper = montar();

    wrapper.vm.continuar();

    expect(wrapper.vm.paso).toBe(1);
    expect(wrapper.vm.errorPaso).toBe('TICKETS.NUEVA.ERRORES.MOTIVO');
  });

  it('«Continuar» avanza al paso 2 con motivo y descripción', () => {
    const wrapper = montar();
    wrapper.vm.form.motivo_pqr_id = 10;
    wrapper.vm.form.description = 'detalle';

    wrapper.vm.continuar();

    expect(wrapper.vm.paso).toBe(2);
    expect(wrapper.vm.errorPaso).toBe('');
  });

  it('«Crear» no envía sin cliente o teléfono (CA2 de la pantalla)', async () => {
    const wrapper = montar();
    wrapper.vm.form.motivo_pqr_id = 10;
    wrapper.vm.form.description = 'detalle';

    await wrapper.vm.crear();

    expect(crearApi).not.toHaveBeenCalled();
    expect(wrapper.vm.errorPaso).toBe('TICKETS.NUEVA.ERRORES.CLIENTE');
  });
});

describe('PqrNuevaPage.vue — crear (MAN-02)', () => {
  it('envía UN POST con title "Motivo · Cliente", numero_orden y el bloque datos', async () => {
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);
    wrapper.vm.form.numero_orden = 'OH-1';
    wrapper.vm.form.cedula = '123';

    await wrapper.vm.crear();
    await flushPromises();

    expect(crearApi).toHaveBeenCalledTimes(1);
    const payload = crearApi.mock.calls[0][0].ticket;
    expect(payload.title).toBe('Garantía de producto · Ana Pérez');
    expect(payload.numero_orden).toBe('OH-1');
    expect(payload.datos.cliente_nombre).toBe('Ana Pérez');
    expect(payload.datos.cliente_telefono).toBe('3001234567');
    expect(payload.datos.cedula).toBe('123');
  });

  it('tras crear, navega al detalle del expediente nuevo', async () => {
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);

    await wrapper.vm.crear();
    await flushPromises();

    expect(push).toHaveBeenCalledWith({
      name: 'helic3_pqr_detail',
      params: { accountId: '1', id: 42 },
    });
  });

  it('sube los adjuntos uno por uno tras crear', async () => {
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);
    wrapper.vm.adjuntos.push(
      { id: 1, file: new File(['a'], 'foto.png') },
      { id: 2, file: new File(['b'], 'factura.pdf') }
    );

    await wrapper.vm.crear();
    await flushPromises();

    expect(subirApi).toHaveBeenCalledTimes(2);
    expect(subirApi.mock.calls[0][0]).toBe(42); // ticketId
  });

  it('muestra el error del backend (422) y no navega', async () => {
    crearApi.mockRejectedValue({
      response: { data: { message: 'Falta el cliente' } },
    });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);

    await wrapper.vm.crear();
    await flushPromises();

    expect(wrapper.vm.errorBackend).toBe('Falta el cliente');
    expect(push).not.toHaveBeenCalled();
  });

  // El backend usa dos claves segun el caso: las validaciones de Rails viajan en
  // data.message, pero errores de negocio como la etapa inicial faltante (CAS-01)
  // viajan en data.error. El wizard debe mostrar ambos, no caer al generico.
  it('muestra el error del backend cuando viene en data.error (etapa inicial faltante)', async () => {
    crearApi.mockRejectedValue({
      response: {
        data: { error: "falta la etapa inicial 'nueva' en la cuenta 1" },
      },
    });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);

    await wrapper.vm.crear();
    await flushPromises();

    expect(wrapper.vm.errorBackend).toBe(
      "falta la etapa inicial 'nueva' en la cuenta 1"
    );
    expect(push).not.toHaveBeenCalled();
  });

  it('no radica dos veces si se invoca crear() de nuevo mientras guarda (anti doble-clic)', async () => {
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);

    const primera = wrapper.vm.crear();
    const segunda = wrapper.vm.crear(); // segundo "clic" mientras la primera guarda
    await Promise.all([primera, segunda]);
    await flushPromises();

    expect(crearApi).toHaveBeenCalledTimes(1);
  });

  it('abierto desde una conversación: asocia la conversación y NO exige cliente (Cambio A)', async () => {
    routeState.query = { conversation: '77' };
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    // solo lo mínimo del paso 1, SIN datos de cliente
    wrapper.vm.form.motivo_pqr_id = 10;
    wrapper.vm.form.description = 'Llegó roto';

    await wrapper.vm.crear();
    await flushPromises();

    expect(crearApi).toHaveBeenCalledTimes(1);
    expect(crearApi.mock.calls[0][0].ticket.conversation_id).toBe('77');
  });

  it('sin conversación, el payload lleva conversation_id nulo', async () => {
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const wrapper = montar();
    llenarMinimo(wrapper.vm);

    await wrapper.vm.crear();
    await flushPromises();

    expect(crearApi.mock.calls[0][0].ticket.conversation_id).toBeNull();
  });

  it('"volver" navega a la bandeja de PQR (destino determinista)', () => {
    const wrapper = montar();

    wrapper.vm.volverABandeja();

    expect(push).toHaveBeenCalledWith({
      name: 'tickets_index',
      params: { accountId: '1' },
    });
  });
});

describe('PqrNuevaPage.vue — ERP (ERP-11)', () => {
  it('CA3: sin erp_habilitado el boton Consultar Siesa no esta disponible', () => {
    expect(montar().vm.erpHabilitado).toBe(false);
  });

  it('erpHabilitado es true cuando el catalogo lo trae encendido', () => {
    catalogosRef.value = { ...catalogosRef.value, erp_habilitado: true };
    expect(montar().vm.erpHabilitado).toBe(true);
  });

  it('CA1: consultar llena y marca los campos; al crear envia consultado_erp en true', async () => {
    catalogosRef.value = { ...catalogosRef.value, erp_habilitado: true };
    consultarErpApi.mockResolvedValue({
      data: {
        encontrado: true,
        cliente: {
          cedula: '1032456789',
          nombre: 'Ana Ruiz',
          telefono: '3001112233',
          email: 'ana@correo.com',
          ciudad: 'Armenia',
          direccion: 'Cra 14',
        },
      },
    });
    crearApi.mockResolvedValue({ data: { id: 42, display_id: 7 } });
    const vm = montar().vm;
    vm.form.motivo_pqr_id = 10;
    vm.form.description = 'El sofá llegó roto';
    vm.form.cedula = '1032456789';

    await vm.erp.consultar();

    expect(vm.form.cliente_nombre).toBe('Ana Ruiz');
    expect(vm.form.ciudad).toBe('Armenia');
    expect(vm.erp.tieneBadge('cliente_nombre')).toBe(true);

    await vm.crear();
    await flushPromises();
    expect(crearApi.mock.calls[0][0].ticket.consultado_erp).toBe(true);
  });

  it('CA4: con el ERP caido avisa y NO bloquea el crear (consultado_erp false)', async () => {
    catalogosRef.value = { ...catalogosRef.value, erp_habilitado: true };
    consultarErpApi.mockRejectedValue({ response: { status: 503 } });
    crearApi.mockResolvedValue({ data: { id: 43, display_id: 8 } });
    const vm = montar().vm;
    vm.form.motivo_pqr_id = 10;
    vm.form.description = 'El sofá llegó roto';
    vm.form.cedula = '1032456789';
    vm.form.cliente_nombre = 'A mano';
    vm.form.cliente_telefono = '3001234567';

    await vm.erp.consultar();
    expect(vm.erp.estado.value).toBe('no_disponible');

    await vm.crear();
    await flushPromises();
    expect(crearApi).toHaveBeenCalled();
    expect(crearApi.mock.calls[0][0].ticket.consultado_erp).toBe(false);
  });

  it('ERP-15/B1/B3: UNA peticion trae cliente + facturas; multi-seleccion de productos', async () => {
    catalogosRef.value = { ...catalogosRef.value, erp_habilitado: true };
    // Una sola peticion (#show) devuelve cliente y facturas juntos.
    consultarErpApi.mockResolvedValue({
      data: {
        encontrado: false,
        facturas: [
          {
            numero: 'FV-1001',
            fecha: '2026-05-10',
            centro_operacion: 'Armenia Centro',
            items: [
              { referencia: 'MIL-200', descripcion: 'Puerta Milano', cantidad: 2, valor: 900000 },
              { referencia: 'CER-050', descripcion: 'Cerradura Premium', cantidad: 1, valor: 900000 },
            ],
          },
        ],
      },
    });
    const vm = montar().vm;
    vm.form.cedula = '26478046';

    await vm.consultarSiesa();
    await flushPromises();

    expect(consultarErpApi).toHaveBeenCalledTimes(1); // B1: una sola peticion, no dos
    const facturas = vm.facturasErp.facturas.value;
    expect(facturas).toHaveLength(1);

    // B3: se eligen DOS productos de la misma factura.
    vm.facturasErp.alternar(facturas[0], facturas[0].items[0]);
    vm.facturasErp.alternar(facturas[0], facturas[0].items[1]);

    expect(vm.form.numero_orden).toBe('FV-1001');
    expect(vm.form.factura_fecha).toBe('2026-05-10');
    expect(vm.facturasErp.productosElegidos()).toEqual([
      { nombre: 'Puerta Milano', referencia: 'MIL-200' },
      { nombre: 'Cerradura Premium', referencia: 'CER-050' },
    ]);
  });

  it('ERP-14: "Volver a consultar" aparece tras un resultado y reconsulta con refrescar', async () => {
    catalogosRef.value = { ...catalogosRef.value, erp_habilitado: true };
    consultarErpApi.mockResolvedValue({
      data: { encontrado: true, cliente: { nombre: 'Ana' }, facturas: [] },
    });
    const vm = montar().vm;
    vm.form.cedula = '26478046';

    await vm.consultarSiesa();
    await flushPromises();
    expect(vm.hayConsultaErp).toBe(true); // ya hay resultado -> se muestra "Volver a consultar"

    consultarErpApi.mockClear();
    await vm.reconsultarSiesa();
    await flushPromises();

    expect(consultarErpApi).toHaveBeenCalledWith('26478046', expect.anything(), { refrescar: true });
  });
});
