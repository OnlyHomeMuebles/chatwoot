// dd/mm/aaaa desde una fecha ISO ('YYYY-MM-DD'), sin pasar por Date (evita
// corrimientos de zona horaria). GAR-09: el aviso de vigencia y la fila "Fecha de
// compra" comparten este formato.
export const fechaDMY = iso =>
  iso ? iso.slice(0, 10).split('-').reverse().join('/') : '';
