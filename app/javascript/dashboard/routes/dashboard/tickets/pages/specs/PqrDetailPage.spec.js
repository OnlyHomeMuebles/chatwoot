import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import PqrDetailPage from '../PqrDetailPage.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// Estado controlable del expediente actual (lo que devuelve pqrInbox/getCurrent).
const expedienteRef = ref(null);
const documentosRef = ref([]);
const uiFlagsRef = ref({ isFetchingItem: false, isUploadingDocumento: false });
// MAN-03: catalogo de resultados para la tarjeta "Resolver PQR".
const catalogosRef = ref({ resultados: [] });
// Devuelve siempre una promesa real: onMounted hace .catch sobre tickets/getCatalogos.
const dispatch = vi.fn(() => Promise.resolve());
const routerPush = vi.fn();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
  useMapGetter: getter => {
    if (getter === 'pqrInbox/getUIFlags') return uiFlagsRef;
    if (getter === 'agents/getAgents') return ref([]);
    if (getter === 'pqrInbox/getDocumentos') return documentosRef;
    if (getter === 'tickets/getCatalogos') return catalogosRef;
    return expedienteRef; // pqrInbox/getCurrent
  },
}));

vi.mock('vue-router', () => ({
  useRoute: () => ({ params: { accountId: '1' } }),
  useRouter: () => ({ push: routerPush }),
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, args) => (args ? `${key} ${JSON.stringify(args)}` : key),
  }),
}));

// Aviso de amparo vencido (GAR): el único uso de composables en el componente es
// useAlert; lo espiamos para comprobar el toast.
import { useAlert } from 'dashboard/composables';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// MAN-03: stub del dialogo de garantia con un open() espiable, para comprobar que
// un resultado que abre garantia abre el dialogo (en vez de resolver directo).
const garantiaOpen = vi.fn();
const GarantiaStub = {
  name: 'GarantiaFormDialog',
  template: '<div data-testid="garantia-dialog" />',
  methods: { open: garantiaOpen },
};

// ACT-01: stub del modal de nueva actividad con un open() espiable.
const actividadOpen = vi.fn();
const NuevaActividadStub = {
  name: 'NuevaActividadModal',
  template: '<div />',
  methods: { open: actividadOpen },
};

const expedienteBase = {
  id: 7,
  title: 'Sofá rayado',
  numero_radicado: '#3',
  status: 'open',
};

const conGarantia = {
  ...expedienteBase,
  garantia: {
    numero_radicado: '1204',
    presupuesto_dias_habiles: 30,
    proceso_visible: { nombre: 'Visita técnica' },
    cobertura_ciudad: { nombre: 'Manizales', tecnico_propio: true },
    presupuesto: { consumidos: 3, saldo: 27, semaforo: 'verde' },
    items: [
      {
        id: 9,
        producto_nombre: 'Sofá Modular',
        proceso: { nombre: 'Visita técnica' },
      },
    ],
  },
};

const montar = () =>
  shallowMount(PqrDetailPage, {
    props: { id: 7 },
    global: {
      stubs: {
        GarantiaFormDialog: GarantiaStub,
        NuevaActividadModal: NuevaActividadStub,
      },
    },
  });

// Busca el <Select> de "Resolver PQR" por su placeholder (único en la vista).
const selectResolver = wrapper =>
  wrapper
    .findAllComponents(Select)
    .find(s => s.props('placeholder') === 'TICKETS.RESOLVER.PLACEHOLDER');

beforeEach(() => {
  documentosRef.value = [];
  uiFlagsRef.value = { isFetchingItem: false, isUploadingDocumento: false };
  catalogosRef.value = { resultados: [] };
  dispatch.mockClear();
  garantiaOpen.mockClear();
  actividadOpen.mockClear();
  routerPush.mockClear();
  useAlert.mockClear();
});

describe('PqrDetailPage.vue — bloque de garantía (DET-01)', () => {
  it('pinta el bloque de garantía cuando viene en el payload', () => {
    expedienteRef.value = conGarantia;

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-garantia"]').exists()).toBe(true);
    expect(wrapper.text()).toContain('1204');
  });

  it('NO pinta el bloque de garantía cuando garantia es null', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-garantia"]').exists()).toBe(
      false
    );
  });
});

