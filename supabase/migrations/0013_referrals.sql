-- ============================================================================
-- نظام الإحالة: الطالب يجيب صديق، كلاهما ياخذ كود خصم 20% بعد أول عملية شراء للصديق
-- ============================================================================

alter table profiles add column referral_code text unique;
alter table profiles add column referred_by uuid references profiles(id);

-- توليد referral_code تلقائياً لكل مستخدم جديد
create or replace function generate_referral_code()
returns trigger as $$
begin
  if new.referral_code is null then
    new.referral_code := upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));
  end if;
  return new;
end;
$$ language plpgsql;

create trigger profiles_generate_referral_code
before insert on profiles
for each row execute function generate_referral_code();

-- نعبّي referral_code لأي صفوف موجودة مسبقاً (لو فيه مستخدمين سجّلوا قبل هذا التحديث)
update profiles set referral_code = upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6))
where referral_code is null;

create table referral_rewards (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references profiles(id),
  referred_id uuid not null references profiles(id) unique,
  referrer_discount_code text references discount_codes(code),
  referred_discount_code text references discount_codes(code),
  created_at timestamptz not null default now()
);

alter table referral_rewards enable row level security;

create policy referral_rewards_select on referral_rewards
  for select using (referrer_id = auth.uid() or referred_id = auth.uid() or is_admin());

-- ----------------------------------------------------------------------------
-- يُستدعى بعد أي عملية شراء ناجحة - يمنح مكافأة إحالة مرة واحدة فقط عند أول
-- عملية شراء فعلية للطالب المُحال
-- ----------------------------------------------------------------------------
create or replace function maybe_grant_referral_reward(p_student_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_referrer_id uuid;
  v_purchase_count integer;
  v_referrer_code text;
  v_referred_code text;
begin
  select referred_by into v_referrer_id from profiles where id = p_student_id;
  if v_referrer_id is null then
    return;
  end if;

  if exists (select 1 from referral_rewards where referred_id = p_student_id) then
    return;
  end if;

  select count(*) into v_purchase_count from purchases
    where student_id = p_student_id and status = 'verified';

  if v_purchase_count <> 1 then
    return; -- نمنح المكافأة فقط عند أول عملية شراء بالضبط
  end if;

  v_referrer_code := 'REF' || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));
  v_referred_code := 'REF' || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));

  insert into discount_codes (code, percent_off, max_uses, created_by, status)
  values (v_referrer_code, 20, 1, p_student_id, 'active');
  insert into discount_codes (code, percent_off, max_uses, created_by, status)
  values (v_referred_code, 20, 1, p_student_id, 'active');

  insert into referral_rewards (referrer_id, referred_id, referrer_discount_code, referred_discount_code)
  values (v_referrer_id, p_student_id, v_referrer_code, v_referred_code);
end;
$$;

-- ----------------------------------------------------------------------------
-- تحديث redeem_code و record_zaincash_result: تطبيق الخصم + استدعاء مكافأة الإحالة
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
  v_lesson_id uuid;
  v_lesson_ids uuid[];
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

  if v_order.lesson_id is not null then
    select * into v_lesson from lessons where id = v_order.lesson_id;
    v_expires_at := case when v_lesson.price_type = 'subscription'
                         then now() + interval '30 days'
                         else null end;

    insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
    values (v_order.student_id, v_order.lesson_id, v_order.teacher_id, p_order_id::text, 'zaincash', 'verified', v_expires_at);

    v_lesson_ids := array[v_order.lesson_id];
  else
    select array_agg(lesson_id) into v_lesson_ids
      from bundle_lessons where bundle_id = v_order.bundle_id;

    if v_lesson_ids is null or array_length(v_lesson_ids, 1) = 0 then
      raise exception 'bundle_empty' using errcode = 'P0006';
    end if;

    foreach v_lesson_id in array v_lesson_ids loop
      select * into v_lesson from lessons where id = v_lesson_id;
      v_expires_at := case when v_lesson.price_type = 'subscription'
                           then now() + interval '30 days'
                           else null end;

      insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
      values (v_order.student_id, v_lesson_id, v_order.teacher_id, p_order_id::text, 'zaincash', 'verified', v_expires_at);
    end loop;
  end if;

  -- المبلغ الفعلي المدفوع (بعد الخصم لو وُجد) هو v_order.amount أصلاً
  -- (الخصم يُحسب وقت إنشاء الطلب بـ create-zaincash-checkout)
  v_gross := v_order.amount;
  v_platform_share := round(v_gross * (v_teacher.revenue_share_percent / 100), 2);
  v_teacher_share := round(v_gross - v_platform_share, 2);

  insert into ledger (
    type, lesson_id, bundle_id, student_id, teacher_id,
    gross_amount, platform_share, teacher_share,
    store_commission, store_transaction_id, store_name
  ) values (
    'sale', v_order.lesson_id, v_order.bundle_id, v_order.student_id, v_order.teacher_id,
    v_gross, v_platform_share, v_teacher_share,
    0, p_order_id::text, 'zaincash'
  );

  update teachers set total_earned = total_earned + v_teacher_share where id = v_order.teacher_id;
  update zaincash_orders set status = 'completed' where id = p_order_id;

  if v_order.discount_code is not null then
    update discount_codes set used_count = used_count + 1 where code = v_order.discount_code;
  end if;

  perform maybe_grant_referral_reward(v_order.student_id);

  return jsonb_build_object(
    'status', 'completed',
    'lesson_id', v_order.lesson_id,
    'bundle_id', v_order.bundle_id,
    'lesson_ids', to_jsonb(v_lesson_ids)
  );
