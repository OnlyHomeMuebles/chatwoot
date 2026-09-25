import { frontendURL } from 'dashboard/helper/URLHelper';
import PageWrapper from './PageWrapper.vue';
import Index from './Index.vue';
import Editor from './Editor.vue';
import EstadoEnVivo from './EstadoEnVivo.vue';

// H3A-13/14: panel de Agentes IA (modulo propio, a lo ancho). Solo administrador.
export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/agentes-ia'),
      component: PageWrapper,
      children: [
        {
          path: '',
          name: 'agentes_ia_index',
          component: Index,
          meta: { permissions: ['administrator'] },
        },
        {
          path: 'new',
          name: 'agentes_ia_new',
          component: Editor,
          meta: { permissions: ['administrator'] },
        },
        {
          path: ':agenteId/edit',
          name: 'agentes_ia_edit',
          component: Editor,
          meta: { permissions: ['administrator'] },
        },
        {
          path: 'estado-en-vivo',
          name: 'agentes_ia_estado_en_vivo',
          component: EstadoEnVivo,
          meta: { permissions: ['administrator'] },
        },
      ],
    },
  ],
};