describe('PqrDetailPage.vue — documentos del expediente (EVI-03)', () => {
  it('pide el archivo documental al montar', async () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };

    montar();
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetchDocumentos', 7);
  });

  it('muestra el estado vacío cuando no hay documentos ni formato de garantía', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [];

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.DOC_EMPTY');
  });

  it('lista los documentos reales, con remitente y sin el estado vacío', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [
      {
        id: 1,
        clase: 'evidencia',
        origen: 'cliente',
        titulo: 'factura.jpg',
        tipo_archivo: 'image/jpeg',
        url: 'https://x.test/factura.jpg',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: 'Juan Pérez', user_id: null },
      },
    ];

    const wrapper = montar();

    expect(wrapper.text()).toContain('factura.jpg');
    expect(wrapper.text()).toContain('Juan Pérez');
    expect(wrapper.text()).not.toContain('TICKETS.DETAIL.DOC_EMPTY');
  });

  it('un documento del agente sin remitente muestra la etiqueta de agente IA', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [
      {
        id: 2,
        clase: 'evidencia',
        origen: 'agente',
        titulo: 'foto.png',
        tipo_archivo: 'image/png',
        url: 'https://x.test/foto.png',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: null, user_id: null },
      },
    ];

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_BY_AGENT');
  });

  it('separa imágenes (preview) de otros documentos, y no pinta una imagen sin url', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    documentosRef.value = [
      {
        id: 1,
        clase: 'evidencia',
        origen: 'cliente',
        titulo: 'foto.png',
        tipo_archivo: 'image/png',
        url: 'https://x.test/foto.png',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: 'Ana', user_id: null },
      },
      {
        id: 2,
        clase: 'evidencia',
        origen: 'cliente',
        titulo: 'factura.pdf',
        tipo_archivo: 'application/pdf',
        url: 'https://x.test/factura.pdf',
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: 'Ana', user_id: null },
      },
      {
        id: 3,
        clase: 'evidencia',
        origen: 'cliente',
        titulo: 'rota.png',
        tipo_archivo: 'image/png',
        url: null,
        ocurrido_at: '2026-09-20T10:00:00Z',
        remitente: { nombre: 'Ana', user_id: null },
      },
    ];

    const wrapper = montar();
    const srcsDeDocumentos = wrapper
      .findAll('img')
      .map(img => img.attributes('src'))
      .filter(src => src && src.includes('x.test'));

    // solo la imagen CON url se pinta como preview; el PDF y la imagen sin url no
    expect(srcsDeDocumentos).toEqual(['https://x.test/foto.png']);
    // pero los tres se listan igual (imagen como preview, los otros como fila)
    expect(wrapper.text()).toContain('foto.png');
    expect(wrapper.text()).toContain('factura.pdf');
    expect(wrapper.text()).toContain('rota.png');
  });
});

describe('PqrDetailPage.vue — actividad desde la bitácora real (EVI-03, cobro de EVT-01)', () => {
  it('pinta cada evento de la bitacora con su titulo y su autor', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [
        {
          id: 1,
          tipo: 'radicada',
          origen: 'humano',
          actor: { id: 3, name: 'Ana Torres' },
          created_at: '2026-09-19T09:00:00Z',
        },
        {
          id: 2,
          tipo: 'evidencia_adjuntada',
          origen: 'agente',
          actor: null,
          created_at: '2026-09-19T10:00:00Z',
        },
      ],
    };

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_FILED');
    expect(wrapper.text()).toContain('Ana Torres');
    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_EVIDENCIA_ADJUNTADA');
    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACT_BY_AGENT');
  });
});

