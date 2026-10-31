-- ============================================================================
-- إصلاح حرج: ما كان فيه أي آلية تنشئ صف profiles تلقائياً عند تسجيل مستخدم
-- جديد! بدون هذا، كل شيء بالنظام يتوقف على وجود صف profiles (is_admin,
-- getUserRole, كل RLS تقريباً) - كان سينهار النظام بالكامل عند أول تسجيل حقيقي.
-- ============================================================================

create or replace function handle_new_user()
returns trigger
security definer
set search_path = public
as $$
declare
  v_referrer_id uuid;
  v_ref_code text;
begin
  -- الكود المُحيل (لو وُجد) يصل عبر بيانات إضافية وقت التسجيل (raw_user_meta_data)
  v_ref_code := new.raw_user_meta_data ->> 'referral_code';

  if v_ref_code is not null then
    select id into v_referrer_id from public.profiles
      where referral_code = upper(v_ref_code)
      limit 1;
  end if;

  insert into public.profiles (id, email, referred_by)
  values (new.id, new.email, v_referrer_id);

  return new;
end;
$$ language plpgsql;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function handle_new_user();
