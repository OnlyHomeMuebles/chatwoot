import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const setColorTheme = isOSOnDarkMode => {
  // VIS-08: Nogal queda OPT-IN hasta pulir los popovers/menus del rail (los menus que
  // aparecen dentro del rail heredan el texto claro y no se leen sobre su fondo claro).
  // Por defecto va el tema NORMAL de Chatwoot. Para probar Nogal: en la consola
  // localStorage.setItem('helic3_nogal', 'on') y recargar. El override vive bajo
  // :root[data-helic3-theme='nogal']:not(.dark), asi que el modo oscuro sigue igual.
  if (LocalStorage.get('helic3_nogal') === 'on') {
    document.documentElement.setAttribute('data-helic3-theme', 'nogal');
  } else {
    document.documentElement.removeAttribute('data-helic3-theme');
  }

  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.body.classList.remove('dark');
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
};