describe('PqrDetailPage.vue — actividades de seguimiento (ACT-01)', () => {
  const evento = (id, tipo, at) => ({
    id,
    tipo,
    origen: 'humano',
    actor: { id: 3, name: 'Ana Torres' },
    created_at: at,
  });
  const seguimiento = (id, titulo, at, detalle = 'Detalle') => ({
    id,
    titulo,
    detalle,
    autor_nombre: 'Karen Vanegas',
    created_at: at,
  });
  const boton = (wrapper, testid) => {
    const el = wrapper.find(`[data-testid="${testid}"]`).element;
    return wrapper.findAllComponents(Button).find(b => b.element === el);
  };
  const titulosVisibles = wrapper =>
    wrapper.findAll('[data-testid="hito"]').map(li => li.text());

  it('sin eventos ni actividades la seccion se ve igual, con el + y un aviso', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [],
      actividades: [],
    };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="seccion-actividad"]').exists()).toBe(
      true
    );
    expect(wrapper.text()).toContain('TICKETS.DETAIL.ACTIVITY_EMPTY');
    await boton(wrapper, 'btn-nueva-actividad').vm.$emit('click');
    expect(actividadOpen).toHaveBeenCalled();
  });

  it('mezcla eventos y seguimientos del mas nuevo al mas antiguo, con la etiqueta Seguimiento', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [
        evento(1, 'radicada', '2026-11-10T09:00:00Z'),
        evento(2, 'formato_generado', '2026-11-12T09:00:00Z'),
      ],
      actividades: [
        seguimiento(5, 'Llamada al cliente', '2026-11-13T10:42:00Z'),
        seguimiento(4, 'WhatsApp de seguimiento', '2026-11-11T08:00:00Z'),
      ],
    };

    const filas = titulosVisibles(montar());

    expect(filas).toHaveLength(4);
    expect(filas[0]).toContain('Llamada al cliente');
    expect(filas[0]).toContain('TICKETS.DETAIL.ACTIVITY_FOLLOW_UP');
    expect(filas[0]).toContain('Karen Vanegas');
    expect(filas[1]).toContain('TICKETS.DETAIL.ACT_FORMATO_GENERADO');
    expect(filas[1]).not.toContain('TICKETS.DETAIL.ACTIVITY_FOLLOW_UP');
    expect(filas[2]).toContain('WhatsApp de seguimiento');
    expect(filas[3]).toContain('TICKETS.DETAIL.ACT_FILED');
  });

  it('cerrada muestra las 4 mas recientes; el titulo despliega todas y las vuelve a cerrar', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [],
      actividades: [1, 2, 3, 4, 5, 6].map(n =>
        seguimiento(n, `Gestion ${n}`, `2026-11-0${n}T10:00:00Z`)
      ),
    };

    const wrapper = montar();
    expect(titulosVisibles(wrapper)).toHaveLength(4);
    expect(titulosVisibles(wrapper)[0]).toContain('Gestion 6');
    expect(boton(wrapper, 'ver-todas-actividad').props('label')).toBe(
      'TICKETS.DETAIL.ACTIVITY_SHOW_ALL {"n":6}'
    );

    await wrapper.find('[data-testid="titulo-actividad"]').trigger('click');
    expect(titulosVisibles(wrapper)).toHaveLength(6);

    await wrapper.find('[data-testid="titulo-actividad"]').trigger('click');
    expect(titulosVisibles(wrapper)).toHaveLength(4);

    await boton(wrapper, 'ver-todas-actividad').vm.$emit('click');
    expect(titulosVisibles(wrapper)).toHaveLength(6);
  });

  it('con 4 o menos no muestra "Ver las N"', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [evento(1, 'radicada', '2026-11-10T09:00:00Z')],
      actividades: [],
    };

    expect(montar().find('[data-testid="ver-todas-actividad"]').exists()).toBe(
      false
    );
  });

  it('dos actividades con el mismo titulo se ven las dos', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [
        evento(1, 'resultado_aplicado', '2026-11-10T09:00:00Z'),
        evento(2, 'resultado_aplicado', '2026-11-10T10:00:00Z'),
      ],
      actividades: [
        seguimiento(1, 'Llamada', '2026-11-11T09:00:00Z'),
        seguimiento(2, 'Llamada', '2026-11-11T10:00:00Z'),
      ],
    };

    const filas = titulosVisibles(montar());

    expect(filas.filter(f => f.includes('Llamada'))).toHaveLength(2);
    expect(
      filas.filter(f => f.includes('TICKETS.DETAIL.ACT_RESULTADO_APLICADO'))
    ).toHaveLength(2);
  });

  it('el detalle va cortado a dos lineas y un clic lo muestra completo', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [],
      actividades: [
        seguimiento(1, 'Llamada', '2026-11-11T09:00:00Z', 'Texto largo'),
      ],
    };

    const wrapper = montar();
    const detalle = () => wrapper.find('[data-testid="hito-detalle"]');
    expect(detalle().classes()).toContain('line-clamp-2');

    await detalle().trigger('click');
    expect(detalle().classes()).not.toContain('line-clamp-2');
  });

  it('el detalle tambien se despliega con el teclado', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      eventos: [],
      actividades: [seguimiento(1, 'Llamada', '2026-11-11T09:00:00Z')],
    };

    const wrapper = montar();
    const fila = wrapper.find('[data-testid="hito"] [role="button"]');
    expect(fila.attributes('tabindex')).toBe('0');
    expect(fila.attributes('aria-expanded')).toBe('false');

    await fila.trigger('keydown', { key: 'Enter' });

    expect(fila.attributes('aria-expanded')).toBe('true');
    expect(
      wrapper.find('[data-testid="hito-detalle"]').classes()
    ).not.toContain('line-clamp-2');
  });
});

