-- ============================================================
-- AURA – Migración Mercado Pago
-- Ejecutar en el SQL Editor de Supabase (una sola vez)
-- ============================================================

-- 1. Agregar campos de suscripción a la tabla usuarios
ALTER TABLE public.usuarios
  ADD COLUMN IF NOT EXISTS mp_subscription_id    TEXT,
  ADD COLUMN IF NOT EXISTS subscription_status   TEXT DEFAULT 'none',
  ADD COLUMN IF NOT EXISTS renewal_date          DATE;

-- 2. Crear tabla de pagos (historial completo de transacciones)
CREATE TABLE IF NOT EXISTS public.pagos (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES public.usuarios(id) ON DELETE CASCADE,
  type              TEXT        NOT NULL CHECK (type IN ('plan', 'pack')),
  mp_payment_id     TEXT,
  mp_preference_id  TEXT,
  mp_preapproval_id TEXT,
  status            TEXT        NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled', 'in_process')),
  amount            INTEGER     NOT NULL DEFAULT 0,
  creditos          INTEGER     NOT NULL DEFAULT 0,
  plan_nombre       TEXT,
  pack_nombre       TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Índices para idempotencia y performance
CREATE UNIQUE INDEX IF NOT EXISTS pagos_mp_payment_id_idx
  ON public.pagos(mp_payment_id) WHERE mp_payment_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS pagos_mp_preference_id_idx
  ON public.pagos(mp_preference_id) WHERE mp_preference_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS pagos_mp_preapproval_id_idx
  ON public.pagos(mp_preapproval_id) WHERE mp_preapproval_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS pagos_user_id_idx
  ON public.pagos(user_id);

-- 3. Row Level Security
ALTER TABLE public.pagos ENABLE ROW LEVEL SECURITY;

-- Usuarios solo pueden ver sus propios pagos (SELECT)
DROP POLICY IF EXISTS "usuarios_ver_sus_pagos" ON public.pagos;
CREATE POLICY "usuarios_ver_sus_pagos"
  ON public.pagos FOR SELECT
  USING (auth.uid() = user_id);

-- INSERT/UPDATE solo permitido vía service_role (webhook usa service_role key,
-- que bypasea RLS por completo). No creamos policy para authenticated en write
-- para que ningún cliente pueda acreditar créditos por su cuenta.

-- 4. Trigger para mantener updated_at al día
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS pagos_set_updated_at ON public.pagos;
CREATE TRIGGER pagos_set_updated_at
  BEFORE UPDATE ON public.pagos
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- Verificación: consultá las nuevas columnas en usuarios
-- ============================================================
-- SELECT mp_subscription_id, subscription_status, renewal_date
-- FROM public.usuarios LIMIT 5;
