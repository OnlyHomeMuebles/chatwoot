// Detalle de un expediente: incluye semaforo y dias_habiles_restantes, que el
// listado omite y solo llegan por show (API-02).
export const ticketDetalle = {
  id: 7,
  display_id: 3,
  title: 'Garantia de sofa',
  status: 'open',
  conversation_id: 42,
  numero_radicado: 'PQR-000003',
  semaforo: 'amarillo',
  dias_habiles_restantes: 2,
  reloj_detenido: false,
};

// Respuesta de catalogos#show (API-01) para poblar los selectores del panel.
export const catalogosData = {
  tipos: [{ id: 1, codigo: 'peticion', nombre: 'Peticion' }],
  motivos_pqr: [
    {
      id: 10,
      codigo: 'garantia_producto',
      nombre: 'Garantia de producto',
      categoria: { id: 5, codigo: 'garantia', nombre: 'Garantia' },
    },
  ],
  etapas_pqr: [{ id: 20, codigo: 'nueva', nombre: 'Nueva' }],
  resultados: [{ id: 30, codigo: 'procede', nombre: 'Procede' }],
};
