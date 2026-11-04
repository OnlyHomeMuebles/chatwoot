// IND-05: helper de descarga propio del modulo Helic3 (GIT-01, revision de
// Jhan: el helper compartido dashboard/helper/downloadHelper.js es upstream,
// no se toca -- todo lo de Helic3 vive bajo helper/helic3/).
//
// Nombre real que mando el backend en el header (indicadores-{tab}-{seccion}-
// {YYYY-MM}.csv) en vez de reconstruirlo en el cliente, para no desalinearse
// si el mes cambia entre el reloj del navegador y el del server.
export const downloadBlobResponse = (response, fallbackFilename) => {
  const encabezado = response.headers?.['content-disposition'] || '';
  const coincidencia = encabezado.match(/filename="?([^";]+)"?/);
  const url = window.URL.createObjectURL(response.data);

  const link = document.createElement('a');
  link.href = url;
  link.download = coincidencia ? coincidencia[1] : fallbackFilename;
  link.click();
  window.URL.revokeObjectURL(url);
};