describe('PqrDetailPage.vue — resolver la PQR desde el detalle (MAN-03)', () => {
  const resultados = [
    {
      id: 10,
      nombre: 'Resuelto a favor',
      abre_garantia: false,
      aprobacion_humana: false,
    },
    {
      id: 20,
      nombre: 'Procede garantía',
      abre_garantia: true,
      aprobacion_humana: false,
    },
    {
      id: 30,
      nombre: 'Requiere visto bueno',
      abre_garantia: false,
      aprobacion_humana: true,
    },
  ];

  it('muestra la tarjeta "Resolver PQR" cuando el expediente no está respondido', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      respondida_at: null,
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-resolver"]').exists()).toBe(true);
    expect(selectResolver(wrapper)).toBeTruthy();
  });

  it('oculta la tarjeta cuando el expediente ya fue respondido', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      respondida_at: '2026-09-20T10:00:00Z',
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-resolver"]').exists()).toBe(
      false
    );
  });

  it('oculta la tarjeta cuando la PQR ya abrió garantía (aunque no esté respondida)', () => {
    expedienteRef.value = {
      ...expedienteBase,
      respondida_at: null,
      garantia: { numero_radicado: '1200' },
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-resolver"]').exists()).toBe(
      false
    );
  });

  it('muestra la tarjeta con un resultado NO terminal (Trasladada) para poder cerrarla luego', () => {
    // "Trasladada a otra área" no cierra la PQR ni abre garantía: la PQR sigue viva
    // y, al ser manual (sin panel de chat), este selector es la única forma de darle
    // el resultado final. Si se ocultara, la PQR se vencería sola.
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      respondida_at: null,
      resultado: { id: 99, nombre: 'Trasladada a otra área' },
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();

    expect(wrapper.find('[data-testid="bloque-resolver"]').exists()).toBe(true);
  });

  it('marca en el selector los resultados que requieren aprobación humana', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    catalogosRef.value = { resultados };

    const wrapper = montar();
    const opciones = selectResolver(wrapper).props('options');

    expect(opciones).toContainEqual({ value: 10, label: 'Resuelto a favor' });
    expect(opciones).toContainEqual({
      value: 30,
      label: 'Requiere visto bueno TICKETS.RESOLUTION.NEEDS_APPROVAL',
    });
  });

  it('con una propuesta pendiente avisa y enlaza a Decisiones, sin dejar resolver', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      resultado_propuesto_id: 20,
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();

    expect(wrapper.text()).toContain('TICKETS.RESOLVER.PROPOSAL_PENDING');
    // mientras haya propuesta pendiente no se ofrece el selector de resolución
    expect(selectResolver(wrapper)).toBeUndefined();
  });

  it('un resultado que NO abre garantía se resuelve directo (resolver + refetch)', async () => {
    expedienteRef.value = { ...expedienteBase, garantia: null };
    catalogosRef.value = { resultados };

    const wrapper = montar();
    await selectResolver(wrapper).vm.$emit('update:modelValue', 10);
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/resolver', {
      id: 7,
      resultadoId: 10,
    });
    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetchOne', 7);
    expect(garantiaOpen).not.toHaveBeenCalled();
  });

  it('un resultado que abre garantía NO resuelve directo: abre el diálogo con el prefill de la ficha', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: {
        producto_nombre: { valor: 'Sofá Modular', fuente: 'ia' },
        producto_referencia: { valor: 'SOF-123', fuente: 'ia' },
        ciudad: { valor: 'Manizales', fuente: 'ia' },
      },
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();
    await selectResolver(wrapper).vm.$emit('update:modelValue', 20);
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'tickets/resolver',
      expect.anything()
    );
    expect(garantiaOpen).toHaveBeenCalledWith(
      expect.objectContaining({ id: 7 }),
      20,
      {
        productos: [],
        producto_nombre: 'Sofá Modular',
        producto_referencia: 'SOF-123',
        ciudad_nombre: 'Manizales',
        detalle_nombre: '',
        radicado: '#3',
        cliente_nombre: '',
        resultado_nombre: 'Procede garantía',
      }
    );
  });

  it('el enlace "Ir a Decisiones" navega a la cola de decisiones', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      resultado_propuesto_id: 20,
    };
    catalogosRef.value = { resultados };

    const wrapper = montar();
    const btn = wrapper
      .findAllComponents(Button)
      .find(b => b.props('label') === 'TICKETS.RESOLVER.GO_TO_DECISIONS');
    await btn.vm.$emit('click');

    expect(routerPush).toHaveBeenCalledWith({
      name: 'helic3_pqr_decisiones',
      params: { accountId: '1' },
    });
  });
});

