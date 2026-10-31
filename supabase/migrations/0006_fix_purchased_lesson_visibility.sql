-- ============================================================================
-- إصلاح: درس تم شراؤه ثم أصبح "غير منشور" لاحقاً (draft/hidden) كان يختفي من
-- قائمة "دروسي" عند الطالب اللي اشتراه فعلاً - RLS كانت تسمح فقط بالدروس
-- المنشورة أو دروس المدرس نفسه، بدون استثناء لمن اشترى الدرس مسبقاً.
-- ملاحظة: هذا لا يؤثر على حجب المحتوى نفسه (get-lesson-content تتحقق من
-- الشراء بشكل منفصل بصلاحيات service_role وتتجاوز RLS أصلاً) - هذا فقط يصلح
-- ظهور الدرس بقائمة الطالب.
-- ============================================================================

create or replace function is_lesson_purchaser(p_lesson_id uuid)
returns boolean as $$
  select exists (
    select 1 from purchases
    where lesson_id = p_lesson_id
      and student_id = auth.uid()
      and status = 'verified'
  );
$$ language sql security definer stable;

drop policy if exists lessons_select on lessons;

create policy lessons_select on lessons
  for select using (
    status = 'published'
    or is_admin()
    or teacher_id = auth.uid()
    or is_lesson_purchaser(id)
  );
