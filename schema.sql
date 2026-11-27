-- ==============================================================================
-- VEXAVET MULTI-TENANT + NFC + COMPATIBILIDAD TOTAL CON ESQUEMA ACTUAL
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. TABLA DE CLÍNICAS (Tenants / Clientes SaaS para el Super Admin)
CREATE TABLE IF NOT EXISTS public.clinicas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre TEXT NOT NULL,
    nit_ruc TEXT,
    pais TEXT DEFAULT 'Ecuador',
    moneda TEXT DEFAULT '$',
    impuesto_nombre TEXT DEFAULT 'IVA',
    impuesto_porcentaje NUMERIC(5,2) DEFAULT 15.00,
    telefono TEXT,
    email TEXT,
    ciudad TEXT DEFAULT 'Portoviejo',
    direccion TEXT,
    horario TEXT DEFAULT 'Lun - Sáb: 08:00 - 20:00',
    sedes TEXT DEFAULT 'Matriz Central',
    metodos_pago TEXT DEFAULT 'Efectivo, Tarjeta, Transferencia',
    logo_url TEXT,
    favicon_url TEXT,
    custom_bg TEXT,
    login_bg TEXT,
    plan_nombre TEXT DEFAULT 'Vexavet Pro',
    plan_estado TEXT DEFAULT 'Activa',
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    fecha_fin DATE DEFAULT (CURRENT_DATE + INTERVAL '365 days'),
    cuota_sms INT DEFAULT 100,
    cuota_whatsapp INT DEFAULT 200,
    cuota_emails INT DEFAULT 3000,
    cuota_agendamientos INT DEFAULT 3000,
    cuota_recibos INT DEFAULT 500,
    cuota_tokens_ia INT DEFAULT 150000,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- Clínica principal por defecto (para migrar tus datos existentes sin perder nada)
INSERT INTO public.clinicas (id, nombre, ciudad, plan_nombre, plan_estado)
VALUES ('11111111-1111-1111-1111-111111111111', 'VEXAVET Clínica Veterinaria', 'Portoviejo', 'Vexavet Enterprise', 'Activa')
ON CONFLICT (id) DO NOTHING;

-- 2. AÑADIR clinica_id Y nfc_uid A TUS TABLAS EXISTENTES (sin borrar datos)
DO $$
DECLARE
    t TEXT;
    tablas_existentes TEXT[] := ARRAY[
        'perfiles', 'mascotas', 'propietarios', 'consultas', 'vacunas',
        'desparasitaciones', 'cirugias', 'examenes', 'medicacion',
        'documentos_clinicos', 'citas', 'procedimientos', 'procedimientos_mascota',
        'hospitalizaciones', 'kardex_hospitalizacion', 'productos',
        'movimientos_inventario', 'ventas', 'notificaciones', 'campanas_marketing',
        'registro_actividad'
    ];
BEGIN
    FOREACH t IN ARRAY tablas_existentes LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
            EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE;', t);
            IF t <> 'perfiles' THEN
                EXECUTE format('UPDATE public.%I SET clinica_id = ''11111111-1111-1111-1111-111111111111'' WHERE clinica_id IS NULL;', t);
            END IF;
        END IF;
    END LOOP;
END $$;

-- Vincular perfiles existentes (que no sean super_admin) a la clínica principal
UPDATE public.perfiles
SET clinica_id = '11111111-1111-1111-1111-111111111111'
WHERE clinica_id IS NULL AND rol <> 'super_admin';

-- Asegurar soporte NFC en mascotas
ALTER TABLE public.mascotas ADD COLUMN IF NOT EXISTS nfc_uid TEXT;
CREATE INDEX IF NOT EXISTS idx_mascotas_nfc_uid ON public.mascotas(nfc_uid);

-- Función RPC para buscar mascota por tarjeta NFC (funciona incluso sin sesión)
CREATE OR REPLACE FUNCTION public.mascota_por_nfc(p_uid TEXT)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT id FROM public.mascotas WHERE UPPER(REPLACE(COALESCE(nfc_uid,''), ':', '')) = UPPER(REPLACE(COALESCE(p_uid,''), ':', '')) LIMIT 1;
$$;

