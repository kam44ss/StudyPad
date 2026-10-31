-- ============================================================================
-- تخفيف قوة تلميح "احذف الخاطئ" - كان يحذف كل الخيارات الخاطئة إلا واحدة
-- (يتحول أي سؤال لـ50/50 دايماً بغض النظر عن عدد الخيارات الأصلي). الآن يحذف
-- نصف الخيارات الخاطئة فقط (لأسفل)، فالسؤال يبقى فيه تحدي حقيقي متبقي.
-- ============================================================================

create or replace function get_answer_hint(p_question_id uuid, p_student_id uuid)
returns jsonb
language plpgsql
security definer
as $$
declare
  v_question quiz_questions%rowtype;
  v_wrong_indexes int[];
  v_eliminate_count int;
begin
  select * into v_question from quiz_questions where id = p_question_id;
  if not found then
    raise exception 'question_not_found' using errcode = 'P0070';
  end if;

  if not exists (
    select 1 from purchases
    where student_id = p_student_id and lesson_id = v_question.lesson_id and status = 'verified'
  ) then
    raise exception 'not_purchased' using errcode = 'P0030';
  end if;

  select array_agg(idx - 1) into v_wrong_indexes
  from jsonb_array_elements(v_question.choices) with ordinality as t(val, idx)
  where idx - 1 <> v_question.correct_index;

  if v_wrong_indexes is null or array_length(v_wrong_indexes, 1) < 2 then
    return jsonb_build_object('eliminated_indexes', '[]'::jsonb, 'hint', v_question.hint);
  end if;

  -- نحذف نصف الخيارات الخاطئة فقط (لأسفل) - يبقى تحدي حقيقي، مو حل شبه جاهز دايماً
  v_eliminate_count := floor(array_length(v_wrong_indexes, 1) / 2.0)::int;

  v_wrong_indexes := (
    select array_agg(x) from (
      select unnest(v_wrong_indexes) as x order by random() limit greatest(v_eliminate_count, 0)
    ) t
  );

  return jsonb_build_object(
    'eliminated_indexes', to_jsonb(coalesce(v_wrong_indexes, array[]::int[])),
    'hint', v_question.hint
  );
end;
$$;
