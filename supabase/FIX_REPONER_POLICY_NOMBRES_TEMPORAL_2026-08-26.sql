-- ⏳ TEMPORAL — REVERTIR CUANDO APPLE APRUEBE EL BUILD 26
--
-- Por qué: el arreglo de nombres del 25/8 tiene dos mitades. La app vieja
-- (build 25, la que los estudios tienen instalada hoy) lee `public.usuarios`
-- DIRECTO, sujeta a RLS. El build 26 usa la RPC limpia
-- `estudio_nombres_alumnas`, que devuelve sólo (id, nombre, email, avatar_url).
--
-- Al crear la RPC se dropeó esta policy, y eso dejó a la app vieja sin nombres:
-- medido el 26/8, la consulta que hace el build 25 como Citra devuelve 0 filas
-- y el cartel del escaneo muestra "Usuario" en vez del nombre.
--
-- Se repone tal cual estaba, con el mismo helper `es_alumna_de_mi_estudio`
-- (que nunca se borró): sólo alumnas con una reserva NO cancelada en una clase
-- de un estudio que quien llama administra.
--
-- ⚠️ EL COSTO, asumido a conciencia: una policy habilita la FILA ENTERA. El
-- estudio puede leer además `creditos`, `plan`, `codigo_referido`, `empresa_id`
-- y `avatar_url` de esa alumna. NO hay datos de cobro ni CBU en esa tabla.
-- Es más de lo que la pantalla necesita, y por eso existe la RPC.
--
-- 👉 CUANDO EL BUILD 26 ESTÉ APROBADO Y ADOPTADO:
--      drop policy usuarios_select_alumnas_de_mis_clases on public.usuarios;
--    y verificar que Asistencia siga mostrando nombres (ya por la RPC).

drop policy if exists usuarios_select_alumnas_de_mis_clases on public.usuarios;
create policy usuarios_select_alumnas_de_mis_clases on public.usuarios
  for select to authenticated
  using (public.es_alumna_de_mi_estudio(id));

notify pgrst, 'reload schema';
