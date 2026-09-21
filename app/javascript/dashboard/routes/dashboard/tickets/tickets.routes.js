import { frontendURL } from 'dashboard/helper/URLHelper.js';

import TicketsPage from './pages/TicketsPage.vue';
import PqrCatalogosPage from './pages/PqrCatalogosPage.vue';
import PqrDetailPage from './pages/PqrDetailPage.vue';
import PqrDecisionesPage from './pages/PqrDecisionesPage.vue';
import AgentInboxPage from './pages/AgentInboxPage.vue';

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
      // Cola de decisiones (DEC-01). Debe ir antes de la ruta con :id para que
      // "decisiones" no la capture como un id.
      path: frontendURL('accounts/:accountId/helic3/pqr/decisiones'),
      name: 'helic3_pqr_decisiones',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: PqrDecisionesPage,
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
    {
      // Bandeja de supervision del Agente IA (AGT-04): solo los casos que el
      // bot radico, sin editar nada aqui (el flujo real vive en la conversacion).
      path: frontendURL('accounts/:accountId/helic3/agente'),
      name: 'helic3_agente_inbox',
      meta: {
        permissions: ['administrator', 'agent'],
      },
      component: AgentInboxPage,
    },
  ],
};

export default ticketsRoutes;
