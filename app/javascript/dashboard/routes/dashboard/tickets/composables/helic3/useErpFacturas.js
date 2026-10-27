import { ref } from 'vue';
import TicketsAPI from 'dashboard/api/tickets';
import {
  useAbortableRequest,
  isAbortError,
} from 'dashboard/composables/useAbortableRequest';

/**
 * ERP-15: trae las facturas + productos del cliente por cedula (ERP-08 facturas) para
 * que el agente elija cual reclama en el wizard. Al elegir, llena los campos de la
 * seccion "Compra". El ERP nunca bloquea: si falla, queda `no_disponible` y el agente
 * escribe a mano. Cancela una consulta en vuelo si llega otra (sin respuestas fuera de orden).
 *
 * @param {object} form reactive del wizard; `elegir` lo muta con la factura/producto elegidos.
 */
export function useErpFacturas(form) {
  const { run, abort } = useAbortableRequest();
  const facturas = ref([]);
  // idle | consultando | con_resultados | sin_resultados | no_disponible
  const estado = ref('idle');

  const consultar = async cedula => {
    const valor = (cedula || '').trim();
    if (!valor) return;

    estado.value = 'consultando';
    try {
      const respuesta = await run(
        signal => TicketsAPI.consultarErpFacturas(valor, signal),
        { onAbort: null }
      );
      if (respuesta === null) return; // la cancelo una consulta mas nueva

      facturas.value = respuesta.data.facturas || [];
      estado.value = facturas.value.length ? 'con_resultados' : 'sin_resultados';
    } catch (error) {
      if (isAbortError(error)) return;
      facturas.value = [];
      estado.value = 'no_disponible';
    }
  };

  // El agente marca una factura + producto: va a la seccion "Compra" de la ficha.
  const elegir = (factura, item) => {
    form.numero_orden = factura.numero;
    form.factura_fecha = factura.fecha;
    form.producto_nombre = item.descripcion;
    form.producto_referencia = item.referencia;
  };

  const limpiar = () => {
    abort();
    facturas.value = [];
    estado.value = 'idle';
  };

  return { facturas, estado, consultar, elegir, limpiar };
}
