-- ============================================================================
-- دعم دروس الاشتراك (وليس فقط الشراء الدائم) + دعم استرجاع المبالغ
-- ============================================================================

-- تاريخ انتهاء الوصول - null يعني وصول دائم (شراء one_time)، وإلا وصول مؤقت
-- ينتهي بعد فترة (subscription)
alter table purchases add column if not exists expires_at timestamptz;

-- ----------------------------------------------------------------------------
-- تحديث redeem_code: لو الدرس subscription، الوصول يكون 30 يوم فقط
-- ----------------------------------------------------------------------------
create or replace function redeem_code(p_code text, p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row redemption_codes%rowtype;
  v_teacher teachers%rowtype;
  v_lesson lessons%rowtype;
  v_agent agents%rowtype;
  v_gross numeric(12,2);
  v_agent_share numeric(12,2) := 0;
  v_net_after_agent numeric(12,2);
  v_platform_share numeric(12,2) := 0;
  v_teacher_share numeric(12,2) := 0;
  v_expires_at timestamptz;
begin
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

  select * into v_lesson from lessons where id = v_row.lesson_id;

  v_expires_at := case when v_lesson.price_type = 'subscription'
                       then now() + interval '30 days'
                       else null end;

  if v_row.is_paid and v_row.agent_id is not null then
    select * into v_agent from agents where id = v_row.agent_id;
  end if;

  update redemption_codes
    set status = 'used', used_by = p_student_id, used_at = now()
    where code = p_code;

  insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
  values (p_student_id, v_row.lesson_id, v_row.teacher_id, p_code, 'redemption_code', 'verified', v_expires_at);

  if v_row.is_paid and v_row.value > 0 then
    v_gross := v_row.value;

    if v_row.agent_id is not null and v_agent.id is not null then
      v_agent_share := round(v_gross * (v_agent.commission_percent / 100), 2);
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

  return jsonb_build_object('status', 'redeemed', 'lesson_id', v_row.lesson_id, 'expires_at', v_expires_at);
end;
$$;

-- ----------------------------------------------------------------------------
-- تحديث record_zaincash_result: نفس مبدأ صلاحية الاشتراك
-- ----------------------------------------------------------------------------
create or replace function record_zaincash_result(p_order_id uuid, p_success boolean)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_order zaincash_orders%rowtype;
  v_teacher teachers%rowtype;
  v_lesson lessons%rowtype;
  v_gross numeric(12,2);
  v_platform_share numeric(12,2);
  v_teacher_share numeric(12,2);
  v_expires_at timestamptz;
begin
  select * into v_order from zaincash_orders where id = p_order_id for update;

  if not found then
    raise exception 'order_not_found' using errcode = 'P0010';
  end if;

  if v_order.status = 'completed' then
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

  select * into v_lesson from lessons where id = v_order.lesson_id;
  v_expires_at := case when v_lesson.price_type = 'subscription'
                       then now() + interval '30 days'
                       else null end;

  v_gross := v_order.amount;
  v_platform_share := round(v_gross * (v_teacher.revenue_share_percent / 100), 2);
  v_teacher_share := round(v_gross - v_platform_share, 2);

  insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
  values (v_order.student_id, v_order.lesson_id, v_order.teacher_id, p_order_id::text, 'zaincash', 'verified', v_expires_at);

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

  return jsonb_build_object('status', 'completed', 'lesson_id', v_order.lesson_id, 'expires_at', v_expires_at);
end;
$$;

-- ----------------------------------------------------------------------------
-- استرجاع مبلغ عملية بيع - يعكس الحصص بسطر ledger جديد (سالب) ويلغي الوصول
-- ----------------------------------------------------------------------------
create or replace function record_refund(p_purchase_id uuid, p_recorded_by uuid, p_note text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_purchase purchases%rowtype;
  v_sale ledger%rowtype;
  v_sale_found boolean := false;
begin
  select * into v_purchase from purchases where id = p_purchase_id for update;

  if not found then
    raise exception 'purchase_not_found' using errcode = 'P0020';
  end if;

  if v_purchase.status = 'refunded' then
    return jsonb_build_object('status', 'already_refunded');
  end if;

  -- نجد سطر البيع الأصلي بنفس معرّف العملية لنعرف كيف كانت الحصص موزّعة بالضبط.
  -- ملاحظة: قد لا يوجد سطر بيع إطلاقاً لو كانت هذي وصول مجاني (كود ترويجي غير
  -- مدفوع) - بهذه الحالة نكتفي بإلغاء الوصول بدون أي عكس مالي، لأنه ما فيه
  -- مبلغ للاسترجاع أصلاً.
  select * into v_sale from ledger
    where store_transaction_id = v_purchase.store_transaction_id and type = 'sale'
    limit 1;

  v_sale_found := found;

  if v_sale_found then
    insert into ledger (
      type, lesson_id, student_id, teacher_id, agent_id,
      gross_amount, agent_share, platform_share, teacher_share,
      store_commission, store_transaction_id, store_name, note, recorded_by
    ) values (
      'refund', v_sale.lesson_id, v_sale.student_id, v_sale.teacher_id, v_sale.agent_id,
      -v_sale.gross_amount, -v_sale.agent_share, -v_sale.platform_share, -v_sale.teacher_share,
      -v_sale.store_commission, v_purchase.store_transaction_id, v_sale.store_name,
      coalesce(p_note, ''), p_recorded_by
    );

    update teachers set total_earned = total_earned - v_sale.teacher_share where id = v_sale.teacher_id;

    if v_sale.agent_id is not null then
      update agents set total_earned = total_earned - v_sale.agent_share where id = v_sale.agent_id;
    end if;
  end if;

  -- إلغاء الوصول فوراً - get-lesson-content يتحقق من status='verified' فقط
  update purchases set status = 'refunded' where id = p_purchase_id;

  return jsonb_build_object(
    'status', 'refunded',
    'financial_reversal', v_sale_found
  );
end;
$$;
