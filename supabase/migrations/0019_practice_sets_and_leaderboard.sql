-- ============================================================================
-- تتبع محاولات الاختبار (لحساب الدوري/الصدارة) + منصة تمارين موحّدة
-- (اختبار يومي، اختبار مخصص، امتحان شامل تجريبي) - كلها تستخدم نفس الآلية
-- ============================================================================

create table quiz_attempts (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references profiles(id),
  question_id uuid not null references quiz_questions(id) on delete cascade,
  correct boolean not null,
  created_at timestamptz not null default now()
);

alter table quiz_attempts enable row level security;

create policy quiz_attempts_select on quiz_attempts
  for select using (student_id = auth.uid() or is_admin());
-- لا سياسة insert للعميل - فقط عبر check-quiz-answer (service_role)

-- لقب اختياري يختاره الطالب بنفسه لعرضه بلوحة الصدارة (بدل الاسم/الإيميل الحقيقي حفاظاً على الخصوصية)
alter table profiles add column nickname text;

-- ----------------------------------------------------------------------------
-- لوحة الصدارة: أكثر الطلاب إجابات صحيحة (بدون كشف أي بيانات حساسة، فقط اللقب)
-- ----------------------------------------------------------------------------
create or replace function get_leaderboard(p_limit int default 20)
returns jsonb
language sql
security definer
stable
as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb)
  from (
    select
      coalesce(p.nickname, 'طالب') as display_name,
      count(*) filter (where qa.correct) as correct_count,
      count(*) as total_attempts
    from quiz_attempts qa
    join profiles p on p.id = qa.student_id
    group by p.id, p.nickname
    order by correct_count desc
    limit p_limit
  ) t;
$$;

-- ----------------------------------------------------------------------------
-- توليد مجموعة تمارين موحّدة - نفس الآلية لثلاث حالات:
--   'daily'     -> مجموعة يومية ثابتة (تتغيّر كل يوم) من كل دروس الطالب المشتراة
--   'custom'    -> مجموعة عشوائية بعدد يحدده الطالب، اختياري تصفية بمادة معيّنة
--   'mock_exam' -> كل أسئلة حزمة معيّنة (يجب أن يكون الطالب اشترى الحزمة كاملة)
-- الأمان: تُرجع فقط أسئلة من دروس اشتراها الطالب فعلياً (نفس مبدأ is_lesson_purchaser)
-- ولا ترجع correct_index أبداً - نفس مبدأ get-lesson-content.
-- ----------------------------------------------------------------------------
create or replace function generate_practice_set(
  p_student_id uuid,
  p_mode text,
  p_subject text default null,
  p_count int default 10,
  p_bundle_id uuid default null
)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_questions jsonb;
  v_seed double precision;
begin
  if p_mode not in ('daily', 'custom', 'mock_exam') then
    raise exception 'invalid_mode' using errcode = 'P0060';
  end if;

  if p_mode = 'mock_exam' then
    if p_bundle_id is null then
      raise exception 'bundle_id_required' using errcode = 'P0061';
    end if;
    -- تحقق إن الطالب اشترى كل دروس الحزمة (مش درس واحد بس)
    if exists (
      select 1 from bundle_lessons bl
      where bl.bundle_id = p_bundle_id
        and not exists (
          select 1 from purchases pu
          where pu.lesson_id = bl.lesson_id and pu.student_id = p_student_id and pu.status = 'verified'
        )
    ) then
      raise exception 'bundle_not_fully_purchased' using errcode = 'P0062';
    end if;

    select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'text', q.text, 'choices', q.choices)), '[]'::jsonb)
    into v_questions
    from quiz_questions q
    join bundle_lessons bl on bl.lesson_id = q.lesson_id
    where bl.bundle_id = p_bundle_id;

  elsif p_mode = 'daily' then
    -- بذرة ثابتة لليوم الحالي فقط، عشان نفس المجموعة تتكرر لنفس الطالب طول اليوم
    v_seed := extract(epoch from date_trunc('day', now()))::double precision;
    perform setseed(mod(v_seed::numeric, 1)::double precision);

    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'text', t.text, 'choices', t.choices)), '[]'::jsonb)
    into v_questions
    from (
      select q.id, q.text, q.choices
      from quiz_questions q
      join purchases pu on pu.lesson_id = q.lesson_id
      where pu.student_id = p_student_id and pu.status = 'verified'
      order by random()
      limit p_count
    ) t;

  else -- custom
    select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'text', t.text, 'choices', t.choices)), '[]'::jsonb)
    into v_questions
    from (
      select q.id, q.text, q.choices
      from quiz_questions q
      join purchases pu on pu.lesson_id = q.lesson_id
      join lessons l on l.id = q.lesson_id
      where pu.student_id = p_student_id and pu.status = 'verified'
        and (p_subject is null or l.subject = p_subject)
      order by random()
      limit p_count
    ) t;
  end if;

  return jsonb_build_object('mode', p_mode, 'questions', v_questions);
end;
$$;
