-- ============================================================================
-- لوحة تحليلات الأدمن: أرباح، أفضل الدروس مبيعاً، إحصائيات عامة
-- ============================================================================

create or replace function get_admin_dashboard_stats()
returns jsonb
language plpgsql
security definer
as $$
declare
  v_total_revenue numeric(12,2);
  v_total_platform_share numeric(12,2);
  v_total_sales_count integer;
  v_total_students integer;
  v_total_teachers integer;
  v_top_lessons jsonb;
  v_revenue_last_30_days numeric(12,2);
begin
  if not is_admin() then
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
$$;
