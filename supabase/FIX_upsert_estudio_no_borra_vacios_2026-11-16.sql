-- 16/11/2026 · Editar un estudio desde el backoffice ya no borra los campos
-- que quedan vacíos (pedido de Sofía). Antes el UPDATE hacía barrio = p_barrio,
-- lat = p_lat, etc.: un campo vacío o una coordenada mal tipeada (Dart manda
-- null si no la entiende) borraba lo que había, y una fecha_inicio_cobro vacía
-- significa "cobra 30% desde siempre".
--
-- Ahora, al EDITAR, vacío = "no tocar" para: barrio, dirección, descripción,
-- foto, instagram, whatsapp, web, lat, lng, fecha_inicio_cobro y CBU.
-- Contra: desde el formulario ya no se puede borrar uno de esos a propósito;
-- eso se hace a mano. Crear un estudio sigue igual.
--
-- ROLLBACK: supabase/ROLLBACK_admin_upsert_estudio_2026-11-16.sql (la versión
-- viva hasta hoy, copiada de pg_get_functiondef).

CREATE OR REPLACE FUNCTION public.admin_upsert_estudio(p_estudio_id bigint DEFAULT NULL::bigint, p_nombre text DEFAULT NULL::text, p_categoria text DEFAULT NULL::text, p_barrio text DEFAULT NULL::text, p_direccion text DEFAULT NULL::text, p_descripcion text DEFAULT NULL::text, p_foto_url text DEFAULT NULL::text, p_instagram text DEFAULT NULL::text, p_whatsapp text DEFAULT NULL::text, p_web text DEFAULT NULL::text, p_lat double precision DEFAULT NULL::double precision, p_lng double precision DEFAULT NULL::double precision, p_activo boolean DEFAULT true, p_comision numeric DEFAULT NULL::numeric, p_fecha_inicio_cobro date DEFAULT NULL::date, p_comision_workshop integer DEFAULT NULL::integer, p_cbu text DEFAULT NULL::text, p_tipo_precio text DEFAULT NULL::text, p_creditos_min integer DEFAULT NULL::integer, p_creditos_max integer DEFAULT NULL::integer, p_categorias text[] DEFAULT NULL::text[], p_valor_credito integer DEFAULT '-1'::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_categorias text[];
  v_id bigint;
  v_cbu text := nullif(trim(coalesce(p_cbu, '')), '');
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_valor_credito is not null and p_valor_credito <> -1
     and (p_valor_credito <= 0 or p_valor_credito > 1000000) then
    raise exception 'Valor del crédito inválido (mayor a 0, o null para seguir el global)';
  end if;

  v_categorias := coalesce(
    nullif(
      array(select distinct trim(c) from unnest(coalesce(p_categorias, '{}')) as c
             where trim(coalesce(c, '')) <> ''),
      '{}'),
    case when trim(coalesce(p_categoria, '')) <> ''
         then array[trim(p_categoria)] else '{}' end);

  if p_estudio_id is null then
    insert into public.estudios (
      nombre, categorias, barrio, direccion, descripcion, foto_url,
      instagram, whatsapp, web, lat, lng, activo,
      fecha_inicio_cobro, tipo_precio, creditos_min, creditos_max
    ) values (
      p_nombre, v_categorias, p_barrio, p_direccion, p_descripcion, p_foto_url,
      p_instagram, p_whatsapp, p_web, p_lat, p_lng, coalesce(p_activo, true),
      p_fecha_inicio_cobro,
      coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), 'rango'),
      p_creditos_min, p_creditos_max
    ) returning id into v_id;

    perform public.log_admin_action('Crear estudio', coalesce(p_nombre, 'Sin nombre'), 'estudios');
  else
    v_id := p_estudio_id;
    update public.estudios
       set nombre = coalesce(nullif(trim(p_nombre), ''), nombre),
           categorias = case when v_categorias = '{}' then categorias else v_categorias end,
           barrio = coalesce(nullif(trim(p_barrio), ''), barrio),
           direccion = coalesce(nullif(trim(p_direccion), ''), direccion),
           descripcion = coalesce(nullif(trim(p_descripcion), ''), descripcion),
           foto_url = coalesce(nullif(trim(p_foto_url), ''), foto_url),
           instagram = coalesce(nullif(trim(p_instagram), ''), instagram),
           whatsapp = coalesce(nullif(trim(p_whatsapp), ''), whatsapp),
           web = coalesce(nullif(trim(p_web), ''), web),
           lat = coalesce(p_lat, lat),
           lng = coalesce(p_lng, lng),
           activo = coalesce(p_activo, true),
           fecha_inicio_cobro = coalesce(p_fecha_inicio_cobro, fecha_inicio_cobro),
           tipo_precio = coalesce(nullif(trim(coalesce(p_tipo_precio, '')), ''), tipo_precio),
           creditos_min = coalesce(p_creditos_min, creditos_min),
           creditos_max = coalesce(p_creditos_max, creditos_max)
     where id = p_estudio_id;

    perform public.log_admin_action('Editar estudio',
      coalesce(p_nombre, 'Estudio') || ' (#' || p_estudio_id || ')', 'estudios');
  end if;

  -- Único destino de los datos de cobro. valor_credito: -1 no toca; null lo
  -- vuelve a "seguí el global"; >0 fija el negociado.
  insert into public.estudios_datos_cobro (
    estudio_id, cbu, comision_aura, comision_workshop, valor_credito
  ) values (
    v_id, v_cbu, coalesce(p_comision, 30), coalesce(p_comision_workshop, 15),
    case when p_valor_credito is null or p_valor_credito = -1 then null
         else p_valor_credito end
  )
  on conflict (estudio_id) do update
    set cbu               = coalesce(excluded.cbu, public.estudios_datos_cobro.cbu),
        comision_aura     = coalesce(p_comision, public.estudios_datos_cobro.comision_aura),
        comision_workshop = coalesce(p_comision_workshop, public.estudios_datos_cobro.comision_workshop),
        valor_credito     = case when p_valor_credito = -1
                                 then public.estudios_datos_cobro.valor_credito
                                 else p_valor_credito end;
end;
$function$;
