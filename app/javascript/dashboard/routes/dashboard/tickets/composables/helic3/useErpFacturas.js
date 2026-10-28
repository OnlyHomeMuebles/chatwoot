import { ref } from 'vue';

/**
 * ERP-15 (B3): guarda las facturas + productos del cliente y la seleccion del agente, que
 * puede elegir UNA factura y UNO O MAS de sus productos (cada uno sera luego un item de la
 * garantia). No consulta por su cuenta: una sola peticion (useErpCliente) trae cliente +
 * facturas y le pasa la lista con `recibir`. La seleccion mantiene en sincronia los campos
 * sueltos de "Compra" (numero_orden + el primer producto) para lo que lee un solo producto.
 *
 * @param {object} form reactive del wizard; la seleccion lo muta.
 */
export function useErpFacturas(form) {
  const facturas = ref([]);
  // idle | con_resultados | sin_resultados
  const estado = ref('idle');
  const facturaElegida = ref(null); // numero de la factura elegida (una sola)
  const referenciasElegidas = ref([]); // referencias de los productos elegidos de esa factura

  const recibir = lista => {
    facturas.value = lista || [];
    estado.value = facturas.value.length ? 'con_resultados' : 'sin_resultados';
  };

  // Alterna un producto. "Una factura y uno o mas productos": elegir un producto de OTRA
  // factura cambia la factura y reinicia la seleccion (no se mezclan facturas). Quitar el
  // ultimo producto deja la factura sin elegir.
  const alternar = (factura, item) => {
    if (facturaElegida.value !== factura.numero) {
      facturaElegida.value = factura.numero;
      referenciasElegidas.value = [item.referencia];
    } else if (referenciasElegidas.value.includes(item.referencia)) {
      referenciasElegidas.value = referenciasElegidas.value.filter(r => r !== item.referencia);
      if (!referenciasElegidas.value.length) facturaElegida.value = null;
    } else {
      referenciasElegidas.value = [...referenciasElegidas.value, item.referencia];
    }
    sincronizar();
  };

  const estaElegido = (factura, item) =>
    facturaElegida.value === factura.numero &&
    referenciasElegidas.value.includes(item.referencia);

  // Productos elegidos como [{nombre, referencia}] para el payload de radicacion. El backend
  // los vuelve a cruzar contra el cache; aqui solo se manda lo que el agente marco.
  const productosElegidos = () => {
    const factura = facturas.value.find(f => f.numero === facturaElegida.value);
    if (!factura) return [];
    return factura.items
      .filter(item => referenciasElegidas.value.includes(item.referencia))
      .map(item => ({ nombre: item.descripcion, referencia: item.referencia }));
  };

  // Campos sueltos de "Compra" (numero_orden + primer producto + fecha) en sincronia con la
  // seleccion, para la seccion manual y para quien lee un solo producto.
  const sincronizar = () => {
    const factura = facturas.value.find(f => f.numero === facturaElegida.value);
    const primero = productosElegidos()[0];
    form.numero_orden = facturaElegida.value || '';
    form.producto_nombre = primero?.nombre || '';
    form.producto_referencia = primero?.referencia || '';
    if (factura?.fecha) form.factura_fecha = factura.fecha;
  };

  const limpiar = () => {
    facturas.value = [];
    estado.value = 'idle';
    facturaElegida.value = null;
    referenciasElegidas.value = [];
  };

  return {
    facturas,
    estado,
    facturaElegida,
    referenciasElegidas,
    recibir,
    alternar,
    estaElegido,
    productosElegidos,
    limpiar,
  };
}
