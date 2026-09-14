import { frontendURL } from 'dashboard/helper/URLHelper.js';

import TicketsPage from './pages/TicketsPage.vue';
import PqrCatalogosPage from './pages/PqrCatalogosPage.vue';
import PqrDecisionesPage from './pages/PqrDecisionesPage.vue';

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
      // Cola de decisiones (DEC-01). Agentes la ven; aprobar lo gatea la política
      // de resolución (un resultado que exige admin rechaza al agente con aviso).
      path: frontendURL('accounts/:accountId/helic3/pqr/decisiones'),
      name: 'helic3_pqr_decisiones',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: PqrDecisionesPage,
    },
  ],
};

export default ticketsRoutes;
