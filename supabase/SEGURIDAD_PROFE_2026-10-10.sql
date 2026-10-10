-- La profe deja de ver y tocar la plata del estudio.
-- APLICADO EN PRODUCCIÓN el 2026-10-10. Copia de lo que se corrió.
--
-- EL PROBLEMA, MEDIDO
--
-- `es_miembro_de_estudio(estudio_id)` devuelve true para CUALQUIER fila de
-- `estudio_admins`, sin mirar `rol`. Quince policies cuelgan de ella, y entre
-- ellas estaban las de cobro. Probado con la cuenta real de la profe de BB
-- Estudio Colegiales, en una transacción revertida:
--
--   leer estudios_datos_cobro .......... vio 1 fila, con el CBU
--   update ... set alias ............... escribió 1 fila
--
-- (verificado después: el alias volvió a null y el CBU quedó intacto).
--
-- Lo único que frenaba a la profe era el redirect del cliente en
-- `app_router.dart`, que no protege nada contra una llamada directa a la API
-- ni contra un build viejo. Hay 2 profes reales: BB Estudio Colegiales y
-- Sitio Pilates.
--
-- Y una segunda puerta, por el mismo agujero: las 4 policies de
-- `horarios_fijos` también eran `es_miembro_de_estudio`, pero el DELETE de
-- `clases` SÍ exige rol ('estudio','admin_estudio'), y el trigger
-- `horarios_fijos_borrar_ordenado` NO es SECURITY DEFINER (prosecdef=false).
-- O sea: la profe borraba el horario, el DELETE de clases que hace el trigger
-- se lo filtraba RLS a 0 filas sin tirar error, y como la FK
-- `clases_horario_fijo_id_fkey` es ON DELETE SET NULL (confdeltype='n'), las
-- clases quedaban publicadas, reservables y sin dueño.
--
-- POR QUÉ NO SE TOCA `es_miembro_de_estudio`
--
-- Porque la usan 15 policies en 9 tablas, y la mayoría son acceso legítimo de
-- la profe: ver las clases, ver el estudio, ver a los otros miembros, leer
-- sus notificaciones, ver los precios de los servicios. Cambiarle el
-- significado a la función le rompería todo eso de una. Es el error del 20/8,
-- cuando validar un guard sólo contra el exploit rompió 2 de 5 usos buenos.
--
-- Así que la función queda como está y se agrega una hermana más estricta,
-- que se aplica SÓLO a las policies de plata y de estructura de la grilla.

-- El conjunto de roles es el mismo que ya usan las policies de escritura de
-- `clases` ('estudio','admin_estudio'), para no inventar un tercer criterio.
create or replace function public.es_admin_de_estudio(p_estudio_id bigint)
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$
  select exists (
           select 1 from public.admin_users where user_id = auth.uid()
         )
      or exists (
           select 1 from public.estudio_admins
            where estudio_id = p_estudio_id
              and usuario_id = auth.uid()
              and rol in ('estudio', 'admin_estudio')
         );
$$;

-- Se usa `alter policy` y no drop+create a propósito: preserva el comando y
-- los roles de cada una. No es decorativo — "estudio ve sus liquidaciones"
-- aplica a PUBLIC y no a `authenticated`, y un recreate a mano se lo comía.

-- 1. LOS DATOS DE COBRO (titular, banco, alias, CBU).
--
-- Ninguna pantalla que la profe pueda abrir los toca: `_rutasProfe` es sólo
-- ['/estudio/clases', '/estudio/asistencia'], y el upsert vive en
-- `perfil_estudio_screen`, fuera de esas dos.
alter policy datos_cobro_select on public.estudios_datos_cobro
  using (is_admin() or public.es_admin_de_estudio((estudio_id)::bigint));

alter policy datos_cobro_insert on public.estudios_datos_cobro
  with check (is_admin() or public.es_admin_de_estudio((estudio_id)::bigint));

alter policy datos_cobro_update on public.estudios_datos_cobro
  using (is_admin() or public.es_admin_de_estudio((estudio_id)::bigint))
  with check (is_admin() or public.es_admin_de_estudio((estudio_id)::bigint));

-- 2. LO QUE AURA LE PAGA AL ESTUDIO.
alter policy "estudio ve sus liquidaciones" on public.liquidaciones
  using (public.es_admin_de_estudio(estudio_id));

alter policy "estudio ve sus correcciones" on public.liquidaciones_correcciones
  using (public.es_admin_de_estudio(estudio_id));

-- 3. LA ESTRUCTURA DE LA GRILLA.
--
-- El SELECT NO se toca: la profe necesita ver la grilla en /estudio/clases,
-- que es una de sus dos pantallas. Lo que se le cierra es cambiarla.
--
-- Esto cierra además el camino de las clases huérfanas: después de esto, el
-- único que puede borrar un horario fijo es alguien que TAMBIÉN puede borrar
-- las clases, así que el trigger nunca más corre a medias.
alter policy horarios_fijos_insert_own on public.horarios_fijos
  with check (public.es_admin_de_estudio(estudio_id));

alter policy horarios_fijos_update_own on public.horarios_fijos
  using (public.es_admin_de_estudio(estudio_id))
  with check (public.es_admin_de_estudio(estudio_id));

alter policy horarios_fijos_delete_own on public.horarios_fijos
  using (public.es_admin_de_estudio(estudio_id));

-- LO QUE NO SE TOCA, Y POR QUÉ
--
-- `clases` (insert/update): la migración 20260724160000_profe_gestiona_clases
-- le dio ese permiso a la profe a propósito. Es su trabajo.
-- `clases` (select), `estudios`, `estudio_admins`, `notificaciones_estudio`,
-- `estudio_servicios_precio`: acceso legítimo de la profe, sigue igual.
--
-- QUEDA PENDIENTE (anotado, no urgente después de esto)
--
-- `horarios_fijos_borrar_ordenado` sigue sin ser SECURITY DEFINER. Con las
-- policies de arriba ya no hay nadie que pueda borrar un horario sin poder
-- borrar sus clases, así que el caso roto no tiene cómo darse. Pero la
-- fragilidad sigue ahí si algún día se agrega otro rol.

-- Chequeo previo que se corrió antes de aplicar: ningún estudio se queda sin
-- poder tocar su CBU. Los 25 estudios con miembros tienen al menos un
-- admin_estudio, y los dos que tienen profe tienen además 2 admins cada uno.
