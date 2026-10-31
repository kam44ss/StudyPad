-- ============================================================================
-- دوال قاعدة البيانات (RPC) اللي تنفّذ عمليات المحاسبة الحساسة
-- كل دالة هنا تعمل داخل معاملة واحدة ذرية تلقائياً (خاصية أساسية بـ Postgres
-- functions) - إما كل الخطوات تصير مع بعض أو ولا وحدة، تماماً مثل
-- db.runTransaction() المستخدمة سابقاً بـ Firestore، لكن بضمانات ACID حقيقية.
-- تُستدعى فقط من Edge Functions عبر service_role، وليست معرّضة مباشرة للعميل.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- استخدام كود تفعيل: يتحقق، يمنح الوصول، ويسجّل المحاسبة (وكيل → منصة → مدرس)
-- ----------------------------------------------------------------------------
create or replace function redeem_code(p_code text, p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row redemption_codes%rowtype;
  v_teacher teachers%rowtype;
  v_agent agents%rowtype;
  v_gross numeric(12,2);
  v_agent_share numeric(12,2) := 0;
  v_net_after_agent numeric(12,2);
  v_platform_share numeric(12,2) := 0;
  v_teacher_share numeric(12,2) := 0;
begin
  -- قفل الصف (FOR UPDATE) يمنع استخدام نفس الكود مرتين حتى لو وصل طلبان بنفس اللحظة
  select * into v_row from redemption_codes where code = p_code for update;

  if not found then
    raise exception 'invalid_code' using errcode = 'P0001';
  end if;

  if v_row.status <> 'unused' then
    raise exception 'code_already_used' using errcode = 'P0002';
  end if;

  if v_row.expires_at is not null and v_row.expires_at < now() then
    raise exception 'code_expired' using errcode = 'P0003';
  end if;

  select * into v_teacher from teachers where id = v_row.teacher_id;
  if not found then
    raise exception 'teacher_not_found' using errcode = 'P0004';
  end if;

  update redemption_codes
    set status = 'used', used_by = p_student_id, used_at = now()
    where code = p_code;

  insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status)
  values (p_student_id, v_row.lesson_id, v_row.teacher_id, p_code, 'redemption_code', 'verified');

  if v_row.is_paid and v_row.value > 0 then
    v_gross := v_row.value;

    if v_row.agent_id is not null then
      select * into v_agent from agents where id = v_row.agent_id;
      if found then
        v_agent_share := round(v_gross * (v_agent.commission_percent / 100), 2);
      end if;
    end if;

    v_net_after_agent := v_gross - v_agent_share;
    v_platform_share := round(v_net_after_agent * (v_teacher.revenue_share_percent / 100), 2);
    v_teacher_share := round(v_net_after_agent - v_platform_share, 2);

    insert into ledger (
      type, lesson_id, student_id, teacher_id, agent_id,
      gross_amount, agent_share, platform_share, teacher_share,
      store_commission, store_transaction_id, store_name
    ) values (
      'sale', v_row.lesson_id, p_student_id, v_row.teacher_id, v_row.agent_id,
      v_gross, v_agent_share, v_platform_share, v_teacher_share,
      0, p_code, 'redemption_code'
    );

    update teachers set total_earned = total_earned + v_teacher_share where id = v_row.teacher_id;

    if v_row.agent_id is not null and v_agent_share > 0 then
      update agents set total_earned = total_earned + v_agent_share where id = v_row.agent_id;
    end if;
  end if;

  return jsonb_build_object('status', 'redeemed', 'lesson_id', v_row.lesson_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- تسجيل نتيجة عملية دفع زين كاش بعد التحقق من توقيع الـ JWT بالـ Edge Function
-- ----------------------------------------------------------------------------
create or replace function record_zaincash_result(p_order_id uuid, p_success boolean)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_order zaincash_orders%rowtype;
  v_teacher teachers%rowtype;
  v_gross numeric(12,2);
  v_platform_share numeric(12,2);
  v_teacher_share numeric(12,2);
begin
  select * into v_order from zaincash_orders where id = p_order_id for update;

  if not found then
    raise exception 'order_not_found' using errcode = 'P0010';
  end if;

  if v_order.status = 'completed' then
    -- سبق ومعالجناه (idempotency) - لا نكرر
    return jsonb_build_object('status', 'already_processed');
  end if;

  if not p_success then
    update zaincash_orders set status = 'failed' where id = p_order_id;
    return jsonb_build_object('status', 'failed');
  end if;

  select * into v_teacher from teachers where id = v_order.teacher_id;
  if not found then
    raise exception 'teacher_not_found' using errcode = 'P0004';
  end if;

  v_gross := v_order.amount;
  v_platform_share := round(v_gross * (v_teacher.revenue_share_percent / 100), 2);
  v_teacher_share := round(v_gross - v_platform_share, 2);

  insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status)
  values (v_order.student_id, v_order.lesson_id, v_order.teacher_id, p_order_id::text, 'zaincash', 'verified');

  insert into ledger (
    type, lesson_id, student_id, teacher_id,
    gross_amount, platform_share, teacher_share,
    store_commission, store_transaction_id, store_name
  ) values (
    'sale', v_order.lesson_id, v_order.student_id, v_order.teacher_id,
    v_gross, v_platform_share, v_teacher_share,
    0, p_order_id::text, 'zaincash'
  );

  update teachers set total_earned = total_earned + v_teacher_share where id = v_order.teacher_id;
  update zaincash_orders set status = 'completed' where id = p_order_id;

  return jsonb_build_object('status', 'completed', 'lesson_id', v_order.lesson_id);
