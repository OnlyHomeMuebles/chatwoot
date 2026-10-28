import { reactive, ref } from 'vue';
import TicketsAPI from 'dashboard/api/tickets';
import {
  useAbortableRequest,
  isAbortError,
} from 'dashboard/composables/useAbortableRequest';

// Campos de la ficha que el ERP puede llenar, mapeados al Customer del endpoint (ERP-08).
const CAMPOS = {
  cliente_nombre: 'nombre',
  cliente_telefono: 'telefono',
  cliente_email: 'email',
  ciudad: 'ciudad',
  direccion: 'direccion',
};

/**
 * ERP-11: consulta el cliente por cedula contra el ERP (ERP-08) para autocompletar el
 * wizard. Reglas: solo llena campos vacios o que una consulta anterior lleno y el agente
 * no toco; NUNCA pisa lo que escribio el agente; marca cada campo llenado con un badge
 * "Siesa"; y cancela una consulta en vuelo si llega otra (sin respuestas fuera de orden).
 *
 * @param {object} form reactive del wizard; el composable lo muta al autocompletar.
 */
export function useErpCliente(form) {
  const { run, abort, isPending } = useAbortableRequest();
  // idle | consultando | encontrado | no_encontrado | no_disponible | cedula_invalida
  const estado = ref('idle');
  // cedula de la ultima consulta EXITOSA: con ella se decide si al crear se manda consultado_erp.
  const cedulaExitosa = ref(null);
  // campos que siguen "de Siesa" (los lleno la consulta y el agente no los toco).
  const badges = reactive({});

  const tieneBadge = campo => Boolean(badges[campo]);

  const llenar = cliente => {
    Object.entries(CAMPOS).forEach(([campo, atributo]) => {
      const valor = cliente[atributo];
      if (!valor) return;
      // solo si el campo esta vacio, o ya lo habia puesto el ERP (y nadie lo toco).
      if (!form[campo] || badges[campo]) {
        form[campo] = valor;
        badges[campo] = true;
      }
    });
  };

  const consultar = async ({ refrescar = false } = {}) => {
    const cedula = (form.cedula || '').trim();
    if (!cedula) return;

    estado.value = 'consultando';
    try {
      const respuesta = await run(
        signal => TicketsAPI.consultarErpCliente(cedula, signal, { refrescar }),
        { onAbort: null }
      );
      if (respuesta === null) return; // la cancelo una consulta mas nueva

      if (respuesta.data.encontrado) {
        llenar(respuesta.data.cliente);
        cedulaExitosa.value = cedula;
        estado.value = 'encontrado';
      } else {
        estado.value = 'no_encontrado';
      }
    } catch (error) {
      if (isAbortError(error)) return;
      estado.value =
        error?.response?.status === 422 ? 'cedula_invalida' : 'no_disponible';
    }
  };

  // El agente edito un campo: deja de ser "de Siesa" (se quita el badge).
  const alEditar = campo => {
    delete badges[campo];
  };

  // Cambio la cedula: lo que seguia con badge "Siesa" se vacia (no mezclar dos clientes)
  // y se cancela cualquier consulta en vuelo.
  const alCambiarCedula = () => {
    abort();
    estado.value = 'idle';
    cedulaExitosa.value = null;
    Object.keys(badges).forEach(campo => {
      form[campo] = '';
      delete badges[campo];
    });
  };

  // Al crear, solo se manda consultado_erp si la ultima consulta exitosa fue con la
  // cedula que esta ahora en el campo (no una vieja).
  const consultadoErp = () =>
    cedulaExitosa.value !== null &&
    cedulaExitosa.value === (form.cedula || '').trim();

  return {
    estado,
    isPending,
    tieneBadge,
    consultar,
    alEditar,
    alCambiarCedula,
    consultadoErp,
  };
}
