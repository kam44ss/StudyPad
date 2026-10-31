# StudyPad

منصة دروس (رياضيات) — Lessons platform.

| المجلد | المحتوى |
|---|---|
| `supabase/` | قاعدة البيانات (23 migration) و22 Edge Function — تُنشر تلقائياً عبر `.github/workflows/deploy.yml` عند الـ push لفرع `main` |
| `public/` | واجهات الويب الثابتة (الطلاب، المدرسون، الأدمن، الشهادات، متابعة ولي الأمر، الخصوصية والشروط) |
| `android/` | تطبيق الأندرويد (Reader App) — كود يُدمج داخل مشروع Android Studio، راجع [`android/README.md`](android/README.md) |
| `docs/supabase-backend.md` | دليل الإعداد الكامل للـ backend والنشر |

> ملاحظة: مفتاح `anon` الموجود في ملفات `public/` وتطبيق الأندرويد مفتاح عام مصمَّم للتضمين في العميل (الحماية عبر RLS). لا تضع `service_role` أو أسرار زين كاش/WhatsApp في المستودع أبداً — تُضبط عبر `supabase secrets set` وأسرار GitHub Actions.
