import { ref } from 'vue';

/**
 * ERP-15: guarda las facturas + productos del cliente para que el agente elija cual
 * reclama en el wizard. NO consulta por su cuenta: una sola peticion (useErpCliente)
 * trae cliente + facturas y le pasa la lista con `recibir`. Al elegir, llena los campos
 * de la seccion "Compra". Una cedula sin compras no es error (lista vacia).
 *
 * @param {object} form reactive del wizard; `elegir` lo muta con la factura/producto elegidos.
 */
export function useErpFacturas(form) {
  const facturas = ref([]);
  // idle | con_resultados | sin_resultados
  const estado = ref('idle');

  // Recibe las facturas que trajo la consulta del cliente (misma peticion).
  const recibir = lista => {
    facturas.value = lista || [];
    estado.value = facturas.value.length ? 'con_resultados' : 'sin_resultados';
  };

  // El agente marca una factura + producto: va a la seccion "Compra" de la ficha.
  const elegir = (factura, item) => {
    form.numero_orden = factura.numero;
    form.factura_fecha = factura.fecha;
    form.producto_nombre = item.descripcion;
    form.producto_referencia = item.referencia;
  };

  const limpiar = () => {
    facturas.value = [];
    estado.value = 'idle';
  };

  return { facturas, estado, recibir, elegir, limpiar };
}
