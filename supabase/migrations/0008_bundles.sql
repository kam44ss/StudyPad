-- ============================================================================
-- حزم/كورسات (بيع عدة دروس بكود أو عملية دفع واحدة) - نموذج مرماز/أبواب
-- الحزمة مملوكة لمدرس واحد فقط (نفس نموذج الدرس) لتفادي تعقيد توزيع الأرباح
-- بين أكثر من مدرس بعملية بيع واحدة.
-- ============================================================================

create table bundles (
  id uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references teachers(id),
  title text not null,
  subject text,
  price numeric(12,2) not null check (price >= 0),
  status text not null default 'draft' check (status in ('draft', 'published', 'hidden')),
  created_at timestamptz not null default now()
);

create table bundle_lessons (
  bundle_id uuid not null references bundles(id) on delete cascade,
  lesson_id uuid not null references lessons(id) on delete cascade,
  primary key (bundle_id, lesson_id)
);

alter table bundles enable row level security;
alter table bundle_lessons enable row level security;

create policy bundles_select on bundles
  for select using (status = 'published' or is_admin() or teacher_id = auth.uid());

create policy bundles_insert on bundles
  for insert with check (teacher_id = auth.uid());

create policy bundles_update on bundles
  for update using (teacher_id = auth.uid() or is_admin());

create or replace function is_bundle_owner(p_bundle_id uuid)
returns boolean as $$
  select exists (
    select 1 from bundles where id = p_bundle_id and teacher_id = auth.uid()
  );
$$ language sql security definer stable;

create policy bundle_lessons_select on bundle_lessons
  for select using (
    is_bundle_owner(bundle_id) or is_admin()
    or exists (select 1 from bundles where id = bundle_id and status = 'published')
  );

create policy bundle_lessons_write on bundle_lessons
  for all using (is_bundle_owner(bundle_id));

-- ----------------------------------------------------------------------------
-- تعديلات على الجداول الموجودة لدعم الحزم
-- ----------------------------------------------------------------------------

-- redemption_codes: الكود إما لدرس واحد أو لحزمة كاملة، وليس الاثنين معاً
alter table redemption_codes alter column lesson_id drop not null;
alter table redemption_codes add column bundle_id uuid references bundles(id);
alter table redemption_codes add constraint redemption_codes_target_check
  check (
    (lesson_id is not null and bundle_id is null) or
    (lesson_id is null and bundle_id is not null)
  );

-- zaincash_orders: نفس المبدأ
alter table zaincash_orders alter column lesson_id drop not null;
alter table zaincash_orders add column bundle_id uuid references bundles(id);
alter table zaincash_orders add constraint zaincash_orders_target_check
  check (
    (lesson_id is not null and bundle_id is null) or
    (lesson_id is null and bundle_id is not null)
  );

-- purchases: شراء حزمة ينتج عدة صفوف (صف لكل درس) بنفس store_transaction_id،
-- فالقيد الفريد القديم على store_transaction_id لحاله يمنع هذا - نوسّعه ليشمل lesson_id
alter table purchases drop constraint purchases_store_transaction_id_key;
alter table purchases add constraint purchases_transaction_lesson_unique
  unique (store_transaction_id, lesson_id);

-- ledger: نضيف bundle_id للتوثيق فقط (سطر واحد بالـ ledger يمثّل كامل عملية بيع الحزمة)
alter table ledger add column bundle_id uuid references bundles(id);
