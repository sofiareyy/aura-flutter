-- ============================================================================
-- Cuentas que NO son clientas: testers y cuentas internas (16/9/2026)
-- ============================================================================
--
-- El 14/9 arrancaron 103 testers de Android contratados por Fiverr y subidos a
-- Play Console. Entre el 14 y el 16/9 se registraron 18 cuentas: 10 son de esa
-- lista y otras 6 tienen el mismo patron (tanda, dispositivo Android, mails del
-- mismo origen) sin estar en el CSV — muy probablemente el vendedor sumo gente
-- con otros mails.
--
-- Sin separarlos, las metricas mienten: septiembre marcaba 29 altas cuando las
-- reales eran 19. Y los 20 "pagos pendientes" que parecian un problema de
-- Mercado Pago eran 16 pruebas de la cuenta de Sofia y 2 de testers probando el
-- checkout.
--
-- La marca es por EMAIL y no por usuario_id a proposito: un tester puede
-- borrarse y volver a registrarse, y la lista tiene que seguir valiendo.
-- ============================================================================

create table if not exists public.cuentas_internas (
  email      text primary key,
  motivo     text not null check (motivo in ('tester_android','tester_probable','interna')),
  nota       text,
  created_at timestamptz not null default now()
);

comment on table public.cuentas_internas is
  'Cuentas que no cuentan como clientas (testers, pruebas). Se filtran de las metricas. Marcadas por email: sobrevive a que la cuenta se borre y se vuelva a crear.';

alter table public.cuentas_internas enable row level security;
-- Sin policies: solo admin por RPC y service_role.
revoke all on public.cuentas_internas from anon, authenticated;

insert into public.cuentas_internas (email, motivo, nota) values
  ('aarav.kumar.8088@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ab.malakzay38@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('abdullahkhankhan2026@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('abdulrahmankabuli25@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('abobakerjan37@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('abobakerkhan95@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('afqaseem866@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ahmadiaisha545@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ahsansadat60@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('akhfarhadi7788@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ali133afghan@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('aliasilio903@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ananya.reddy1414@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('armanlilay@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ashnasuliman318@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('asmabarakat2090@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ayubarman823@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bakht0643@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('baltakhan4545@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('barakatullah.af.1.2@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('barakatullah.private1@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('barakatullahkhan12@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bashirahmadrahimi8890p@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('belalahmady140@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bhamdard730@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bibizainab2090@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bibrahimi947@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('bostanalirahnaward22@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('danishaqil194@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('enuamd@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('fkhadimsofian@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hajizadasima7@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hakeemkhan0003@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hamidjalali066@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hamtahamta722@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hawamohammadiaf@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('hejra.karimi2010@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('henry.parker.official33@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ibrahimkhan125405@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('iftikharmomand45@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ihsanulllahzahid@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ilhamkamal065@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('jack.mitchell.dev@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('jalali.omid2021@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('janankhan5011227@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('johans654321@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('kabirtaskin7@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('kefayatkhan2090@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khademkhan2025@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khadimnasratullah41@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khaleelnazari66@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khankpkk591@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khanmaimana77@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('khannawabafghan123@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('kkhansafijan@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ksofian024@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('lalaarman078@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('lotfullahehsass@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('lucas.morgan.io13@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mahwaham2@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mashna727@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mateen.m.khan123@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('minarana2017@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mkbahar891@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mohabatkhan9995@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mohammadrafirahimi890@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mohammadsabir.hewadmall47@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mohammadsalamfaizi@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mursalghayor@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('musadarman07@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('mustefanoori42@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('nasratkhan2025khan@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('nasratullahkhadim00@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('naweedkhan2027@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('noorrahmanyousofzai@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('omarzalmi43@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('omidrahimi5066@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('qandwakhand@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('rashindkhan33@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('rentakahash55@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('roshanazizullah768@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('sadatamiri004@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('safi127615@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('safirkhan0773@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('safisafna14@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('sakurayamamoto601@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('samemk218@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('samimqadiri353@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('samirsami0912@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('sanaullahkhan64772@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('seyamsalaah@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('shahidonkhadim@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('shamskhadim91@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('shamskhan123408@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('sharifkarimi014@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('simonjan2090@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('solomanpro001@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('sultanazimi011@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('taskenbath@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('taskjon359@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('zahidkhadem84@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ziedjan1332025@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('ziedkhan9995@gmail.com', 'tester_android', 'CSV de Play Console del 14/9/2026'),
  ('afg.arian123@gmail.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('abasskhan9995@gmail.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('asma.asma.asma.2026@gmail.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('qaiskhadim0700@gmail.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('barakatullah1provider@gmail.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('zainabsafar111@icloud.com', 'tester_probable', 'Mismo patron que los testers (tanda, Android) pero NO esta en el CSV. Revisable.'),
  ('aura.hola.app@gmail.com', 'interna', 'La cuenta de Sofia: hace las pruebas de pago y de la app')
on conflict (email) do nothing;

-- ¿Esta cuenta cuenta como clienta? Una sola definicion para todas las
-- metricas, para que no se separen nunca.
create or replace function public.es_cuenta_interna(p_email text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cuentas_internas ci
                  where ci.email = lower(trim(coalesce(p_email, ''))));
$$;

grant execute on function public.es_cuenta_interna(text) to authenticated, service_role;

-- Historial de resumenes enviados. Sirve para dos cosas: numerarlos (si salta
-- un numero, algo se rompio) y poder mirar hacia atras que decia cada uno.
create table if not exists public.resumen_diario_envios (
  id         bigint generated always as identity primary key,
  numero     int  not null,
  fecha      date not null unique,
  metricas   jsonb,
  enviado_at timestamptz not null default now()
);

alter table public.resumen_diario_envios enable row level security;
revoke all on public.resumen_diario_envios from anon, authenticated;
