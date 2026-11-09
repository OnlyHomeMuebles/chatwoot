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

  // ERP-05: Siesa trae nombre, telefono, correo y direccion; la ciudad llega como codigo (no
  // nombre), asi que por ahora no se llena. Si la consulta encontro al cliente y el campo quedo
  // vacio sin badge, es que Siesa no lo trae: se avisa para que el agente lo llene a mano. No se
  // hardcodea la lista de campos; cuando la ciudad se traduzca (catalogo DANE), le pondra badge y
  // este aviso desaparece solo.
  const sinDato = campo =>
    estado.value === 'encontrado' && !badges[campo] && !form[campo];

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

  // Devuelve las facturas de la misma respuesta (una sola peticion trae cliente + facturas),
  // o null si no hubo respuesta usable (cedula vacia, consulta cancelada), para que el que
  // llama no pise el selector con una lista vacia.
  const consultar = async ({ refrescar = false } = {}) => {
    const cedula = (form.cedula || '').trim();
    if (!cedula) return null;

    estado.value = 'consultando';
    try {
      const respuesta = await run(
        signal => TicketsAPI.consultarErpCliente(cedula, signal, { refrescar }),
        { onAbort: null }
      );
      if (respuesta === null) return null; // la cancelo una consulta mas nueva

      if (respuesta.data.encontrado) {
        llenar(respuesta.data.cliente);
        cedulaExitosa.value = cedula;
        estado.value = 'encontrado';
      } else {
        estado.value = 'no_encontrado';
      }
      return respuesta.data.facturas || [];
    } catch (error) {
      if (isAbortError(error)) return null;
      estado.value =
        error?.response?.status === 422 ? 'cedula_invalida' : 'no_disponible';
      return [];
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
    sinDato,
    consultar,
    alEditar,
    alCambiarCedula,
    consultadoErp,
  };
}