end;
$$;

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
  v_lesson_id uuid;
  v_lesson_ids uuid[];
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

  update redemption_codes
    set status = 'used', used_by = p_student_id, used_at = now()
    where code = p_code;

  if v_row.agent_id is not null then
    select * into v_agent from agents where id = v_row.agent_id;
  end if;

  if v_row.lesson_id is not null then
    select * into v_lesson from lessons where id = v_row.lesson_id;
    v_expires_at := case when v_lesson.price_type = 'subscription'
                         then now() + interval '30 days'
                         else null end;

    insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
    values (p_student_id, v_row.lesson_id, v_row.teacher_id, p_code, 'redemption_code', 'verified', v_expires_at);

    v_lesson_ids := array[v_row.lesson_id];
  else
    select array_agg(lesson_id) into v_lesson_ids
      from bundle_lessons where bundle_id = v_row.bundle_id;

    if v_lesson_ids is null or array_length(v_lesson_ids, 1) = 0 then
      raise exception 'bundle_empty' using errcode = 'P0006';
    end if;

    foreach v_lesson_id in array v_lesson_ids loop
      select * into v_lesson from lessons where id = v_lesson_id;
      v_expires_at := case when v_lesson.price_type = 'subscription'
                           then now() + interval '30 days'
                           else null end;

      insert into purchases (student_id, lesson_id, teacher_id, store_transaction_id, method, status, expires_at)
      values (p_student_id, v_lesson_id, v_row.teacher_id, p_code, 'redemption_code', 'verified', v_expires_at);
    end loop;
  end if;

  if v_row.is_paid and v_row.value > 0 then
    v_gross := v_row.value;

    if v_row.agent_id is not null and v_agent.id is not null then
      v_agent_share := round(v_gross * (v_agent.commission_percent / 100), 2);
    end if;

    v_net_after_agent := v_gross - v_agent_share;
    v_platform_share := round(v_net_after_agent * (v_teacher.revenue_share_percent / 100), 2);
    v_teacher_share := round(v_net_after_agent - v_platform_share, 2);

    insert into ledger (
      type, lesson_id, bundle_id, student_id, teacher_id, agent_id,
      gross_amount, agent_share, platform_share, teacher_share,
      store_commission, store_transaction_id, store_name
    ) values (
      'sale', v_row.lesson_id, v_row.bundle_id, p_student_id, v_row.teacher_id, v_row.agent_id,
      v_gross, v_agent_share, v_platform_share, v_teacher_share,
      0, p_code, 'redemption_code'
    );

    update teachers set total_earned = total_earned + v_teacher_share where id = v_row.teacher_id;

    if v_row.agent_id is not null and v_agent_share > 0 then
      update agents set total_earned = total_earned + v_agent_share where id = v_row.agent_id;
    end if;
  end if;

  perform maybe_grant_referral_reward(p_student_id);

  return jsonb_build_object(
    'status', 'redeemed',
    'lesson_id', v_row.lesson_id,
    'bundle_id', v_row.bundle_id,
    'lesson_ids', to_jsonb(v_lesson_ids)
  );
end;
$$;
