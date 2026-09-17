import { frontendURL } from 'dashboard/helper/URLHelper.js';

import TicketsPage from './pages/TicketsPage.vue';

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
  ],
};

export default ticketsRoutes;
