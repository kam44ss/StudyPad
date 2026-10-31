-- ============================================================================
-- تخزين ملفات محتوى الدروس (فيديو/PDF) - Supabase Storage
-- Bucket خاص (private) تماماً - لا وصول عام إطلاقاً، فقط روابط موقّعة مؤقتة
-- تُولَّد من get-lesson-content بعد التحقق من الشراء.
-- ============================================================================

insert into storage.buckets (id, name, public)
values ('lesson-content', 'lesson-content', false)
on conflict (id) do nothing;

-- تنظيم الملفات بمسار: {lesson_id}/{filename} - نستخدم هذا لمطابقة صلاحية المدرس
-- عبر استخراج أول جزء من المسار (foldername) ومقارنته بدرس يملكه هو

create policy teacher_can_upload_own_lesson_files
on storage.objects for insert
with check (
  bucket_id = 'lesson-content'
  and is_lesson_owner((storage.foldername(name))[1]::uuid)
);

create policy teacher_can_manage_own_lesson_files
on storage.objects for all
using (
  bucket_id = 'lesson-content'
  and (is_lesson_owner((storage.foldername(name))[1]::uuid) or is_admin())
);

-- ملاحظة: لا توجد سياسة SELECT عامة أو للطلاب على storage.objects عن قصد -
-- الملفات تُخدَّم فقط عبر روابط موقّعة (signed URLs) تولّدها get-lesson-content
-- بصلاحيات service_role بعد التحقق من وجود عملية شراء فعلية.