describe('PqrDetailPage.vue — ficha editable (MAN-03)', () => {
  // Abre edición y devuelve el <Input> de un campo por su label (clave i18n cruda).
  const abrirYCampo = async (wrapper, labelKey) => {
    const btnEditar = wrapper
      .findAllComponents(Button)
      .find(b => b.props('label') === 'TICKETS.DATA.EDIT');
    await btnEditar.vm.$emit('click');
    await wrapper.vm.$nextTick();
    return wrapper
      .findAllComponents(Input)
      .find(i => i.props('label') === labelKey);
  };

  it('en modo lectura no muestra el formulario', () => {
    expedienteRef.value = { ...expedienteBase, garantia: null, datos: {} };
    expect(montar().find('form').exists()).toBe(false);
  });

  it('guarda SOLO el campo que el operador cambió (no re-sella como humano el resto)', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: {
        cedula: { valor: '123', fuente: 'ia' },
        ciudad: { valor: 'Pereira', fuente: 'erp' },
      },
    };

    const wrapper = montar();
    const inputCedula = await abrirYCampo(
      wrapper,
      'TICKETS.DATA.FIELDS.CEDULA'
    );
    expect(wrapper.find('form').exists()).toBe(true);

    // el operador solo corrige la cédula; ciudad (fuente erp) la deja igual
    await inputCedula.vm.$emit('update:modelValue', '456');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    // se manda EXCLUSIVAMENTE la cédula; ciudad no viaja, así conserva su fuente erp
    expect(dispatch).toHaveBeenCalledWith('tickets/registrarDatos', {
      id: 7,
      datos: { cedula: '456' },
    });
    expect(dispatch).toHaveBeenCalledWith('pqrInbox/fetchOne', 7);
  });

  it('si no se cambió nada, no llama al backend y cierra la edición', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: { cedula: { valor: '123', fuente: 'ia' } },
    };

    const wrapper = montar();
    await abrirYCampo(wrapper, 'TICKETS.DATA.FIELDS.CEDULA'); // abre sin tocar nada
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'tickets/registrarDatos',
      expect.anything()
    );
    expect(wrapper.find('form').exists()).toBe(false); // volvió a lectura
  });

  it('recorta los espacios del valor antes de guardarlo', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: { cedula: { valor: '123', fuente: 'ia' } },
    };

    const wrapper = montar();
    const inputCedula = await abrirYCampo(
      wrapper,
      'TICKETS.DATA.FIELDS.CEDULA'
    );
    await inputCedula.vm.$emit('update:modelValue', '  456  ');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/registrarDatos', {
      id: 7,
      datos: { cedula: '456' },
    });
  });

  it('un cambio que es solo espacios no cuenta como cambio', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: { cedula: { valor: '123', fuente: 'ia' } },
    };

    const wrapper = montar();
    const inputCedula = await abrirYCampo(
      wrapper,
      'TICKETS.DATA.FIELDS.CEDULA'
    );
    await inputCedula.vm.$emit('update:modelValue', '123 '); // mismo contenido + espacio
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).not.toHaveBeenCalledWith(
      'tickets/registrarDatos',
      expect.anything()
    );
  });

  // GAR-06: la garantia no se abre sin detalle, asi que se completa aqui.
  it('guarda el detalle tipificado elegido del catalogo (GAR-06)', async () => {
    catalogosRef.value = {
      resultados: [],
      detalles_tipificados: [{ id: 3, nombre: 'Producto mal pintado' }],
    };
    expedienteRef.value = { ...expedienteBase, garantia: null, datos: {} };

    const wrapper = montar();
    await abrirYCampo(wrapper, 'TICKETS.DATA.FIELDS.CEDULA');
    const selectDetalle = wrapper.find('[data-testid="select-detalle-ficha"]');
    await wrapper
      .findAllComponents(Select)
      .find(s => s.element === selectDetalle.element)
      .vm.$emit('update:modelValue', 3);
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/registrarDatos', {
      id: 7,
      datos: { detalle_tipificado_id: 3 },
    });
  });
});

