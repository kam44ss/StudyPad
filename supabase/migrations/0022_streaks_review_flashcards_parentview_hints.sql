-- ============================================================================
-- 1. سلسلة الأيام المتتالية (Streak) - أسلوب دولينجو
-- ============================================================================

create table student_streaks (
  student_id uuid primary key references profiles(id),
  current_streak integer not null default 0,
  longest_streak integer not null default 0,
  last_activity_date date,
  updated_at timestamptz not null default now()
);

alter table student_streaks enable row level security;

create policy student_streaks_select on student_streaks
  for select using (student_id = auth.uid() or is_admin());

-- تُستدعى عند أي نشاط تعليمي حقيقي (إجابة سؤال، إكمال درس)
create or replace function record_daily_activity(p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row student_streaks%rowtype;
  v_today date := current_date;
begin
  select * into v_row from student_streaks where student_id = p_student_id for update;

  if not found then
    insert into student_streaks (student_id, current_streak, longest_streak, last_activity_date)
    values (p_student_id, 1, 1, v_today);
    return jsonb_build_object('current_streak', 1, 'longest_streak', 1);
  end if;

  if v_row.last_activity_date = v_today then
    return jsonb_build_object('current_streak', v_row.current_streak, 'longest_streak', v_row.longest_streak);
  elsif v_row.last_activity_date = v_today - 1 then
    update student_streaks
      set current_streak = current_streak + 1,
          longest_streak = greatest(longest_streak, current_streak + 1),
          last_activity_date = v_today,
          updated_at = now()
      where student_id = p_student_id
      returning current_streak, longest_streak into v_row.current_streak, v_row.longest_streak;
  else
    update student_streaks
      set current_streak = 1,
          last_activity_date = v_today,
          updated_at = now()
      where student_id = p_student_id
      returning current_streak, longest_streak into v_row.current_streak, v_row.longest_streak;
  end if;

  return jsonb_build_object('current_streak', v_row.current_streak, 'longest_streak', v_row.longest_streak);
end;
$$;

-- ----------------------------------------------------------------------------
-- 2. تكرار متباعد للأسئلة الخاطئة (Spaced Repetition مبسّط)
--    نضيف وضع 'review' لدالة التمارين الموحّدة الموجودة أصلاً
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
  if p_mode not in ('daily', 'custom', 'mock_exam', 'review') then
    raise exception 'invalid_mode' using errcode = 'P0060';
  end if;

  if p_mode = 'mock_exam' then
    if p_bundle_id is null then
      raise exception 'bundle_id_required' using errcode = 'P0061';
    end if;
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

  elsif p_mode = 'review' then
    -- أسئلة أخطأ فيها الطالب بآخر محاولة له عليها فقط (لو صحّحها لاحقاً ما ترجع تظهر)
    -- أقدم خطأ غير مُراجَع يظهر أول - نفس مبدأ التكرار المتباعد المبسّط
    select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'text', x.text, 'choices', x.choices)), '[]'::jsonb)
    into v_questions
    from (
      select distinct on (q.id) q.id, q.text, q.choices, qa.correct, qa.created_at
      from quiz_attempts qa
      join quiz_questions q on q.id = qa.question_id
      join purchases pu on pu.lesson_id = q.lesson_id
      where qa.student_id = p_student_id and pu.status = 'verified'
      order by q.id, qa.created_at desc
    ) x
    where x.correct = false
    order by x.created_at asc
    limit p_count;

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

-- ----------------------------------------------------------------------------
-- 3. بطاقات تعليمية (Flashcards) - أسلوب Quizlet، للقوانين والتعريفات
-- ----------------------------------------------------------------------------
create table flashcards (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  front_text text not null,
  back_text text not null,
  order_index integer not null default 0
);

alter table flashcards enable row level security;

create policy flashcards_select on flashcards
  for select using (is_lesson_purchaser(lesson_id) or is_lesson_owner(lesson_id) or is_admin());

create policy flashcards_write on flashcards
  for all using (is_lesson_owner(lesson_id));

