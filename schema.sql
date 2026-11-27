-- ==============================================================================
-- VEXAVET SAAS MULTI-TENANT - SCRIPT COMPLETO UNIFICADO (TABLAS + SEED + RLS)
-- ==============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. CONFIGURACIÓN GLOBAL DE LA PLATAFORMA (Exclusivo Super Admin Vexavet)
CREATE TABLE IF NOT EXISTS public.plataforma_config (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    nombre_saas TEXT NOT NULL DEFAULT 'Vexavet',
    logo_saas_url TEXT DEFAULT '',
    favicon_url TEXT DEFAULT '',
    fondo_login_url TEXT DEFAULT '',
    color_primario TEXT DEFAULT '#4F46E5',
    soporte_whatsapp TEXT DEFAULT '',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. CLÍNICAS VETERINARIAS (Tenants / Clientes SaaS)
CREATE TABLE IF NOT EXISTS public.clinicas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nombre TEXT NOT NULL,
    ruc_nit TEXT,
    telefono TEXT,
    email TEXT,
    direccion TEXT,
    ciudad TEXT,
    pais TEXT DEFAULT 'Ecuador',
    moneda TEXT DEFAULT 'USD',
    impuesto_porcentaje NUMERIC(5,2) DEFAULT 15.00,
    logo_clinica_url TEXT DEFAULT '',
    plan_nombre TEXT NOT NULL DEFAULT 'Vexavet Pro',
    plan_estado TEXT NOT NULL DEFAULT 'Activa' CHECK (plan_estado IN ('Activa', 'Prueba', 'Vencida', 'Suspendida')),
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    fecha_fin DATE DEFAULT (CURRENT_DATE + INTERVAL '30 days'),
    cuota_sms INT DEFAULT 50,
    cuota_whatsapp INT DEFAULT 50,
    cuota_emails INT DEFAULT 3000,
    cuota_agendamientos INT DEFAULT 3000,
    cuota_recibos INT DEFAULT 300,
    cuota_tokens_ia INT DEFAULT 150000,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. USUARIOS Y ROLES
CREATE TABLE IF NOT EXISTS public.usuarios_sistema (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID REFERENCES public.clinicas(id) ON DELETE CASCADE,
    nombre_completo TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    rol TEXT NOT NULL CHECK (rol IN ('super_admin', 'admin_clinica', 'veterinario', 'recepcion')),
    especialidad TEXT DEFAULT 'Medicina General',
    registro_profesional TEXT,
    telefono TEXT,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. CONSULTORIOS / SALAS FÍSICAS
CREATE TABLE IF NOT EXISTS public.consultorios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    nombre TEXT NOT NULL,
    tipo TEXT DEFAULT 'Consulta General',
    activo BOOLEAN DEFAULT TRUE
);

-- 5. PROPIETARIOS
CREATE TABLE IF NOT EXISTS public.propietarios (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    codigo_externo TEXT,
    identificacion TEXT,
    nombres TEXT NOT NULL,
    apellidos TEXT,
    telefono TEXT,
    email TEXT,
    direccion TEXT,
    ciudad TEXT,
    saldo_favor NUMERIC(12,2) DEFAULT 0,
    notas TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. MASCOTAS
CREATE TABLE IF NOT EXISTS public.mascotas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    propietario_id UUID REFERENCES public.propietarios(id) ON DELETE SET NULL,
    codigo_externo TEXT,
    nombre TEXT NOT NULL,
    especie TEXT NOT NULL DEFAULT 'Canino',
    raza TEXT DEFAULT 'Mestizo',
    sexo TEXT DEFAULT 'Macho',
    fecha_nacimiento DATE,
    color TEXT,
    peso_kg NUMERIC(6,2) DEFAULT 0,
    esterilizado BOOLEAN DEFAULT FALSE,
    microchip TEXT,
    propietario_nombre TEXT,
    propietario_telefono TEXT,
    estado TEXT DEFAULT 'Activo',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. AGENDA Y SALA DE ESPERA
CREATE TABLE IF NOT EXISTS public.citas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    mascota_id UUID REFERENCES public.mascotas(id) ON DELETE CASCADE,
    veterinario_id UUID REFERENCES public.usuarios_sistema(id) ON DELETE SET NULL,
    consultorio_id UUID REFERENCES public.consultorios(id) ON DELETE SET NULL,
    fecha DATE NOT NULL,
    hora TIME NOT NULL,
    tipo_servicio TEXT NOT NULL DEFAULT 'Consulta General',
    motivo TEXT,
    estado TEXT NOT NULL DEFAULT 'Programada' CHECK (estado IN ('Programada', 'En Sala de Espera', 'En Consulta', 'Completada', 'Cancelada')),
    hora_llegada TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. HISTORIA CLÍNICA
CREATE TABLE IF NOT EXISTS public.historia_clinica (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    mascota_id UUID NOT NULL REFERENCES public.mascotas(id) ON DELETE CASCADE,
    veterinario_id UUID REFERENCES public.usuarios_sistema(id) ON DELETE SET NULL,
    tipo_registro TEXT NOT NULL DEFAULT 'Consulta',
    fecha TIMESTAMPTZ DEFAULT NOW(),
    motivo_consulta TEXT,
    anamnesis TEXT,
    temperatura NUMERIC(4,1),
    frecuencia_cardiaca INT,
    frecuencia_respiratoria INT,
    peso_actual NUMERIC(6,2),
    diagnostico TEXT,
    tratamiento_formula TEXT,
    proxima_cita DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. HOSPITALIZACIÓN Y AMBULATORIO
CREATE TABLE IF NOT EXISTS public.hospitalizaciones (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    mascota_id UUID NOT NULL REFERENCES public.mascotas(id) ON DELETE CASCADE,
    veterinario_id UUID REFERENCES public.usuarios_sistema(id) ON DELETE SET NULL,
    modalidad TEXT NOT NULL DEFAULT 'Hospitalización',
    jaula_box TEXT,
    fecha_ingreso TIMESTAMPTZ DEFAULT NOW(),
    fecha_egreso TIMESTAMPTZ,
    diagnostico_ingreso TEXT,
    plan_terapeutico TEXT,
    estado TEXT DEFAULT 'Internado',
    kardex_notas JSONB DEFAULT '[]'::jsonb
);

-- 10. SOLICITUDES Y TAREAS PENDIENTES
CREATE TABLE IF NOT EXISTS public.solicitudes_tareas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    mascota_id UUID REFERENCES public.mascotas(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL,
    titulo TEXT NOT NULL,
    detalle TEXT,
    prioridad TEXT DEFAULT 'Media',
    estado TEXT DEFAULT 'Pendiente',
    fecha_limite DATE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. PROVEEDORES
CREATE TABLE IF NOT EXISTS public.proveedores (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    nombre TEXT NOT NULL,
    ruc_nit TEXT,
    contacto TEXT,
    telefono TEXT,
    email TEXT,
    categoria TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. INVENTARIO: PRODUCTOS, SERVICIOS Y PLANES DE SALUD
CREATE TABLE IF NOT EXISTS public.inventario_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    codigo_sku TEXT,
    nombre TEXT NOT NULL,
    tipo TEXT NOT NULL DEFAULT 'Producto',
    categoria TEXT DEFAULT 'General',
    precio_compra NUMERIC(12,2) DEFAULT 0,
    precio_venta NUMERIC(12,2) NOT NULL DEFAULT 0,
    stock_actual INT DEFAULT 0,
    stock_minimo INT DEFAULT 5,
    fecha_vencimiento DATE,
    lote TEXT,
    duracion_dias INT DEFAULT 365,
    activo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. DOCUMENTOS DE VENTA
CREATE TABLE IF NOT EXISTS public.documentos_venta (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    propietario_id UUID REFERENCES public.propietarios(id) ON DELETE SET NULL,
    cliente_nombre TEXT NOT NULL,
    tipo_documento TEXT NOT NULL DEFAULT 'Factura/Recibo',
    numero_correlativo TEXT NOT NULL,
    items JSONB NOT NULL DEFAULT '[]'::jsonb,
    subtotal NUMERIC(12,2) DEFAULT 0,
    impuesto NUMERIC(12,2) DEFAULT 0,
    total NUMERIC(12,2) NOT NULL DEFAULT 0,
    metodo_pago TEXT DEFAULT 'Efectivo',
    estado TEXT DEFAULT 'Pagado',
    usuario_emisor TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. MOVIMIENTOS DE CAJA
CREATE TABLE IF NOT EXISTS public.movimientos_caja (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    tipo TEXT NOT NULL,
    concepto TEXT NOT NULL,
    categoria TEXT DEFAULT 'Operativo',
    monto NUMERIC(12,2) NOT NULL,
    metodo_pago TEXT DEFAULT 'Efectivo',
    referencia TEXT,
    fecha TIMESTAMPTZ DEFAULT NOW()
);

-- 15. AFILIACIONES A PLANES DE SALUD
CREATE TABLE IF NOT EXISTS public.planes_afiliados (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    clinica_id UUID NOT NULL REFERENCES public.clinicas(id) ON DELETE CASCADE,
    mascota_id UUID REFERENCES public.mascotas(id) ON DELETE CASCADE,
    plan_id UUID REFERENCES public.inventario_items(id) ON DELETE SET NULL,
    plan_nombre TEXT NOT NULL,
    mascota_nombre TEXT NOT NULL,
    propietario_nombre TEXT,
    fecha_inicio DATE DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE NOT NULL,
    estado TEXT DEFAULT 'Vigente'
);

-- ==============================================================================
-- HABILITAR RLS Y POLÍTICAS EN TODAS LAS TABLAS
-- ==============================================================================
DO $$ 
DECLARE 
    t TEXT;
    tablas TEXT[] := ARRAY[
        'plataforma_config', 'clinicas', 'usuarios_sistema', 'consultorios',
        'propietarios', 'mascotas', 'citas', 'historia_clinica',
        'hospitalizaciones', 'solicitudes_tareas', 'proveedores',
        'inventario_items', 'documentos_venta', 'movimientos_caja', 'planes_afiliados'
    ];
BEGIN
    FOREACH t IN ARRAY tablas LOOP
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY;', t);
        EXECUTE format('DROP POLICY IF EXISTS "Acceso_Vexavet_%I" ON public.%I;', t, t);
        EXECUTE format('CREATE POLICY "Acceso_Vexavet_%I" ON public.%I FOR ALL USING (true) WITH CHECK (true);', t, t);
    END LOOP;
END $$;

-- ==============================================================================
-- DATOS INICIALES (SUPER ADMIN + CLÍNICA DEMO)
-- ==============================================================================
INSERT INTO public.plataforma_config (id, nombre_saas)
VALUES (1, 'Vexavet')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.usuarios_sistema (id, clinica_id, nombre_completo, email, password_hash, rol)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    NULL,
    'Super Admin Vexavet',
    'superadmin@vexavet.com',
    'Vexavet2026*',
    'super_admin'
) ON CONFLICT (email) DO NOTHING;

INSERT INTO public.clinicas (id, nombre, ruc_nit, telefono, email, direccion, ciudad, plan_nombre, plan_estado)
VALUES (
    '11111111-1111-1111-1111-111111111111',
    'Hospital Veterinario San Francisco',
    '1390123456001',
    '+593 99 123 4567',
    'contacto@vetsanfrancisco.com',
    'Av. Manabí y Calle 10',
    'Portoviejo',
    'Vexavet Pro',
    'Activa'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO public.usuarios_sistema (clinica_id, nombre_completo, email, password_hash, rol, especialidad)
VALUES 
    ('11111111-1111-1111-1111-111111111111', 'Dr. Carlos Mendoza (Director)', 'admin@clinica.com', 'Clinica2026*', 'admin_clinica', 'Cirugía y Dirección'),
    ('11111111-1111-1111-1111-111111111111', 'Dra. Valeria Gómez', 'vet@clinica.com', 'Vet2026*', 'veterinario', 'Medicina Interna')
ON CONFLICT (email) DO NOTHING;