describe('PqrDetailPage.vue — observación del caso (DET-02)', () => {
  const abrirEdicion = async wrapper => {
    const btn = wrapper
      .findAllComponents(Button)
      .find(b => b.props('label') === 'TICKETS.DATA.EDIT');
    await btn.vm.$emit('click');
    await wrapper.vm.$nextTick();
  };

  it('muestra la observación (description) y ya no la fila "Detalle"', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      description: 'Llegó rayado\nen el cabecero',
      datos: {},
    };

    const texto = montar().text();
    expect(texto).toContain('TICKETS.DATA.FIELDS.OBSERVACION');
    expect(texto).toContain('Llegó rayado');
    expect(texto).not.toContain('TICKETS.DATA.FIELDS.DETALLE'); // la fila Detalle desapareció
  });

  it('sin observación muestra "Sin observación"', () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      description: '',
      datos: {},
    };

    expect(montar().text()).toContain('TICKETS.DATA.SIN_OBSERVACION');
  });

  it('editar la observación la guarda por tickets/update (solo si cambió)', async () => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      description: 'vieja',
      datos: {},
    };

    const wrapper = montar();
    await abrirEdicion(wrapper);
    await wrapper
      .find('[data-testid="textarea-observacion"]')
      .setValue('nueva observación');
    await wrapper.find('form').trigger('submit');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('tickets/update', {
      id: 7,
      description: 'nueva observación',
    });
  });
});

describe('PqrDetailPage.vue — aviso de amparo de garantía vencido (GAR)', () => {
  const resultadoGarantia = [
    { id: 20, nombre: 'Procede garantía', abre_garantia: true },
  ];
  // Dispara "Procede garantía" (abre_garantia) sobre un expediente con factura_fecha.
  const resolverConFactura = async facturaFecha => {
    expedienteRef.value = {
      ...expedienteBase,
      garantia: null,
      datos: { factura_fecha: { valor: facturaFecha, fuente: 'erp' } },
    };
    const wrapper = montar();
    await selectResolver(wrapper).vm.$emit('update:modelValue', 20);
    await flushPromises();
  };

  it('avisa cuando la factura ya superó el amparo (factura vieja + 12 meses < hoy)', async () => {
    catalogosRef.value = { resultados: resultadoGarantia, amparo_garantia_meses: 12 };

    await resolverConFactura('2020-01-01');

    // el diálogo se abre igual (es aviso, no bloqueo) y además sale el toast,
    // con la fecha ya en dd/mm/aaaa (como el resto del módulo)
    expect(garantiaOpen).toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalledWith(
      'TICKETS.RESOLVER.AMPARO_VENCIDO {"fecha":"01/01/2020","meses":12}'
    );
  });

  it('NO avisa cuando la factura sigue dentro del amparo', async () => {
    catalogosRef.value = { resultados: resultadoGarantia, amparo_garantia_meses: 12 };

    // factura de hoy + 12 meses siempre cae en el futuro: fecha dinámica para que el
    // test no se vuelva una bomba de tiempo cuando el reloj avance.
    const hoy = new Date().toISOString().slice(0, 10);
    await resolverConFactura(hoy);

    expect(garantiaOpen).toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('NO avisa si no hay amparo configurado o falta la fecha de factura', async () => {
    catalogosRef.value = { resultados: resultadoGarantia }; // sin amparo_garantia_meses

    await resolverConFactura('2020-01-01');

    expect(useAlert).not.toHaveBeenCalled();
  });
});
