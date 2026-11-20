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
  // Indices de LINEA de los productos elegidos (no referencias): una factura puede traer dos
  // lineas con la misma referencia, y por referencia se marcarian/duplicarian juntas.
  const indicesElegidos = ref([]);
  // ERP-18b (CA1): el centro_operacion_nombre del campo lo llenó la factura elegida (badge Siesa).
  const centroEsSiesa = ref(false);

  const recibir = lista => {
    // De la mas reciente a la mas vieja (la fecha es ISO AAAA-MM-DD, compara cronologico).
    facturas.value = [...(lista || [])].sort((a, b) =>
      (b.fecha || '').localeCompare(a.fecha || '')
    );
    estado.value = facturas.value.length ? 'con_resultados' : 'sin_resultados';
  };

  // Productos elegidos como [{nombre, referencia}] para el payload de radicacion, en orden de
  // linea. El backend los vuelve a cruzar contra el cache; aqui solo se manda lo que se marco.
  const productosElegidos = () => {
    const factura = facturas.value.find(f => f.numero === facturaElegida.value);
    if (!factura) return [];
    return [...indicesElegidos.value]
      .sort((a, b) => a - b)
      .map(i => factura.items[i])
      .filter(Boolean)
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

  // Alterna un producto. "Una factura y uno o mas productos": elegir un producto de OTRA
  // factura cambia la factura y reinicia la seleccion (no se mezclan facturas). Quitar el
  // ultimo producto deja la factura sin elegir.
  const alternar = (factura, idx) => {
    if (facturaElegida.value !== factura.numero) {
      facturaElegida.value = factura.numero;
      indicesElegidos.value = [idx];
      // ERP-18b (CA1): el centro viene de la factura elegida. Si Siesa lo trae, llena el campo
      // y prende el badge; si no, respeta lo escrito a mano pero apaga el badge (no debe quedar
      // marcado "Siesa" con el centro de otra factura).
      if (factura.centro_operacion_nombre) {
        form.centro_operacion_nombre = factura.centro_operacion_nombre;
        centroEsSiesa.value = true;
      } else {
        centroEsSiesa.value = false;
      }
    } else if (indicesElegidos.value.includes(idx)) {
      indicesElegidos.value = indicesElegidos.value.filter(i => i !== idx);
      if (!indicesElegidos.value.length) {
        // Jhan #173: sin factura elegida, el badge "Siesa" del centro ya no debe quedar prendido.
        facturaElegida.value = null;
        centroEsSiesa.value = false;
      }
    } else {
      indicesElegidos.value = [...indicesElegidos.value, idx];
    }
    sincronizar();
  };

  const estaElegido = (factura, idx) =>
    facturaElegida.value === factura.numero &&
    indicesElegidos.value.includes(idx);

  // El agente editó el campo del centro: deja de ser "de Siesa" (se quita el badge).
  const alEditarCentro = () => {
    centroEsSiesa.value = false;
  };

  const limpiar = () => {
    facturas.value = [];
    estado.value = 'idle';
    facturaElegida.value = null;
    indicesElegidos.value = [];
    centroEsSiesa.value = false;
  };

  return {
    facturas,
    estado,
    facturaElegida,
    indicesElegidos,
    centroEsSiesa,
    recibir,
    alternar,
    estaElegido,
    productosElegidos,
    alEditarCentro,
    limpiar,
  };
}
