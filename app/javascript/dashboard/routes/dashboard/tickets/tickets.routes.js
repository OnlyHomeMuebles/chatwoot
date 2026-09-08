import { frontendURL } from 'dashboard/helper/URLHelper.js';

import TicketsPage from './pages/TicketsPage.vue';
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
