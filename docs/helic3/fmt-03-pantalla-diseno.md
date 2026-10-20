# FMT-03 · Pestaña «Formatos» (subir, vista previa, activar) — Diseño

> Spec de implementación. Aterriza el ticket "Formatos con plantillas de Karen
> (Semana 3) · §6 FMT-03" contra el frontend real del fork. Verificado el 2026-10-06.
> **Alcance: MVP** (ver §3). Frontend Vue 3.

## 1. Objetivo

Que un administrador (Karen) suba su `.docx`, vea el PDF tal como saldrá y lo active,
sin salir de Catálogos. Un agente lo ve en **solo lectura**. Es lo que se muestra en la demo.

## 2. Rama, base y secuencia

- **Rama:** `feature/FMT-03-pantalla-formatos` (creada desde `feature/FMT-02-plantillas-formato`
  para disponer de la API de FMT-02).
- **Base del ticket:** `integracion/entrega-7-formatos-pdf` con FMT-02 mergeado.
- **Secuencia:** FMT-03 se mergea después de FMT-02 (que a su vez va después de #110).
- **Dependencia:** API de admin de FMT-02 (`helic3/admin/formatos` y `helic3/admin/plantillas`).

## 3. Alcance MVP y fuera de alcance

**Dentro (MVP):** pestaña «Formatos»; tarjeta por formato con su versión activa; subir
`.docx`; vista previa en PDF con **datos de ejemplo**; activar / descartar borrador;
error 422 con marcadores desconocidos + sugerencia; lista plegable de marcadores con
«Copiar»; solo-lectura para agentes.

**Diferido** (el resumen del ticket los marca recortables; se harán si queda tiempo):
- Vista previa con un **caso real** (número de expediente + `item_id`) — ticket §6.5.
- **Historial** de versiones en pantalla — ticket §6.7. (El historial se guarda en BD
  igual; solo no se muestra todavía.)

**Fuera de alcance (del ticket):** editar el `.docx` en el navegador; comparar dos
versiones lado a lado; generar desde el expediente (FMT-04).

## 4. Estructura de archivos (todos nuevos salvo PqrCatalogosPage)

| Archivo | Papel |
| --- | --- |
| `app/javascript/dashboard/routes/dashboard/tickets/pages/PqrCatalogosPage.vue` | **Modificar**: añadir la entrada «Formatos» en su menú lateral interno y montar el panel. |
| `app/javascript/dashboard/routes/dashboard/tickets/components/formatos/FormatosPanel.vue` | Panel: lista de tarjetas + lista de marcadores + vista previa. |
| `app/javascript/dashboard/routes/dashboard/tickets/components/formatos/FormatoCard.vue` | Tarjeta de un formato (estado + acciones). |
| `app/javascript/dashboard/api/helic3/formatos.js` | Cliente de API (extiende `ApiClient`). |
| `app/javascript/dashboard/store/modules/helic3Formatos.js` | Módulo Vuex. |
| `app/javascript/dashboard/store/index.js` | **Modificar**: registrar el módulo (archivo del proyecto, no upstream de FMT). |
| `app/javascript/dashboard/store/mutation-types.js` | **Modificar**: constantes `SET_HELIC3_FORMATOS...`. |
| `app/javascript/dashboard/i18n/locale/es/tickets.json` y `en/tickets.json` | Textos `TICKETS.FORMATOS.*`. |
| `.../components/formatos/specs/FormatosPanel.spec.js` | Spec Vitest. |

> No se toca `settings.routes.js`, `tickets.routes.js`, `Sidebar.vue`, `package.json` ni
> `pnpm-lock.yaml`. FMT-03 es una **pestaña interna** de PqrCatalogosPage, no una ruta nueva.

## 5. Cliente de API — `api/helic3/formatos.js`

Clase que extiende `ApiClient` (patrón de `api/pqrCatalogos.js`), base `helic3/admin`:

```js
class Helic3FormatosAPI extends ApiClient {
  constructor() { super('helic3/admin', { accountScoped: true }); }

  listFormatos()                   { return axios.get(`${this.url}/formatos`); }
  marcadores()                     { return axios.get(`${this.url}/formatos/marcadores`); }
  subirPlantilla(formatoId, fd)    { return axios.post(`${this.url}/formatos/${formatoId}/plantillas`, fd,
                                       { headers: { 'Content-Type': 'multipart/form-data' } }); }
  vistaPrevia(plantillaId, formato = 'pdf') {
    return axios.get(`${this.url}/plantillas/${plantillaId}/vista_previa`,
                     { params: { formato }, responseType: 'blob' });
  }
  descargarOriginal(plantillaId)   { return axios.get(`${this.url}/plantillas/${plantillaId}/original`,
                                       { responseType: 'blob' }); }
  activar(plantillaId)             { return axios.post(`${this.url}/plantillas/${plantillaId}/activar`); }
  descartar(plantillaId)           { return axios.delete(`${this.url}/plantillas/${plantillaId}`); }
}
export default new Helic3FormatosAPI();
```

- La vista previa y la descarga usan `responseType: 'blob'` **a propósito**: la
  autenticación va en las cabeceras (un `iframe`/`<a href>` directo a la API no la
  llevaría). El componente crea una URL `blob:` con `URL.createObjectURL`.

## 6. Store — `store/modules/helic3Formatos.js`

Mismo patrón que `pqrCatalogos.js`:
- **state:** `formatos: []`, `marcadores: {}`, `uiFlags: { isFetching, isSaving }`.
- **actions:** `fetchFormatos`, `fetchMarcadores`, `subirPlantilla({ formatoId, formData })`,
  `activar(plantillaId)`, `descartar(plantillaId)`. Las de escritura levantan `isSaving`,
  y **recargan** `fetchFormatos` al terminar. `subirPlantilla` relanza el error para que
  el componente lea el 422 (cuerpo con `errores`).
- **getters:** `getFormatos`, `getMarcadores`, `getUIFlags`.
- **mutations:** `SET_HELIC3_FORMATOS`, `SET_HELIC3_MARCADORES`, `SET_HELIC3_FORMATOS_UI_FLAG`.
- Registrar en `store/index.js` (import + dentro de `modules`) y las constantes en `mutation-types.js`.

## 7. UI

### 7.1 Integración en `PqrCatalogosPage.vue`
Esa página ya tiene un menú lateral interno (tipos de catálogo + «Parámetros»). Se añade
una entrada «Formatos» con el mismo mecanismo (`tabActivo`). Cuando `tabActivo === 'formatos'`
se renderiza `<FormatosPanel />` en el área de contenido. Nada más de esa página cambia.

### 7.2 `FormatosPanel.vue`
- `onMounted`: `fetchFormatos` + `fetchMarcadores`.
- Renderiza un `FormatoCard` por formato, la lista plegable de marcadores, y el área de
  vista previa (iframe) cuando hay un PDF cargado.
- `esAdmin = computed(() => currentRole === 'administrator')` (getter `getCurrentRole`),
  se pasa a las tarjetas para gatear acciones.
- Maneja la vista previa: al recibir el blob, `URL.createObjectURL`; guarda la URL para el
  `iframe`; revoca la anterior con `URL.revokeObjectURL`. Botón «Abrir en pestaña nueva»
  como fallback.
- `conAviso(async () => {...})` traduce 401 → `FORBIDDEN` y el resto a un aviso (patrón de
  PqrCatalogosPage).

### 7.3 `FormatoCard.vue`
- Props: `formato` (con `codigo`, `nombre`, `activa_id`, `versiones`), `esAdmin`.
- Muestra: nombre; si hay activa, su versión + fecha + quién; si no, «Aún no tiene
  plantilla; no se puede generar».
- Acciones (solo admin): «Subir nueva versión» (abre el `<input type=file accept=".docx">`
  oculto), «Descargar .docx» (de la activa), «Activar esta versión» (con confirmación vía
  `Dialog`), «Descartar borrador».
- Si la subida devuelve **422**, la tarjeta muestra la lista de marcadores desconocidos y
  su sugerencia (del cuerpo de la respuesta) y no cambia nada más.
- Emite eventos al panel (`subir`, `activar`, `descartar`, `previsualizar`) para que el
  panel llame al store (las tarjetas no hablan con el store directamente).

### 7.4 Marcadores con «Copiar»
Lista plegable del diccionario (`getMarcadores`): por cada uno, nombre, descripción,
ejemplo y un botón «Copiar» → `navigator.clipboard.writeText('{{NOMBRE}}')` + aviso.

## 8. i18n — `TICKETS.FORMATOS.*`
En `tickets.json` (es y en), dentro de `TICKETS`, una sección `FORMATOS` con: `TITLE`,
`SIN_PLANTILLA`, `SUBIR`, `DESCARGAR`, `ACTIVAR`, `ACTIVAR_CONFIRMACION`, `DESCARTAR`,
`VISTA_PREVIA`, `ABRIR_NUEVA_PESTANA`, `MARCADORES.{TITLE,COPIAR,COPIADO}`,
`DESCONOCIDOS`, `SOLO_LECTURA`, `GUARDADO`, `FORBIDDEN`, `ERROR`. (Nombres exactos se
fijan en el plan.)

## 9. Permisos
- La ruta de PqrCatalogosPage ya permite `administrator` y `agent` (lectura).
- `esAdmin` gatea subir/activar/descartar en la UI; el backend además responde 401 a un
  agente que intente escribir (se traduce a `FORBIDDEN`).

## 10. Pruebas (Vitest, store mockeado) — CA6
`FormatosPanel.spec.js`: mockea `dashboard/composables/store` (`dispatch` + `useMapGetter`),
`vue-i18n` (`t` devuelve la clave) y `navigator.clipboard`. Cubre:
- pinta una tarjeta por formato (con y sin activa),
- un 422 muestra el/los marcadores desconocidos y su sugerencia,
- el flujo subir → vista previa → activar (con la API/store simulada),
- un agente (no admin) no ve los botones de escritura,
- «Copiar» llama a `navigator.clipboard.writeText` con `{{CLIENTE}}`.

Selectores por `data-testid`.

## 11. Criterios de aceptación (MVP)
1. Admin: subir el `.docx` del No.3, ver el PDF en la página y activarlo; la tarjeta queda
   con la versión nueva. (Capturas/el video en el PR.)
2. Un `.docx` con `{{CLEINTE}}` muestra el marcador y la sugerencia; la activa no cambia.
3. «Copiar» deja `{{CLIENTE}}` en el portapapeles.
4. Un agente sin rol admin no ve subir/activar/descartar.
5. Spec del panel (Vitest) verde: tarjetas, 422 y flujo subir→vista previa→activar.
6. Capturas con tema Nogal y tema por defecto.
7. Ningún paquete npm nuevo; ningún archivo upstream tocado.

> (Los CA del ticket sobre vista previa con caso real quedan para la fase diferida.)

## 12. Frontera y verificación
- Sin paquetes npm nuevos; no se tocan `settings.routes.js`, `tickets.routes.js`,
  `Sidebar.vue`, `package.json`, `pnpm-lock.yaml`.
- Comandos:
  ```
  pnpm test app/javascript/dashboard/routes/dashboard/tickets/components/formatos/
  pnpm eslint app/javascript/dashboard/routes/dashboard/tickets/ app/javascript/dashboard/api/helic3/
  git diff --name-only origin/dev -- package.json pnpm-lock.yaml app/javascript/dashboard/routes/dashboard/settings/settings.routes.js   # vacío
  ```
- Gotcha vite: en Windows/Docker el dev server no detecta cambios; reinicio con
  `docker compose restart vite` para la verificación visual.

## 13. Orden de implementación sugerido
1. `api/helic3/formatos.js` + `store/modules/helic3Formatos.js` (+ registro) + i18n.
2. `FormatoCard.vue` (tarjeta, acciones, 422) + su spec.
3. `FormatosPanel.vue` (tarjetas + marcadores + vista previa) + su spec.
4. Integrar la pestaña en `PqrCatalogosPage.vue`.
5. `pnpm eslint` + `pnpm test` + verificación visual (vite) + capturas.
