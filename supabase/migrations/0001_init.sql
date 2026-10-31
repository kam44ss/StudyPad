-- ============================================================================
-- منصة الدروس - المخطط الأساسي (Supabase / PostgreSQL)
-- ملاحظة: لم يتيسر تشغيل هذا الملف فعلياً على سيرفر Postgres حقيقي أثناء الكتابة
-- (لا توجد بيئة Postgres متاحة هنا) - راجعه بعناية أو جربه على مشروع Supabase تجريبي
-- قبل استخدامه بالإنتاج.
-- ============================================================================

create extension if not exists "pgcrypto"; -- لتوليد gen_random_uuid()

-- ----------------------------------------------------------------------------
-- 1. الملفات الشخصية (مرتبطة بـ auth.users المدمج بـ Supabase)
-- ----------------------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  email text,
  role text not null default 'student' check (role in ('admin', 'teacher', 'student')),
  created_at timestamptz not null default now()
);

-- منع أي شخص من تغيير role الخاص فيه إلا عبر service_role (أي عبر Edge Function)
create or replace function prevent_role_self_change()
returns trigger as $$
begin
  if new.role is distinct from old.role and auth.role() <> 'service_role' then
    raise exception 'cannot change role directly';
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger profiles_protect_role
before update on profiles
for each row execute function prevent_role_self_change();

-- ----------------------------------------------------------------------------
-- 2. المدرسون
-- ----------------------------------------------------------------------------
create table teachers (
  id uuid primary key references profiles(id) on delete cascade,
  display_name text,
  bio text,
  revenue_share_percent numeric(5,2) not null default 100
    check (revenue_share_percent >= 0 and revenue_share_percent <= 100),
  payout_method text,
  payout_info text,
  total_earned numeric(12,2) not null default 0,
  total_paid_out numeric(12,2) not null default 0,
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now()
);

-- منع تعديل الحقول المالية أو نسبة الأرباح مباشرة من العميل - فقط عبر service_role
create or replace function protect_teacher_financials()
returns trigger as $$
begin
  if auth.role() <> 'service_role' then
    if new.total_earned is distinct from old.total_earned
      or new.total_paid_out is distinct from old.total_paid_out
      or new.revenue_share_percent is distinct from old.revenue_share_percent then
      raise exception 'cannot modify teacher financial fields directly';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger teachers_protect_financials
before update on teachers
for each row execute function protect_teacher_financials();

-- ----------------------------------------------------------------------------
-- 3. الوكلاء / الموزّعون
-- ----------------------------------------------------------------------------
create table agents (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  commission_percent numeric(5,2) not null default 0
    check (commission_percent >= 0 and commission_percent <= 100),
  total_earned numeric(12,2) not null default 0,
  total_paid_out numeric(12,2) not null default 0,
  status text not null default 'active' check (status in ('active', 'suspended')),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 4. الدروس والمحتوى
-- ----------------------------------------------------------------------------
create table lessons (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references teachers(id),
  title text not null,
  subject text,
  type text check (type in ('video', 'pdf', 'quiz', 'mixed')),
  price_type text not null default 'one_time' check (price_type in ('one_time', 'subscription')),
  price numeric(12,2) not null check (price >= 0),
  google_play_product_id text,
  apple_product_id text,
  status text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  created_at timestamptz not null default now()
);

create table lesson_content (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  type text check (type in ('video', 'pdf', 'quiz')),
  url text,
  order_index integer not null default 0
);

create table quiz_questions (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  text text not null,
  choices jsonb not null,
  correct_index integer not null
);

-- ----------------------------------------------------------------------------
-- 5. المشتريات وأكواد التفعيل وطلبات زين كاش
-- ----------------------------------------------------------------------------
create table purchases (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles(id),
  lesson_id uuid not null references lessons(id),
  teacher_id uuid not null references teachers(id),
  store_transaction_id text not null unique, -- قيد فريد حقيقي بقاعدة البيانات يمنع التكرار
  purchase_token text,
  method text not null check (method in ('google_play', 'app_store', 'zaincash', 'redemption_code')),
  status text not null default 'verified' check (status in ('verified', 'pending', 'refunded')),
  purchased_at timestamptz not null default now()
);

create table redemption_codes (
  code text primary key,
  lesson_id uuid not null references lessons(id),
  teacher_id uuid not null references teachers(id),
  agent_id uuid references agents(id),
  value numeric(12,2) not null,
  is_paid boolean not null default false,
  status text not null default 'unused' check (status in ('unused', 'used')),
  created_by uuid references profiles(id),
  used_by uuid references profiles(id),
  used_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table zaincash_orders (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles(id),
  lesson_id uuid not null references lessons(id),
  teacher_id uuid not null references teachers(id),
  amount numeric(12,2) not null,
  status text not null default 'pending'
    check (status in ('pending', 'completed', 'failed', 'init_failed')),
  zaincash_transaction_id text,
  created_at timestamptz not null default now()
);

-- ملاحظة: تم استبدال فكرة جدول "subscriptions" منفصل بحقل purchases.expires_at
-- (يُضاف بـ 0005_subscriptions_and_refunds.sql) - أبسط ويكفي لنموذج "اشتراك لكل درس"
-- المعتمد فعلياً بهذا المشروع، فما فيه داعي لجدول منفصل غير مستخدم.

-- ----------------------------------------------------------------------------
-- 6. سجل الأرباح (Append-only Ledger) - أهم جدول بالنظام
-- ----------------------------------------------------------------------------
create table ledger (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('sale', 'refund', 'payout', 'agent_payout')),
  lesson_id uuid references lessons(id),
  student_id uuid references profiles(id),
  teacher_id uuid references teachers(id),
  agent_id uuid references agents(id),
  gross_amount numeric(12,2) not null default 0,
  agent_share numeric(12,2) not null default 0,
  platform_share numeric(12,2) not null default 0,
  teacher_share numeric(12,2) not null default 0,
  store_commission numeric(12,2) not null default 0,
  store_transaction_id text,
  store_name text,
  note text,
  recorded_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- قيد فريد جزئي: يمنع تسجيل نفس عملية البيع مرتين (يسمح بتعدد صفوف null لعمليات الدفع اليدوية)
create unique index ledger_store_transaction_unique
  on ledger (store_transaction_id)
  where store_transaction_id is not null;

-- **الضمانة الأهم**: يمنع التعديل أو الحذف نهائياً على مستوى قاعدة البيانات نفسها،
-- حتى لو استُخدم service_role - أي خطأ يُصحَّح بسطر جديد يعاكسه، أبداً بتعديل التاريخ.
create or replace function prevent_ledger_mutation()
returns trigger as $$
begin
  raise exception 'ledger is append-only: % is not allowed on this table', TG_OP;
end;
$$ language plpgsql;

create trigger ledger_no_update
before update on ledger
for each row execute function prevent_ledger_mutation();

create trigger ledger_no_delete
before delete on ledger
for each row execute function prevent_ledger_mutation();

-- ----------------------------------------------------------------------------
-- 7. دالة مساعدة للتحقق من الصلاحيات (تُستخدم بسياسات RLS)
-- ----------------------------------------------------------------------------
create or replace function is_admin()
returns boolean as $$
  select exists (
    select 1 from profiles where id = auth.uid() and role = 'admin'
  );
$$ language sql security definer stable;

create or replace function is_lesson_owner(p_lesson_id uuid)
returns boolean as $$
  select exists (
    select 1 from lessons where id = p_lesson_id and teacher_id = auth.uid()
  );
$$ language sql security definer stable;
