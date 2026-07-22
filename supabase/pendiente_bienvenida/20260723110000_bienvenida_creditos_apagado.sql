-- ============================================================================
-- Créditos de bienvenida — ARMADO Y APAGADO
-- ============================================================================
--
-- Todo queda listo pero el interruptor arranca en OFF: con el flag apagado,
-- ninguna función acredita nada ni se dispara ninguna notificación. Se
-- enciende manualmente desde el backoffice cuando se quiera lanzar.
--
-- Estos créditos usan source 'bienvenida' y NUNCA disparan referido.
-- ============================================================================

-- Flags en configuracion_global (mismo patrón que valor_credito_ars).
insert into public.configuracion_global (clave, valor)
values ('bienvenida_activa', 'false')
on conflict (clave) do nothing;

insert into public.configuracion_global (clave, valor)
values ('bienvenida_monto', '10')
on conflict (clave) do nothing;


-- Registro de a quién ya se le dio la bienvenida (idempotencia + auditoría).
create table if not exists public.bienvenida_otorgada (
  usuario_id uuid primary key references public.usuarios(id) on delete cascade,
  otorgada_at timestamptz not null default now()
);

alter table public.bienvenida_otorgada enable row level security;
-- Sin policies: solo funciones security definer / service_role la tocan.


-- ── Helpers de lectura del flag ────────────────────────────────────────────
create or replace function public.bienvenida_esta_activa()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select lower(trim(valor)) = 'true'
       from public.configuracion_global
      where clave = 'bienvenida_activa'),
    false
  );
$$;

grant execute on function public.bienvenida_esta_activa() to authenticated, anon;


-- ── Acreditar la bienvenida a UN usuario ───────────────────────────────────
-- Idempotente (bienvenida_otorgada como candado) y gateada por el flag: con
-- el flag OFF no hace nada. Inserta también la notificación in-app.
create or replace function public.acreditar_bienvenida(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_monto int;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'no_user');
  end if;

  -- Apagado → no hace absolutamente nada.
  if not public.bienvenida_esta_activa() then
    return jsonb_build_object('ok', true, 'otorgada', false, 'motivo', 'apagada');
  end if;

  -- Ya se le dio antes.
  if exists (select 1 from public.bienvenida_otorgada where usuario_id = p_user_id) then
    return jsonb_build_object('ok', true, 'otorgada', false, 'motivo', 'ya_otorgada');
  end if;

  select coalesce(nullif(trim(valor), '')::int, 10) into v_monto
    from public.configuracion_global where clave = 'bienvenida_monto';
  v_monto := coalesce(v_monto, 10);

  insert into public.bienvenida_otorgada (usuario_id) values (p_user_id)
  on conflict (usuario_id) do nothing;

  -- Si otro proceso ya insertó la fila, no acreditamos de nuevo.
  if not found then
    return jsonb_build_object('ok', true, 'otorgada', false, 'motivo', 'carrera');
  end if;

  perform public.grant_user_credits(
    p_user_id => p_user_id, p_amount => v_monto,
    p_source => 'bienvenida',
    p_expires_at => (current_date + interval '60 days')::text,
    p_description => 'Créditos de bienvenida'
  );

  insert into public.notificaciones_usuario (usuario_id, titulo, mensaje, tipo, leida)
  values (
    p_user_id,
    '🧡 ¡Bienvenida a Aura!',
    'Te regalamos ' || v_monto || ' créditos para tu primera clase. ¡Aprovechalos!',
    'bienvenida',
    false
  );

  return jsonb_build_object('ok', true, 'otorgada', true, 'monto', v_monto);
end;
$$;

revoke execute on function public.acreditar_bienvenida(uuid) from public, anon;
grant execute on function public.acreditar_bienvenida(uuid) to authenticated, service_role;


-- ── Encender la feature + backfill a TODOS los ya registrados ───────────────
-- Un solo RPC admin: prende el flag y acredita la bienvenida a todos los
-- usuarios existentes que no la recibieron. Idempotente: correrlo dos veces
-- no duplica (bienvenida_otorgada). Con esto el "encendido" es una acción
-- deliberada del admin, no algo que pase solo.
create or replace function public.admin_encender_bienvenida(p_monto int default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_otorgadas int := 0;
  v_row record;
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  if p_monto is not null and p_monto > 0 then
    insert into public.configuracion_global (clave, valor, updated_at)
    values ('bienvenida_monto', p_monto::text, now())
    on conflict (clave) do update set valor = excluded.valor, updated_at = now();
  end if;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('bienvenida_activa', 'true', now())
  on conflict (clave) do update set valor = 'true', updated_at = now();

  -- Backfill: solo usuarios finales (no estudios/profes/admin), sin bienvenida.
  for v_row in
    select u.id
      from public.usuarios u
      left join public.bienvenida_otorgada b on b.usuario_id = u.id
     where b.usuario_id is null
       and coalesce(u.rol, 'usuario') = 'usuario'
  loop
    if (public.acreditar_bienvenida(v_row.id)->>'otorgada') = 'true' then
      v_otorgadas := v_otorgadas + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'otorgadas', v_otorgadas);
end;
$$;

grant execute on function public.admin_encender_bienvenida(int) to authenticated;


-- ── Apagar la feature ──────────────────────────────────────────────────────
create or replace function public.admin_apagar_bienvenida()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  insert into public.configuracion_global (clave, valor, updated_at)
  values ('bienvenida_activa', 'false', now())
  on conflict (clave) do update set valor = 'false', updated_at = now();

  return jsonb_build_object('ok', true);
end;
$$;

grant execute on function public.admin_apagar_bienvenida() to authenticated;
