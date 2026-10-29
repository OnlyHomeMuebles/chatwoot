import { reactive } from 'vue';
import { useErpCliente } from '../useErpCliente';
import TicketsAPI from 'dashboard/api/tickets';

vi.mock('dashboard/api/tickets', () => ({
  default: { consultarErpCliente: vi.fn() },
}));

const CLIENTE = {
  cedula: '1032456789',
  nombre: 'Ana Ruiz',
  telefono: '3001112233',
  email: 'ana.ruiz@correo.com',
  ciudad: 'Armenia',
  direccion: 'Cra 14 # 10-25',
};

const nuevoForm = () =>
  reactive({
    cedula: '',
    cliente_nombre: '',
    cliente_telefono: '',
    cliente_email: '',
    ciudad: '',
    direccion: '',
  });

describe('useErpCliente', () => {
  beforeEach(() => vi.clearAllMocks());

  it('CA1: llena los campos vacios con lo de Siesa y los marca con badge', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);

    await erp.consultar();

    expect(form.cliente_nombre).toBe('Ana Ruiz');
    expect(form.ciudad).toBe('Armenia');
    expect(erp.tieneBadge('cliente_nombre')).toBe(true);
    expect(erp.tieneBadge('direccion')).toBe(true);
    expect(erp.estado.value).toBe('encontrado');
  });

  it('CA2: no pisa un campo que el agente ya escribio', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    form.cliente_telefono = '3009999999'; // ya escrito por el agente
    const erp = useErpCliente(form);

    await erp.consultar();

    expect(form.cliente_telefono).toBe('3009999999');
    expect(erp.tieneBadge('cliente_telefono')).toBe(false);
    expect(form.cliente_nombre).toBe('Ana Ruiz'); // los vacios si se llenan
  });

  it('editar un campo le quita el badge "Siesa"', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);
    await erp.consultar();

    expect(erp.tieneBadge('cliente_nombre')).toBe(true);
    erp.alEditar('cliente_nombre');
    expect(erp.tieneBadge('cliente_nombre')).toBe(false);
  });

  it('cambiar la cedula vacia lo que seguia con badge y resetea el estado', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);
    await erp.consultar();
    expect(form.ciudad).toBe('Armenia');

    erp.alCambiarCedula();

    expect(form.ciudad).toBe('');
    expect(erp.tieneBadge('ciudad')).toBe(false);
    expect(erp.estado.value).toBe('idle');
  });

  it('CA4: con el ERP caido (503) avisa no_disponible y no llena nada', async () => {
    TicketsAPI.consultarErpCliente.mockRejectedValue({
      response: { status: 503 },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);

    await erp.consultar();

    expect(erp.estado.value).toBe('no_disponible');
    expect(form.cliente_nombre).toBe('');
  });

  it('cedula invalida (422) -> estado cedula_invalida', async () => {
    TicketsAPI.consultarErpCliente.mockRejectedValue({
      response: { status: 422 },
    });
    const form = nuevoForm();
    form.cedula = '123';
    const erp = useErpCliente(form);

    await erp.consultar();

    expect(erp.estado.value).toBe('cedula_invalida');
  });

  it('cedula desconocida -> estado no_encontrado', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: false },
    });
    const form = nuevoForm();
    form.cedula = '99999999';
    const erp = useErpCliente(form);

    await erp.consultar();

    expect(erp.estado.value).toBe('no_encontrado');
  });

  it('consultar devuelve las facturas de la misma respuesta (una sola peticion, B1)', async () => {
    const FACTURAS = [{ numero: 'FV-1001', fecha: '2026-05-10', items: [] }];
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE, facturas: FACTURAS },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);

    const facturas = await erp.consultar();

    expect(facturas).toEqual(FACTURAS);
  });

  it('consultadoErp es true solo si la ultima consulta exitosa fue con la cedula actual', async () => {
    TicketsAPI.consultarErpCliente.mockResolvedValue({
      data: { encontrado: true, cliente: CLIENTE },
    });
    const form = nuevoForm();
    form.cedula = '1032456789';
    const erp = useErpCliente(form);
    await erp.consultar();

    expect(erp.consultadoErp()).toBe(true);
    form.cedula = '55555555'; // cambio la cedula sin consultar de nuevo
    expect(erp.consultadoErp()).toBe(false);
  });
});