-- 3. TABLAS COMPLEMENTARIAS (Consultorios, Solicitudes, Planes, Caja, Proveedores)
CREATE TABLE IF NOT EXISTS public.consultorios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE DEFAULT '11111111-1111-1111-1111-111111111111',
    nombre TEXT NOT NULL,
    tipo TEXT DEFAULT 'Consulta General',
    activo BOOLEAN DEFAULT TRUE,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.solicitudes_tareas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE DEFAULT '11111111-1111-1111-1111-111111111111',
    mascota_id UUID REFERENCES public.mascotas(id) ON DELETE CASCADE,
    mascota_nombre TEXT,
    tipo TEXT NOT NULL DEFAULT 'Seguimiento',
    titulo TEXT NOT NULL,
    detalle TEXT,
    prioridad TEXT DEFAULT 'Media',
    estado TEXT DEFAULT 'Pendiente',
    fecha_limite DATE DEFAULT CURRENT_DATE,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.proveedores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE DEFAULT '11111111-1111-1111-1111-111111111111',
    nombre TEXT NOT NULL,
    nit_ruc TEXT,
    contacto TEXT,
    telefono TEXT,
    email TEXT,
    categoria TEXT DEFAULT 'Distribuidor Veterinario',
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.movimientos_caja (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE DEFAULT '11111111-1111-1111-1111-111111111111',
    tipo TEXT NOT NULL CHECK (tipo IN ('Ingreso', 'Egreso')),
    concepto TEXT NOT NULL,
    categoria TEXT DEFAULT 'Operativo',
    monto NUMERIC(12,2) NOT NULL DEFAULT 0,
    metodo_pago TEXT DEFAULT 'Efectivo',
    usuario_nombre TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.planes_afiliados (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE DEFAULT '11111111-1111-1111-1111-111111111111',
    mascota_id UUID REFERENCES public.mascotas(id) ON DELETE CASCADE,
    mascota_nombre TEXT NOT NULL,
    propietario_nombre TEXT,
    plan_nombre TEXT NOT NULL,
    valor NUMERIC(12,2) DEFAULT 0,
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE NOT NULL,
    estado TEXT DEFAULT 'Vigente',
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 4. ACTUALIZAR RPC admin_crear_usuario PARA SOPORTAR clinica_id Y rol super_admin
CREATE OR REPLACE FUNCTION public.admin_crear_usuario(
    p_usuario TEXT,
    p_clave TEXT,
    p_nombre TEXT,
    p_rol TEXT,
    p_clinica_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_uid UUID;
    v_email TEXT;
    v_cid UUID;
BEGIN
    v_email := LOWER(TRIM(p_usuario)) || '@vexavet.local';
    SELECT COALESCE(p_clinica_id, clinica_id, '11111111-1111-1111-1111-111111111111')
    INTO v_cid FROM public.perfiles WHERE id = auth.uid();

    IF p_rol = 'super_admin' THEN
        v_cid := NULL;
    END IF;

    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
        '00000000-0000-0000-0000-000000000000',
        uuid_generate_v4(),
        'authenticated',
        'authenticated',
        v_email,
        crypt(p_clave, gen_salt('bf')),
        NOW(),
        '{"provider":"email","providers":["email"]}',
        jsonb_build_object('nombre', p_nombre),
        NOW(),
        NOW()
    ) RETURNING id INTO v_uid;

    INSERT INTO public.perfiles (id, usuario, email, nombre, rol, activo, clinica_id)
    VALUES (v_uid, LOWER(TRIM(p_usuario)), v_email, p_nombre, p_rol, TRUE, v_cid);

    RETURN v_uid;
END;
$$;

-- 5. HABILITAR RLS Y POLÍTICAS EN TODAS LAS TABLAS
DO $$
DECLARE
    t TEXT;
    todas TEXT[] := ARRAY[
        'clinicas', 'perfiles', 'mascotas', 'propietarios', 'consultas', 'vacunas',
        'desparasitaciones', 'cirugias', 'examenes', 'medicacion',
        'documentos_clinicos', 'citas', 'procedimientos', 'procedimientos_mascota',
        'hospitalizaciones', 'kardex_hospitalizacion', 'productos',
        'movimientos_inventario', 'ventas', 'notificaciones', 'campanas_marketing',
        'registro_actividad', 'configuracion_clinica', 'consultorios',
        'solicitudes_tareas', 'proveedores', 'movimientos_caja', 'planes_afiliados'
    ];
BEGIN
    FOREACH t IN ARRAY todas LOOP
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = t) THEN
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
            EXECUTE format('DROP POLICY IF EXISTS "Acceso_Vexavet_%I" ON public.%I;', t, t);
            EXECUTE format('CREATE POLICY "Acceso_Vexavet_%I" ON public.%I FOR ALL USING (true) WITH CHECK (true);', t, t);
        END IF;
    END LOOP;
END $$;