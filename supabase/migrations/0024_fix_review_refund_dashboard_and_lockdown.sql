-- ============================================================================
-- 0024: إصلاحات بعد اختبار شامل على Postgres 16 حقيقي
-- ============================================================================
-- (1) مراجعة الأخطاء (mode = 'review') كانت تفشل دائماً بخطأ SQL
--     "column x.created_at must appear in the GROUP BY clause"،
--     وLIMIT كانت ستُطبَّق على صف التجميع الوحيد بدل الأسئلة.
-- (2) لوحة الأدمن: get_admin_dashboard_stats تفحص is_admin() المعتمدة على auth.uid()،
--     لكن الـ Edge Function تستدعيها بمفتاح service_role (بدون مستخدم) فكانت ترجع
--     admin_only دائماً حتى للأدمن الحقيقي.
-- (3) الاسترجاع (record_refund) كان يفشل دائماً لأي عملية بيع مدفوعة: صف الاسترجاع
--     يستخدم نفس store_transaction_id الخاص بصف البيع، والفهرس الفريد كان شاملاً لكل
--     الأنواع. صار الفهرس الفريد للبيع فقط + فهرس فريد منفصل للاسترجاع.
-- (4) أمان: كل دوال الـ RPC كانت قابلة للاستدعاء مباشرة من أي مستخدم مسجل (وحتى
--     الزائر) عبر /rest/v1/rpc/... لأن Postgres يمنح EXECUTE لـ PUBLIC افتراضياً.
--     مثال مُثبت بالاختبار: طالب عادي استطاع تسجيل دفعة وكيل وهمية بالدفتر
--     (record_agent_payout) وقراءة أرباح أي مدرس/وكيل. الآن الدوال الداخلية
--     مقتصرة على service_role (أي على الـ Edge Functions فقط).
--     تبقى متاحة للعميل فقط: دوال مساعدة سياسات RLS، وverify_certificate،
--     وget_parent_view (تُستدعى من صفحات عامة بدون تسجيل دخول).
-- ملاحظة: أي دالة جديدة تُضاف مستقبلاً داخل public ستكون قابلة للاستدعاء من العميل
--     افتراضياً - أضف لها revoke execute ... from public, anon, authenticated.
-- ============================================================================

-- ------------------------------ (1) review ----------------------------------
CREATE OR REPLACE FUNCTION public.generate_practice_set(p_student_id uuid, p_mode text, p_subject text DEFAULT NULL::text, p_count integer DEFAULT 10, p_bundle_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
    select coalesce(
             jsonb_agg(jsonb_build_object('id', x.id, 'text', x.text, 'choices', x.choices)
                       order by x.created_at asc),
             '[]'::jsonb)
    into v_questions
    from (
      select d.id, d.text, d.choices, d.created_at
      from (
        select distinct on (q.id) q.id, q.text, q.choices, qa.correct, qa.created_at
        from quiz_attempts qa
        join quiz_questions q on q.id = qa.question_id
        join purchases pu on pu.lesson_id = q.lesson_id
        where qa.student_id = p_student_id and pu.status = 'verified'
        order by q.id, qa.created_at desc
      ) d
      where d.correct = false
      order by d.created_at asc
      limit p_count
    ) x;

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
$function$;

-- --------------------------- (2) admin dashboard ----------------------------
CREATE OR REPLACE FUNCTION public.get_admin_dashboard_stats()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_total_revenue numeric(12,2);
  v_total_platform_share numeric(12,2);
  v_total_sales_count integer;
  v_total_students integer;
  v_total_teachers integer;
  v_top_lessons jsonb;
  v_revenue_last_30_days numeric(12,2);
begin
  if auth.role() is distinct from 'service_role' and not is_admin() then
    raise exception 'admin_only' using errcode = 'P0050';
  end if;

  select
    coalesce(sum(gross_amount) filter (where type = 'sale'), 0)
      + coalesce(sum(gross_amount) filter (where type = 'refund'), 0),
    coalesce(sum(platform_share) filter (where type = 'sale'), 0)
      + coalesce(sum(platform_share) filter (where type = 'refund'), 0),
    coalesce(count(*) filter (where type = 'sale'), 0)
  into v_total_revenue, v_total_platform_share, v_total_sales_count
  from ledger;

  select coalesce(sum(gross_amount), 0) into v_revenue_last_30_days
  from ledger where type = 'sale' and created_at > now() - interval '30 days';

  select count(*) into v_total_students from profiles where role = 'student';
  select count(*) into v_total_teachers from teachers where status = 'active';

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_top_lessons
  from (
    select l.id, l.title, count(*) as sales_count, sum(led.gross_amount) as revenue
    from ledger led
    join lessons l on l.id = led.lesson_id
    where led.type = 'sale'
    group by l.id, l.title
    order by sales_count desc
    limit 5
  ) t;

  return jsonb_build_object(
    'total_revenue', v_total_revenue,
    'total_platform_share', v_total_platform_share,
    'total_sales_count', v_total_sales_count,
    'total_students', v_total_students,
    'total_teachers', v_total_teachers,
    'revenue_last_30_days', v_revenue_last_30_days,
    'top_lessons', v_top_lessons
  );
end;
$function$;

-- ------------------------------ (3) ledger ----------------------------------
-- الفهرس القديم ledger_store_transaction_unique كان يشمل كل الأنواع فيمنع صف
-- الاسترجاع. نستبدله بفهرسين جزئيين: بيع واحد فقط، واسترجاع واحد فقط لكل عملية.
drop index if exists ledger_store_transaction_unique;

create unique index ledger_sale_store_transaction_unique
  on ledger (store_transaction_id)
  where store_transaction_id is not null and type = 'sale';

create unique index ledger_refund_store_transaction_unique
  on ledger (store_transaction_id)
  where store_transaction_id is not null and type = 'refund';

-- ------------------------------ (4) lockdown --------------------------------
revoke execute on function
  generate_practice_set(uuid, text, text, integer, uuid),
  get_admin_dashboard_stats(),
  get_agent_earnings(uuid),
  get_teacher_earnings(uuid),
  get_answer_hint(uuid, uuid),
  get_leaderboard(integer),
  mark_lesson_complete(uuid, uuid),
  maybe_grant_referral_reward(uuid),
  record_agent_payout(uuid, numeric, text, uuid),
  record_teacher_payout(uuid, numeric, text, uuid),
  record_daily_activity(uuid),
  record_refund(uuid, uuid, text),
  record_zaincash_result(uuid, boolean),
  redeem_code(text, uuid),
  validate_discount_code(text)
from public, anon, authenticated;

grant execute on function
  generate_practice_set(uuid, text, text, integer, uuid),
  get_admin_dashboard_stats(),
  get_agent_earnings(uuid),
  get_teacher_earnings(uuid),
  get_answer_hint(uuid, uuid),
  get_leaderboard(integer),
  mark_lesson_complete(uuid, uuid),
  maybe_grant_referral_reward(uuid),
  record_agent_payout(uuid, numeric, text, uuid),
  record_teacher_payout(uuid, numeric, text, uuid),
  record_daily_activity(uuid),
  record_refund(uuid, uuid, text),
  record_zaincash_result(uuid, boolean),
  redeem_code(text, uuid),
  validate_discount_code(text)
to service_role;
