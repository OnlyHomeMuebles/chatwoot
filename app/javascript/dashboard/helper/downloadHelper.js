import fromUnixTime from 'date-fns/fromUnixTime';
import format from 'date-fns/format';

export const downloadCsvFile = (fileName, content) => {
  const contentType = 'data:text/csv;charset=utf-8;';
  const blob = new Blob([content], { type: contentType });
  const url = URL.createObjectURL(blob);

  const link = document.createElement('a');
  link.setAttribute('download', fileName);
  link.setAttribute('href', url);
  link.click();
  return link;
};

// IND-05: nombre real que mando el backend en el header (indicadores-{tab}-
// {seccion}-{YYYY-MM}.csv) en vez de reconstruirlo en el cliente, para no
// desalinearse si el mes cambia entre el reloj del navegador y el del server.
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

export const generateFileName = ({ type, to, businessHours = false }) => {
  let name = `${type}-report-${format(fromUnixTime(to), 'dd-MM-yyyy')}`;
  if (businessHours) {
    name = `${name}-business-hours`;
  }
  return `${name}.csv`;
};
