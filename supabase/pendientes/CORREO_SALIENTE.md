# Pendiente: Reply-To y SPF del correo saliente

Fecha de la nota: 2026-08-21. Sale de revisar los DNS al preparar la ficha de
Google Play. **No bloquea builds ni la publicación.**

## El estado real, medido con `dig`

| | `somosaura.app` | `somosaurapass.com` |
|---|---|---|
| **MX** (puede recibir) | ✅ ImprovMX (reenvío) | ❌ **ninguno** |
| **SPF** | ✅ `v=spf1 include:spf.improvmx.com ~all` | ❌ **ninguno** |
| **DKIM** (Resend) | — | ✅ `resend._domainkey` |
| **DMARC** | `p=none` | `p=none` |

Los dos dominios existen y resuelven. `somosaurapass.com` apunta a GitHub Pages
(185.199.x), que sirve la web.

## Qué está BIEN y no hay que tocar

`privacy.html`, `eliminar-cuenta.html` y `support.html` usan
**`hola@somosaura.app`**, que es el que **sí recibe** (reenvía por ImprovMX).
Es el correcto para Google y Apple, que entran a esas páginas.

> En su momento se sospechó lo contrario (que ese dominio estaba muerto y había
> que cambiarlo por `@somosaurapass.com`). Los DNS dicen exactamente lo
> opuesto. No cambiar las páginas.

## Los dos temas a resolver

### 1. Nadie puede responder los mails de la app

Todas las edge functions mandan con
`AURA_FROM_EMAIL = 'Aura <hola@somosaurapass.com>'`, y ese dominio **no tiene
MX**. Si una alumna o un estudio le da "Responder" a un mail de Aura
(confirmación de reserva, aviso de cobro, reporte mensual, gift card), el
correo **rebota**.

Dos salidas:

- **Agregar `Reply-To`** en las llamadas a Resend, apuntando a
  `hola@somosaura.app`. Es el cambio más chico y no toca DNS. Hay que tocarlo
  en todas las functions que mandan mail: `email-regalo`, `aviso-alumnos-email`,
  `aviso-cobro-manana`, `reporte-mensual-estudios`,
  `nueva-reserva-estudio-email`, `email-confirmacion`.
- **Ponerle MX a `somosaurapass.com`** (por ejemplo el mismo ImprovMX) para que
  la dirección remitente también reciba. Deja todo bajo un solo dominio.

### 2. Falta el SPF de `somosaurapass.com`

El dominio **no tiene ningún registro TXT** más allá del DKIM. Resend manda
desde ahí y el DKIM autentica, así que con DMARC en `p=none` los mails no se
rechazan — pero la ausencia de SPF le pega a la entregabilidad en Gmail y
Outlook (más chances de caer en spam).

Se arregla agregando un TXT en el DNS de `somosaurapass.com`:

```
v=spf1 include:_spf.resend.com ~all
```

(Confirmar el `include` exacto en el panel de Resend, en la pantalla de
verificación del dominio.)

### Extra, si se quiere endurecer

Con SPF + DKIM funcionando, subir DMARC de `p=none` a `p=quarantine` mejora la
protección contra suplantación. **No hacerlo antes** de tener el SPF, o se
empiezan a marcar como spam los mails propios.

## Cómo verificar cuando se resuelva

```bash
dig +short MX  somosaurapass.com          # deberia devolver algo
dig +short TXT somosaurapass.com          # deberia incluir v=spf1
dig +short TXT resend._domainkey.somosaurapass.com
```

Y una prueba real: mandarse una reserva a uno mismo y darle "Responder".
