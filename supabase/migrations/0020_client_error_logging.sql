-- ============================================================================
-- سجل أخطاء العملاء (بديل بسيط عن Sentry، بدون خدمة خارجية أو تسجيل حساب جديد)
-- ============================================================================

create table client_errors (
  id uuid primary key default gen_random_uuid(),
  platform text not null check (platform in ('web', 'android')),
  user_id uuid references profiles(id),
  message text not null,
  context jsonb,
  created_at timestamptz not null default now()
);

alter table client_errors enable row level security;

create policy client_errors_select on client_errors
  for select using (is_admin());
-- لا سياسة insert للعميل - فقط عبر log-client-error (service_role)، لمنع إغراق الجدول بسجلات وهمية