end;
$$;

-- ----------------------------------------------------------------------------
-- تسجيل دفعة فعلية دفعتها لمدرس أو وكيل (سطر دائم بالـ ledger)
-- ----------------------------------------------------------------------------
create or replace function record_teacher_payout(
  p_teacher_id uuid, p_amount numeric, p_note text, p_recorded_by uuid
)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from teachers where id = p_teacher_id) then
    raise exception 'teacher_not_found' using errcode = 'P0004';
  end if;

  insert into ledger (type, teacher_id, teacher_share, note, recorded_by)
  values ('payout', p_teacher_id, -abs(p_amount), coalesce(p_note, ''), p_recorded_by);

  update teachers set total_paid_out = total_paid_out + abs(p_amount) where id = p_teacher_id;

  return jsonb_build_object('status', 'ok');
end;
$$;

create or replace function record_agent_payout(
  p_agent_id uuid, p_amount numeric, p_note text, p_recorded_by uuid
)
returns jsonb
language plpgsql
security definer
as $$
begin
  if not exists (select 1 from agents where id = p_agent_id) then
    raise exception 'agent_not_found' using errcode = 'P0005';
  end if;

  insert into ledger (type, agent_id, agent_share, note, recorded_by)
  values ('agent_payout', p_agent_id, -abs(p_amount), coalesce(p_note, ''), p_recorded_by);

  update agents set total_paid_out = total_paid_out + abs(p_amount) where id = p_agent_id;

  return jsonb_build_object('status', 'ok');
end;
$$;

-- ----------------------------------------------------------------------------
-- رصيد المدرس/الوكيل الحقيقي، محسوب من مجموع سطور الـ ledger مباشرة
-- (وليس من الحقل المخزّن total_earned فقط، لضمان دقة الرصيد دائماً)
-- ----------------------------------------------------------------------------
create or replace function get_teacher_earnings(p_teacher_id uuid)
returns jsonb
language sql
security definer
stable
as $$
  select jsonb_build_object(
    'total_earned', coalesce(sum(case when type = 'sale' then teacher_share else 0 end), 0),
    'total_paid_out', coalesce(sum(case when type = 'payout' then -teacher_share else 0 end), 0),
    'sales_count', coalesce(sum(case when type = 'sale' then 1 else 0 end), 0)
  )
  from ledger
  where teacher_id = p_teacher_id and type in ('sale', 'payout');
$$;

create or replace function get_agent_earnings(p_agent_id uuid)
returns jsonb
language sql
security definer
stable
as $$
  select jsonb_build_object(
    'total_earned', coalesce(sum(case when type = 'sale' then agent_share else 0 end), 0),
    'total_paid_out', coalesce(sum(case when type = 'agent_payout' then -agent_share else 0 end), 0),
    'sales_count', coalesce(sum(case when type = 'sale' then 1 else 0 end), 0)
  )
  from ledger
  where agent_id = p_agent_id and type in ('sale', 'agent_payout');
$$;