-- ----------------------------------------------------------------------------
-- 4. رابط متابعة لولي الأمر (قراءة فقط، بدون تسجيل دخول)
-- ----------------------------------------------------------------------------
create table parent_view_tokens (
  token text primary key default encode(gen_random_bytes(12), 'hex'),
  student_id uuid not null references profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table parent_view_tokens enable row level security;

create policy parent_view_tokens_select on parent_view_tokens
  for select using (student_id = auth.uid() or is_admin());

create policy parent_view_tokens_insert on parent_view_tokens
  for insert with check (student_id = auth.uid());

-- دالة عامة تُستخدم من صفحة ولي الأمر - تكشف فقط التقدم، بدون أي بيانات حساسة
create or replace function get_parent_view(p_token text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_student_id uuid;
  v_student_name text;
  v_lessons jsonb;
  v_certificates jsonb;
  v_streak record;
begin
  select student_id into v_student_id from parent_view_tokens where token = p_token;
  if v_student_id is null then
    return jsonb_build_object('valid', false);
  end if;

  select coalesce(nickname, 'الطالب') into v_student_name from profiles where id = v_student_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'title', l.title, 'completed', lp.completed
  )), '[]'::jsonb)
  into v_lessons
  from purchases pu
  join lessons l on l.id = pu.lesson_id
  left join lesson_progress lp on lp.lesson_id = pu.lesson_id and lp.student_id = pu.student_id
  where pu.student_id = v_student_id and pu.status = 'verified';

  select coalesce(jsonb_agg(jsonb_build_object('bundle_title', b.title, 'issued_at', c.issued_at)), '[]'::jsonb)
  into v_certificates
  from certificates c
  join bundles b on b.id = c.bundle_id
  where c.student_id = v_student_id;

  select current_streak, longest_streak into v_streak from student_streaks where student_id = v_student_id;

  return jsonb_build_object(
    'valid', true,
    'student_name', v_student_name,
    'lessons', v_lessons,
    'certificates', v_certificates,
    'current_streak', coalesce(v_streak.current_streak, 0),
    'longest_streak', coalesce(v_streak.longest_streak, 0)
  );
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. تلميحات محلية بدون أي مفتاح API أو ذكاء اصطناعي:
--    (أ) تلميح نصي يكتبه المدرس نفسه لكل سؤال (اختياري)
--    (ب) "احذف إجابتين خاطئتين" محسوبة عشوائياً بالسيرفر بدون كشف الإجابة الصحيحة
-- ----------------------------------------------------------------------------
alter table quiz_questions add column hint text;

create or replace function get_answer_hint(p_question_id uuid, p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_question quiz_questions%rowtype;
  v_lesson_id uuid;
  v_wrong_indexes int[];
  v_eliminate int;
begin
  select * into v_question from quiz_questions where id = p_question_id;
  if not found then
    raise exception 'question_not_found' using errcode = 'P0070';
  end if;

  if not exists (
    select 1 from purchases
    where student_id = p_student_id and lesson_id = v_question.lesson_id and status = 'verified'
  ) then
    raise exception 'not_purchased' using errcode = 'P0030';
  end if;

  -- نجمع كل فهارس الخيارات الخاطئة (غير فهرس الإجابة الصحيحة)
  select array_agg(idx - 1) into v_wrong_indexes
  from jsonb_array_elements(v_question.choices) with ordinality as t(val, idx)
  where idx - 1 <> v_question.correct_index;

  if v_wrong_indexes is null or array_length(v_wrong_indexes, 1) < 2 then
    -- سؤال بخيارين بس - ما نقدر نحذف خيارين خطأ ونخلي شي يتبقى
    return jsonb_build_object('eliminated_indexes', '[]'::jsonb, 'hint', v_question.hint);
  end if;

  -- نختار عشوائياً خيارين خطأ للحذف (نبقي خيار خطأ واحد + الصحيح للطالب يختار بينهم)
  v_eliminate := array_length(v_wrong_indexes, 1);
  v_wrong_indexes := (
    select array_agg(x) from (
      select unnest(v_wrong_indexes) as x order by random() limit greatest(v_eliminate - 1, 0)
    ) t
  );

  return jsonb_build_object(
    'eliminated_indexes', to_jsonb(coalesce(v_wrong_indexes, array[]::int[])),
    'hint', v_question.hint
  );
end;
$$;
