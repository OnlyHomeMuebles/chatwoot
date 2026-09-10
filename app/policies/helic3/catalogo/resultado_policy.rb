# Quien puede FIRMAR cada resultado (RES-01). Este chequeo NO puede vivir en
# TicketPolicy#resolver?: Pundit autoriza el ticket antes de saber que resultado
# se aplica, asi que el limite fino tiene que correr sobre el resultado ya
# cargado. El controlador llama authorize(resultado, :aplicar?) despues de
# resolverlo contra la cuenta.
#
# El namespace calca la clase del record (Helic3::Catalogo::Resultado): asi
# Pundit encuentra esta policy sola, sin decirselo.
#
# requiere_admin es un valor de CATALOGO, no una regla en codigo: default true =
# solo admin, como hoy; Karen lo afloja por resultado desde ADM-01 sin desplegar.
# La puerta general (ser participante del expediente) ya la valido
# TicketPolicy#resolver?; aqui solo se decide si ademas hace falta ser admin.
class Helic3::Catalogo::ResultadoPolicy < ApplicationPolicy
  def aplicar?
    return @account_user.administrator? if record.requiere_admin?

    true
  end
end

Helic3::Catalogo::ResultadoPolicy.prepend_mod_with('Helic3::Catalogo::ResultadoPolicy')
