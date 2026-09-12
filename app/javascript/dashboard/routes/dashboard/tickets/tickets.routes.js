import { frontendURL } from 'dashboard/helper/URLHelper.js';

import TicketsPage from './pages/TicketsPage.vue';
import PqrCatalogosPage from './pages/PqrCatalogosPage.vue';
import PqrDetailPage from './pages/PqrDetailPage.vue';

const ticketsRoutes = {
  routes: [
    {
      path: frontendURL('accounts/:accountId/tickets'),
      name: 'tickets_index',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: TicketsPage,
    },
    {
      // Agentes entran en solo lectura; solo administradores editan (ADM-01)
      path: frontendURL('accounts/:accountId/helic3/catalogos'),
      name: 'helic3_catalogos_admin',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: PqrCatalogosPage,
    },
    {
      // Detalle del expediente (DET-01), con URL compartible.
      path: frontendURL('accounts/:accountId/helic3/pqr/:id'),
      name: 'helic3_pqr_detail',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: PqrDetailPage,
      props: true,
    },
  ],
};

export default ticketsRoutes;
