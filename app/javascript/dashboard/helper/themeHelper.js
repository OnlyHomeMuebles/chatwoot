import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

export const setColorTheme = isOSOnDarkMode => {
  // VIS-01: enciende el tema Nogal en toda la instancia. Por defecto 'nogal';
  // apagarlo es quitar este atributo. El override del tema vive bajo
  // :root[data-helic3-theme='nogal']:not(.dark), asi que el modo oscuro sigue igual.
  document.documentElement.setAttribute('data-helic3-theme', 'nogal');

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
