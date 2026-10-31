-- ============================================================================
-- 1. شرح الإجابة الصحيحة (يظهر بعد الإجابة، بغض النظر صح أو خطأ)
-- 2. ميزة سؤال وجواب - الطالب يسأل، المدرس أو أي طالب ثاني يجاوب
-- ============================================================================

alter table quiz_questions add column explanation text;

create table lesson_questions (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  student_id uuid not null references profiles(id),
  question_text text not null,
  created_at timestamptz not null default now()
);

create table lesson_answers (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references lesson_questions(id) on delete cascade,
  responder_id uuid not null references profiles(id),
  answer_text text not null,
  is_teacher_answer boolean not null default false,
  created_at timestamptz not null default now()
);

alter table lesson_questions enable row level security;
alter table lesson_answers enable row level security;

-- القراءة: أي طالب اشترى الدرس، أو المدرس، أو الأدمن
create policy lesson_questions_select on lesson_questions
  for select using (
    is_lesson_purchaser(lesson_id) or is_lesson_owner(lesson_id) or is_admin()
  );

create policy lesson_questions_insert on lesson_questions
  for insert with check (
    student_id = auth.uid() and is_lesson_purchaser(lesson_id)
  );

create policy lesson_answers_select on lesson_answers
  for select using (
    exists (
      select 1 from lesson_questions lq
      where lq.id = question_id
        and (is_lesson_purchaser(lq.lesson_id) or is_lesson_owner(lq.lesson_id) or is_admin())
    )
  );

-- أي طالب اشترى نفس الدرس يقدر يجاوب (تعاون بين الطلاب)، أو المدرس نفسه
create policy lesson_answers_insert on lesson_answers
  for insert with check (
    responder_id = auth.uid() and
    exists (
      select 1 from lesson_questions lq
      where lq.id = question_id
        and (is_lesson_purchaser(lq.lesson_id) or is_lesson_owner(lq.lesson_id))
    )
  );
