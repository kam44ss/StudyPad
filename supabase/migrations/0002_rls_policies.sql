-- ============================================================================
-- سياسات أمان مستوى الصف (Row Level Security)
-- كل جدول يُفعَّل عليه RLS، وأي عملية Cloud/Edge Function تستخدم service_role
-- تتجاوز RLS تلقائياً (نفس مبدأ Firebase Admin SDK) - لهذا الجداول المالية
-- ما تحتاج سياسة INSERT/UPDATE للعميل العادي إطلاقاً.
-- ============================================================================

alter table profiles enable row level security;
alter table teachers enable row level security;
alter table agents enable row level security;
alter table lessons enable row level security;
alter table lesson_content enable row level security;
alter table quiz_questions enable row level security;
alter table purchases enable row level security;
alter table redemption_codes enable row level security;
alter table zaincash_orders enable row level security;
alter table ledger enable row level security;

-- ------- profiles -------
create policy profiles_select on profiles
  for select using (auth.uid() = id or is_admin());

create policy profiles_insert on profiles
  for insert with check (auth.uid() = id);

create policy profiles_update on profiles
  for update using (auth.uid() = id or is_admin());

-- ------- teachers (بروفايل عام، القراءة مفتوحة) -------
create policy teachers_select on teachers
  for select using (true);

create policy teachers_update on teachers
  for update using (auth.uid() = id or is_admin());
  -- ملاحظة: حماية الحقول المالية تصير عبر trigger protect_teacher_financials أعلاه

-- ------- agents (خاص بالأدمن فقط) -------
create policy agents_select on agents
  for select using (is_admin());
-- لا توجد سياسة insert/update/delete للعميل: فقط عبر service_role (createAgent Edge Function)

-- ------- lessons -------
create policy lessons_select on lessons
  for select using (status = 'published' or is_admin() or teacher_id = auth.uid());

create policy lessons_insert on lessons
  for insert with check (teacher_id = auth.uid());

create policy lessons_update on lessons
  for update using (teacher_id = auth.uid() or is_admin());

-- ------- lesson_content / quiz_questions -------
-- ما تُقرأ مباشرة أبداً من العميل العادي؛ تُخدَّم فقط عبر Edge Function ترجع رابط موقّع
-- بعد التحقق من وجود شراء فعلي (نفس مبدأ Firestore: allow read: if false)
create policy lesson_content_select on lesson_content
  for select using (is_admin() or is_lesson_owner(lesson_id));

create policy lesson_content_write on lesson_content
  for all using (is_lesson_owner(lesson_id));

create policy quiz_questions_select on quiz_questions
  for select using (is_admin() or is_lesson_owner(lesson_id));

create policy quiz_questions_write on quiz_questions
  for all using (is_lesson_owner(lesson_id));

-- ------- purchases: قراءة فقط، الكتابة حصراً عبر service_role -------
create policy purchases_select on purchases
  for select using (
    student_id = auth.uid() or teacher_id = auth.uid() or is_admin()
  );

-- ------- redemption_codes: لا قراءة ولا كتابة من العميل، فقط الأدمن يقرأ (للوحة التوليد) -------
create policy redemption_codes_select on redemption_codes
  for select using (is_admin());

-- ------- zaincash_orders -------
create policy zaincash_orders_select on zaincash_orders
  for select using (student_id = auth.uid() or is_admin());

-- ------- ledger: الأدمن فقط يقرأ، ولا كتابة أو تعديل أو حذف من أي أحد عبر RLS
--         (وحتى service_role نفسه ممنوع فعلياً من التعديل/الحذف بسبب trigger منفصل) -------
create policy ledger_select on ledger
  for select using (is_admin());
