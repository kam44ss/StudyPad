-- ============================================================================
-- التحقق العلني من شهادة بالكود - بدون كشف أي بيانات حساسة أخرى عن الطالب
-- ============================================================================

create or replace function verify_certificate(p_code text)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_cert record;
begin
  select c.certificate_code, c.issued_at, b.title as bundle_title, p.name as student_name
  into v_cert
  from certificates c
  join bundles b on b.id = c.bundle_id
  join profiles p on p.id = c.student_id
  where c.certificate_code = p_code;

  if not found then
    return jsonb_build_object('valid', false);
  end if;

  return jsonb_build_object(
    'valid', true,
    'bundle_title', v_cert.bundle_title,
    'student_name', coalesce(v_cert.student_name, 'طالب'),
    'issued_at', v_cert.issued_at
  );
end;
$$;
