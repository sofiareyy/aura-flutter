-- Deshace FIX_nombre_real_google_apple_2026-11-03.sql.
-- Vuelve el nombre anterior SOLO si nadie lo cambió después (si la alumna lo
-- editó en la app, se respeta lo que puso).

update public.usuarios u
   set nombre = b.nombre_anterior
  from public._backup_nombres_2026_11_03 b
 where u.id = b.usuario_id
   and u.nombre = b.nombre_nuevo;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  BEGIN
    INSERT INTO public.usuarios (
      id,
      nombre,
      email,
      plan,
      creditos,
      rol
    )
    VALUES (
      NEW.id,
      COALESCE(
        NULLIF(TRIM(NEW.raw_user_meta_data->>'nombre'), ''),
        split_part(NEW.email, '@', 1),
        'Usuario'
      ),
      COALESCE(NEW.email, ''),
      NULL,
      0,
      'usuario'
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'handle_new_user falló para %: %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

-- La tabla de backup y el helper se pueden dejar; borrarlos después de
-- confirmar que no hace falta volver atrás:
-- drop table public._backup_nombres_2026_11_03;
-- drop function public._nombre_prolijo(text);
