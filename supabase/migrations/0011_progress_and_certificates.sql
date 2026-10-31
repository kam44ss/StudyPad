-- ============================================================================
-- تتبع تقدم الطالب + شهادات الإتمام
-- ============================================================================

create table lesson_progress (
  student_id uuid not null references profiles(id) on delete cascade,
  lesson_id uuid not null references lessons(id) on delete cascade,
  completed boolean not null default false,
  completed_at timestamptz,
  primary key (student_id, lesson_id)
);

alter table lesson_progress enable row level security;

-- الطالب يدير تقدمه الخاص فقط (ليس مالياً، فلا حاجة لحصره بـ service_role)
create policy lesson_progress_select on lesson_progress
  for select using (student_id = auth.uid() or is_admin() or is_lesson_owner(lesson_id));

create policy lesson_progress_upsert on lesson_progress
  for insert with check (student_id = auth.uid() and is_lesson_purchaser(lesson_id));

create policy lesson_progress_update on lesson_progress
  for update using (student_id = auth.uid());

-- ----------------------------------------------------------------------------
-- الشهادات: تُصدر تلقائياً عند إكمال كل دروس حزمة معيّنة
-- ----------------------------------------------------------------------------
create table certificates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles(id),
  bundle_id uuid not null references bundles(id),
  certificate_code text not null unique default encode(gen_random_bytes(8), 'hex'),
  issued_at timestamptz not null default now(),
  unique (student_id, bundle_id)
);

alter table certificates enable row level security;

-- الشهادة تُتحقق منها علناً بالكود (لأي طرف ثالث يريد التحقق من صحتها) + صاحبها يشوفها
create policy certificates_select on certificates
  for select using (true);

-- ----------------------------------------------------------------------------
-- دالة: الطالب يعلّم درس كمكتمل، وتتحقق تلقائياً هل أكمل حزمة كاملة فتصدر شهادة
-- ----------------------------------------------------------------------------
create or replace function mark_lesson_complete(p_lesson_id uuid, p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_bundle record;
  v_total_lessons integer;
  v_completed_lessons integer;
  v_new_certificates jsonb := '[]'::jsonb;
  v_cert_id uuid;
begin
  if not exists (
    select 1 from purchases
    where student_id = p_student_id and lesson_id = p_lesson_id and status = 'verified'
  ) then
    raise exception 'not_purchased' using errcode = 'P0030';
  end if;

  insert into lesson_progress (student_id, lesson_id, completed, completed_at)
  values (p_student_id, p_lesson_id, true, now())
  on conflict (student_id, lesson_id)
  do update set completed = true, completed_at = now();

  -- نتحقق من كل حزمة تحتوي هذا الدرس: هل الطالب أكمل كل دروسها؟
  for v_bundle in
    select b.id, b.title from bundles b
    join bundle_lessons bl on bl.bundle_id = b.id
    where bl.lesson_id = p_lesson_id
  loop
    select count(*) into v_total_lessons
      from bundle_lessons where bundle_id = v_bundle.id;

    select count(*) into v_completed_lessons
      from bundle_lessons bl
      join lesson_progress lp on lp.lesson_id = bl.lesson_id
        and lp.student_id = p_student_id and lp.completed = true
      where bl.bundle_id = v_bundle.id;

    if v_total_lessons > 0 and v_total_lessons = v_completed_lessons then
      insert into certificates (student_id, bundle_id)
      values (p_student_id, v_bundle.id)
      on conflict (student_id, bundle_id) do nothing
      returning id into v_cert_id;

      if v_cert_id is not null then
        v_new_certificates := v_new_certificates || jsonb_build_object(
          'bundle_id', v_bundle.id, 'bundle_title', v_bundle.title, 'certificate_id', v_cert_id
        );
      end if;
    end if;
  end loop;

  return jsonb_build_object('status', 'ok', 'new_certificates', v_new_certificates);
end;
$$;
