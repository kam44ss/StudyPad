-- ============================================================================
-- كودات خصم (نسبة مئوية) - منفصلة عن أكواد الوصول الكامل، تُستخدم وقت الدفع بزين كاش
-- ============================================================================

create table discount_codes (
  code text primary key,
  percent_off numeric(5,2) not null check (percent_off > 0 and percent_off <= 100),
  max_uses integer, -- null = بلا حد
  used_count integer not null default 0,
  expires_at timestamptz,
  created_by uuid references profiles(id),
  status text not null default 'active' check (status in ('active', 'disabled')),
  created_at timestamptz not null default now()
);

alter table discount_codes enable row level security;

create policy discount_codes_select on discount_codes
  for select using (is_admin());
-- لا سياسات insert/update للعميل - فقط عبر service_role (create-discount-code Edge Function)

-- زين كاش: نضيف حقول تتبع الخصم المطبّق (إن وجد) على كل طلب
alter table zaincash_orders add column discount_code text references discount_codes(code);
alter table zaincash_orders add column original_amount numeric(12,2);

-- ----------------------------------------------------------------------------
-- يتحقق من صلاحية كود الخصم ويرجع النسبة - بدون زيادة عداد الاستخدام
-- (العداد يزيد فقط بعد نجاح الدفع فعلياً بـ record_zaincash_result)
-- ----------------------------------------------------------------------------
create or replace function validate_discount_code(p_code text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_row discount_codes%rowtype;
begin
  select * into v_row from discount_codes where code = upper(p_code);

  if not found then
    raise exception 'invalid_discount_code' using errcode = 'P0040';
  end if;
  if v_row.status <> 'active' then
    raise exception 'discount_code_disabled' using errcode = 'P0041';
  end if;
  if v_row.expires_at is not null and v_row.expires_at < now() then
    raise exception 'discount_code_expired' using errcode = 'P0042';
  end if;
  if v_row.max_uses is not null and v_row.used_count >= v_row.max_uses then
    raise exception 'discount_code_exhausted' using errcode = 'P0043';
  end if;

  return jsonb_build_object('valid', true, 'percent_off', v_row.percent_off);
end;
$$;
