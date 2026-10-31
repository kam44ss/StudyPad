-- ============================================================================
-- تقييمات ومراجعات الطلاب على الدروس
-- ============================================================================

create table lesson_reviews (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references lessons(id) on delete cascade,
  student_id uuid not null references profiles(id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_id, student_id) -- تقييم واحد لكل طالب لكل درس (يعدّله لاحقاً بدل تكراره)
);

alter table lesson_reviews enable row level security;

-- القراءة عامة لأي درس منشور - المراجعات جزء من قرار الشراء
create policy lesson_reviews_select on lesson_reviews
  for select using (
    exists (select 1 from lessons where id = lesson_id and status = 'published')
    or is_admin()
  );

-- الكتابة فقط لمن اشترى الدرس فعلاً (نفس دالة is_lesson_purchaser من 0006)
create policy lesson_reviews_insert on lesson_reviews
  for insert with check (
    student_id = auth.uid() and is_lesson_purchaser(lesson_id)
  );

create policy lesson_reviews_update on lesson_reviews
  for update using (student_id = auth.uid());

create policy lesson_reviews_delete on lesson_reviews
  for delete using (student_id = auth.uid() or is_admin());

-- تحديث updated_at تلقائياً عند التعديل
create or replace function touch_review_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger lesson_reviews_touch
before update on lesson_reviews
for each row execute function touch_review_updated_at();

-- دالة مساعدة: متوسط التقييم وعدد المراجعات لدرس معيّن (تُستخدم بالواجهة)
create or replace function get_lesson_rating(p_lesson_id uuid)
returns jsonb
language sql
stable
as $$
  select jsonb_build_object(
    'average', coalesce(round(avg(rating)::numeric, 1), 0),
    'count', count(*)
  )
  from lesson_reviews
  where lesson_id = p_lesson_id;
$$;
