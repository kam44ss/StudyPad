# منصة الدروس — نسخة Supabase (مفتوحة المصدر، مجانية)

هذه نسخة كاملة من نفس منصة الدروس، لكن مبنية على [Supabase](https://supabase.com) بدل Firebase:
- **مفتوحة المصدر بالكامل** (يمكنك حتى استضافتها بنفسك لاحقاً بنفس الكود لو حبيت)
- **مجانية** على الخطة المجانية من Supabase (لا حاجة لبطاقة ائتمان للبدء)
- مبنية على **PostgreSQL حقيقي** بدل Firestore — قاعدة بيانات علائقية بمعاملات ACID فعلية، وهذا أنسب لسجل الأرباح تحديداً (قيود Unique حقيقية بقاعدة البيانات، ودالة `ledger` ممنوعة من التعديل أو الحذف حتى بصلاحيات كاملة — راجع `0001_init.sql`)

## لماذا Supabase وليس تشغيل محلي بالكامل؟
"مجاني بالكامل ومحلي للأبد" غير ممكن عملياً لتطبيق يستخدمه طلاب حقيقيون — أي نظام لازم يشتغل على سيرفر يوصله الناس 24 ساعة. الخطة المجانية من Supabase تعطيك هذا **بدون أي تكلفة وبدون أي سيرفر تديره بنفسك**: مشروع واحد مجاني (قاعدة بيانات 500MB، مصادقة غير محدودة تقريباً بحدود معقولة، Edge Functions مجانية بحدود سخية). لو احتجت لاحقاً استقلالية كاملة، الكود نفسه مفتوح المصدر ويمكن نشره على سيرفرك الخاص (self-hosted Supabase عبر Docker) بدون إعادة كتابة أي شيء.

## النشر التلقائي من GitHub (اللي طلبته تحديداً)

المشروع فيه `.github/workflows/deploy.yml` — بمجرد ما ترفع هذا المجلد لمستودع GitHub خاص فيك وتعدّل عليه، أي push لفرع `main` يغيّر شي بمجلد `supabase/` ينشر تلقائياً لحساب Supabase الفعلي (قاعدة البيانات + كل الـ Edge Functions) بدون أي خطوة يدوية منك بعد كذا.

### إعداد لمرة واحدة فقط
1. ارفع هذا المجلد لمستودع GitHub جديد (خاص، عشان فيه مفاتيح حساسة لاحقاً بـ secrets)
2. من إعدادات المستودع → Settings → Secrets and variables → Actions، أضف:
   - `SUPABASE_ACCESS_TOKEN` — من [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens)
   - `SUPABASE_PROJECT_REF` — من رابط مشروعك بلوحة Supabase (الجزء بعد `/project/`)
   - `SUPABASE_DB_PASSWORD` — كلمة مرور قاعدة البيانات (حددتها وقت إنشاء المشروع)
3. اضبط أسرار زين كاش (`ZAINCASH_*`, `SITE_URL`) مرة واحدة يدوياً عبر `supabase secrets set` (خطوة 5 فوق) — هذي ثابتة وما تحتاج تتكرر مع كل push

بعد هذا، أي تعديل تسويه على أي فنكشن أو جدول وترفعه لـ GitHub، ينزل تلقائياً على حسابك الفعلي.

## سجل مراجعة دقيقة (Changelog)
بعد مراجعة شاملة للكود ككل، تم إصلاح هذه النقاط تحديداً:

- **`0006_fix_purchased_lesson_visibility.sql`** — كان الدرس يختفي من قائمة "دروسي" عند الطالب لو المدرس رجع الدرس لمسودة/إخفاء بعد ما الطالب اشتراه (RLS كانت تسمح فقط بالدروس المنشورة أو دروس المدرس نفسه). الحين أي درس اشتراه الطالب فعلياً يبقى ظاهر له بغض النظر عن حالة النشر.
- **`record_refund`** — كانت تفشل بالكامل لو حاولت استرجاع/إلغاء وصول درس تم الحصول عليه بكود ترويجي مجاني (ما فيه سطر بيع مالي لتعكسه). الحين تُلغي الوصول بأي الحالتين، وتعكس المحاسبة فقط لو فيه مبلغ فعلي.
- **دروس الاشتراك** — لم تكن مفعّلة إطلاقاً رغم إنها جزء من القرار الأساسي (سعر لكل درس: دائم أو اشتراك)؛ الحين أي درس `subscription` يعطي وصول 30 يوم فقط ثم ينتهي، ويُتحقق من هذا بكل نقطة وصول للمحتوى.
- **تسريب إجابة الاختبار** — الفنكشن كانت ترجع `correct_index` مع الأسئلة رغم إنه ما يظهر بالواجهة، يعني أي فحص لطلب الشبكة كان يكشف الإجابة الصحيحة. فُصلت لفنكشن `check-quiz-answer` منفصلة لا ترجع غير النتيجة.

## معروف وغير مُنفَّذ بعد (بقرار، وليس سهو)
- **الدفع عبر Google Play Billing** لم يُنقل لنسخة Supabase (كان موجوداً بالنسخة الأولى المبنية على Firebase) لأن القرار النهائي كان التركيز على زين كاش + الأكواد لتفادي عمولة المتجر بالكامل. لو احتجته لاحقاً كخيار إضافي، يحتاج بناء من جديد بنفس منطق التحقق من إيصال الشراء.

## خطوات الإعداد

### 1. أنشئ مشروع Supabase مجاني
اذهب إلى [supabase.com](https://supabase.com) → New Project (مجاني، بدون بطاقة).

### 2. شغّل ملفات الهجرة (migrations)
من لوحة تحكم Supabase → SQL Editor، شغّل الملفات **بالترتيب**:
1. `supabase/migrations/0001_init.sql` — الجداول والقيود
2. `supabase/migrations/0002_rls_policies.sql` — قواعد الأمان
3. `supabase/migrations/0003_rpc_functions.sql` — دوال المحاسبة الذرية
4. `supabase/migrations/0004_storage.sql` — تخزين ملفات الفيديو/PDF (bucket خاص)
5. `supabase/migrations/0005_subscriptions_and_refunds.sql` — دعم دروس الاشتراك (وصول 30 يوم) والاسترجاع
6. `supabase/migrations/0006_fix_purchased_lesson_visibility.sql` — إصلاح ظهور الدرس المشترى بقائمة الطالب
7. `supabase/migrations/0007_reviews.sql` — تقييمات ومراجعات الطلاب
8. `supabase/migrations/0008_bundles.sql` — حزم/كورسات (بيع عدة دروس بكود واحد)
9. `supabase/migrations/0009_bundle_rpc_updates.sql` — تحديث دوال المحاسبة لدعم الحزم
10. `supabase/migrations/0010_phone_number.sql` — رقم هاتف الطالب (لإشعارات WhatsApp)
11. `supabase/migrations/0011_progress_and_certificates.sql` — تتبع تقدم الطالب وشهادات الإتمام
12. `supabase/migrations/0012_discount_codes.sql` — كودات خصم (نسبة مئوية)
13. `supabase/migrations/0013_referrals.sql` — نظام الإحالة
14. `supabase/migrations/0014_auto_create_profile_critical_fix.sql` — **إصلاح حرج**: إنشاء profile تلقائياً عند التسجيل (بدونه النظام كله يفشل)
15. `supabase/migrations/0015_admin_dashboard.sql` — إحصائيات لوحة الأدمن
16. `supabase/migrations/0016_certificate_verification.sql` — التحقق العلني من الشهادات
17. `supabase/migrations/0017_captions.sql` — دعم ترجمة/نص مصاحب للفيديو
18. `supabase/migrations/0018_explanations_and_qa.sql` — شرح الإجابة الصحيحة + ميزة سؤال وجواب
19. `supabase/migrations/0019_practice_sets_and_leaderboard.sql` — لوحة صدارة + منصة تمارين موحّدة (يومي/مخصص/امتحان شامل)
20. `supabase/migrations/0020_client_error_logging.sql` — سجل أخطاء العملاء (بديل Sentry بسيط)
21. `supabase/migrations/0021_admin_mfa_capability.sql` — دالة MFA للأدمن (غير مفعّلة تلقائياً - راجع القسم أدناه)
22. `supabase/migrations/0022_streaks_review_flashcards_parentview_hints.sql` — سلسلة أيام، مراجعة، بطاقات، متابعة ولي أمر، تلميح محلي
23. `supabase/migrations/0023_reduce_hint_strength.sql` — تخفيف قوة تلميح 50/50 (يحذف نصف الخيارات الخاطئة فقط، مو كلها)

24. `supabase/migrations/0024_fix_review_refund_dashboard_and_lockdown.sql` — **إصلاحات من اختبار فعلي**: مراجعة الأخطاء، الاسترجاع (كان يفشل دائماً)، لوحة الأدمن (كانت ترجع admin_only)، وتقييد تنفيذ دوال RPC المالية على `service_role` فقط

> **ملاحظة:** الـ migrations الـ 24 طُبّقت بالترتيب على Postgres 16 حقيقي (مع محاكاة بسيطة لمخططي `auth` و`storage` الخاصين بـ Supabase)، وفُحصت كل دوال plpgsql بأداة `plpgsql_check`، وجُرّبت دوال RPC كلها بسيناريو كامل (شراء، أكواد، استرجاع، شهادات، تمارين). لم تُجرَّب على مشروع Supabase حقيقي (لا يوجد اتصال به من بيئة الاختبار) — جرّبها على مشروع تجريبي أولاً قبل الإنتاج.

### 3. أنشئ أول حساب أدمن (أنت)
سجّل دخول بالتطبيق مرة عادية (بريدك الإلكتروني)، ثم من SQL Editor:
```sql
update profiles set role = 'admin' where email = 'بريدك@example.com';
```
(هذا الأمر الوحيد المسموح يتجاوز حماية الـ role لأنه يُنفَّذ مباشرة بدون سياق طلب مستخدم عادي.)

### 4. انشر Edge Functions
ثبّت [Supabase CLI](https://supabase.com/docs/guides/cli) ثم:
```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
# ينشر كل الدوال (24 دالة) دفعة واحدة بدل سردها يدوياً - القائمة اليدوية السابقة كانت
# ناقصة (create-parent-view-token, get-answer-hint, get-parent-view) وفيها تكرار.
# supabase/config.toml يحدد نقطة الدخول index.js لكل دالة، ويعطّل verify_jwt لـ zaincash-redirect.
for d in supabase/functions/*/; do
  fn=$(basename "$d"); [ "$fn" = "_shared" ] && continue
  supabase functions deploy "$fn"
done
```

> **مهم:** `zaincash-redirect` يجب أن تبقى بدون التحقق من JWT (`verify_jwt = false` في `config.toml`)
> لأن متصفح الطالب العائد من زين كاش لا يحمل جلسة Supabase. التحقق الحقيقي يتم داخل الدالة
> بتوقيع JWT الخاص بزين كاش. ولا تضبط `SITE_URL` على عنوان الدوال: `SITE_URL` هو عنوان
> الموقع الثابت فقط (صفحة `payment-result.html`)، أما عنوان رجوع زين كاش فيُبنى تلقائياً من `SUPABASE_URL`.

## مقارنة مع أبواب/مرماز - شنو بنيناه وشنو تأجّل

بعد بحث فعلي بمنصتي أبواب ومرماز، بنينا هذي الفجوات:
- ✅ شرح الإجابة الصحيحة بعد كل سؤال
- ✅ سؤال وجواب (الطالب يسأل، المدرس أو طالب ثاني يجاوب)
- ✅ لوحة صدارة (بلقب اختياري يحدده الطالب، بدون كشف اسمه/إيميله الحقيقي)
- ✅ منصة تمارين موحّدة تخدم 3 حالات: اختبار يومي، اختبار مخصص بمادة معيّنة، وامتحان شامل تجريبي لحزمة كاملة

**تأجّلت بقرار صريح:**
- **البث المباشر (Live)** — يحتاج خدمة خارجية متخصصة (Agora/LiveKit) بتكلفة شهرية فعلية، مختلف تماماً عن بنيتنا المجانية الحالية. قرار تكلفة يحتاجه صاحب المشروع، مو شي يُبنى بصمت.
- **مرشد شخصي بخطة أسبوعية وتقارير آلية عبر WhatsApp** — يحتاج جدولة تلقائية (pg_cron) وقالب WhatsApp معتمد من Meta (يأخذ أيام للموافقة) - ما قدرت أختبر هذا التدفق كامل من طرف لطرف، فتركته لمرحلة لاحقة بدل ما أدّعي إنه جاهز 100% وهو غير مُختبر فعلياً.

## ✅ حالة المشروع: منشور فعلياً ويشتغل

هذا المشروع **ليس مجرد كود جاهز للنشر** — تم إنشاؤه ونشره فعلياً على مشروع Supabase حقيقي (`math-lessons-platform`) عبر اتصال MCP مباشر، وتحققت من عمله حياً:
- كل الـ 17 جدول موجودة وRLS مفعّل عليها كلها
- كل الـ 17 Edge Function منشورة ونشطة (`ACTIVE`)
- اختبرت ضمانة "سجل الأرباح لا يُعدَّل" فعلياً (حاولت تعديل وحذف صف، وانرُفض الاثنين بالضبط كما هو مصمَّم)
- ملفات `index.html`, `admin.html`, `teacher.html`, وتطبيق الأندرويد محدّثة تلقائياً بالقيم الحقيقية للمشروع (مو `YOUR_PROJECT` وهمية)

**الشيء الوحيد المتبقي فعلياً:** بيانات زين كاش الحقيقية (بعد ما تسجّل حساب تاجر)، ونشر مجلد `public/` على استضافة (Vercel/Netlify)، وتجربة تسجيل دخول حقيقي أول مرة.

### 5. اضبط أسرار زين كاش (secrets)
```bash
supabase secrets set ZAINCASH_MSISDN=9647XXXXXXXX
supabase secrets set ZAINCASH_MERCHANT_ID=your_merchant_id
supabase secrets set ZAINCASH_SECRET=your_secret
supabase secrets set ZAINCASH_PRODUCTION=false
supabase secrets set SITE_URL=https://your-domain.com
supabase secrets set WHATSAPP_TOKEN=your_permanent_access_token
supabase secrets set WHATSAPP_PHONE_NUMBER_ID=your_phone_number_id
```

## إعداد إشعارات WhatsApp (نقطة مهمة يجب معرفتها)

استخدمت **Meta WhatsApp Cloud API الرسمية** فقط (وليس أي أداة أتمتة غير رسمية - تلك تخالف شروط WhatsApp وتعرّض رقمك للحظر).

**خطوات الإعداد:**
1. أنشئ حساب على [Meta Business Manager](https://business.facebook.com) وفعّل WhatsApp Business Platform
2. من System Users بالـ Business Manager، أنشئ مستخدم نظام وولّد Access Token دائم (permanent) بصلاحيات `whatsapp_business_messaging`
3. خذ `WHATSAPP_PHONE_NUMBER_ID` من إعدادات رقم الواتساب التجاري بلوحة Meta

**نقطة حرجة (تحققت منها بالبحث قبل ما أكتب الكود):** رسائل WhatsApp الحرة (نص عادي) تشتغل فقط خلال 24 ساعة من آخر رسالة أرسلها الطالب لرقمك التجاري. أي إشعار تبدأه أنت (تفعيل كود، درس جديد) يحتاج **قالب رسالة معتمد مسبقاً من Meta** (Message Template) — أنشئه من WhatsApp Manager → Message Templates قبل استخدام `send-whatsapp-message`، وإلا الإرسال يفشل بالكامل خارج نافذة الـ 24 ساعة.

## تحسينات وفجوات إضافية (بطلب صريح لمراجعة الموجود، وتفكير بسيناريوهات فشل)
- ✅ **تعديل/حذف الأسئلة والبطاقات التعليمية** من `teacher.html` مباشرة - ما تحتاج تروح للوحة Supabase لتصحيح غلطة
- ✅ **قائمة اختيار للحزمة بالامتحان الشامل** بالأندرويد - بدل ما يكتب الطالب uuid خام، يشوف أسماء حزمه فعلياً
- ✅ **تحميل التقييمات بطلب واحد** بدل طلب منفصل لكل درس - أسرع بكثير مع نمو عدد الدروس
- ✅ **لوحة الأدمن صارت بتبويبات** (الرئيسية، المدرسون والوكلاء، الأكواد والخصومات، المالية والدعم) بدل تمرير طويل واحد
- ✅ **تخفيف قوة تلميح 50/50** - يحذف نصف الخيارات الخاطئة فقط الآن (مو كلها إلا واحدة)، فيبقى تحدي حقيقي
- ✅ **حل الدفعات العالقة** — `admin-resolve-stuck-order` + قسم بلوحة الأدمن لمراجعة أي طلب زين كاش بقي "pending" وحسمه يدوياً
- ✅ **سجل أخطاء بسيط** (`client_errors` + `log-client-error`) — بديل عن Sentry بدون حساب خارجي، مفعّل بكل صفحات الموقع والأندرويد
- ✅ **بحث/فلترة الدروس** بالموقع الرئيسي
- ✅ **سياسة خصوصية وشروط استخدام** (`privacy.html`, `terms.html`) — **مسودة عامة فقط، راجعها مع محامٍ قبل النشر الفعلي**
- ⚠️ **حماية MFA لحساب الأدمن** — الدالة `is_admin_with_mfa()` جاهزة بس **غير مفعّلة بأي مكان بعد عمداً**، لتفادي قفلك برّا حسابك قبل ما تتأكد الكود يشتغل. فعّلها لحسابك من قسم "حماية إضافية" بلوحة الأدمن، وتأكد تشتغل، بعدين اطلب مني أشدّد الفحص بالأماكن الحساسة.

## الميزات الجديدة (حزم، تقييمات)
- **الحزم/الكورسات:** من `teacher.html` تقدر تجمع عدة دروس بسعر واحد. الأكواد وزين كاش يدعمون البيع بحزمة كاملة بنفس الآلية (`generate-redemption-codes`/`create-zaincash-checkout` يقبلون `bundleId` بدل `lessonId`).
- **التقييمات:** الطالب يقيّم من داخل تطبيق الأندرويد بعد ما يشتري الدرس، والموقع يعرض متوسط التقييم لكل درس قبل الشراء.

### 6. حدّث إعدادات المشروع بالواجهة
افتح `public/index.html` و`public/admin.html` و`public/teacher.html` وبدّل:
```js
const SUPABASE_URL = "https://YOUR_PROJECT.supabase.co";
const SUPABASE_ANON_KEY = "YOUR_ANON_KEY";
```
(تجدها بلوحة Supabase → Project Settings → API)

**الصفحات الثلاث:**
- `public/index.html` — للطلاب: تسجيل دخول، شراء بزين كاش، تفعيل كود
- `public/teacher.html` — للمدرسين: إنشاء درس، رفع فيديو/PDF، إضافة أسئلة اختبار، نشر الدرس
- `public/admin.html` — لك أنت: تحويل مستخدم إلى مدرس، إنشاء وكلاء، توليد أكواد، متابعة الأرباح وتسجيل الدفعات

### 7. استضف مجلد `public/`
Supabase لا يستضيف مواقع ثابتة، فتحتاج استضافة منفصلة مجانية: [Vercel](https://vercel.com) أو [Netlify](https://netlify.com) أو GitHub Pages — كلها مجانية لموقع بسيط زي هذا. اسحب مجلد `public/` وخلاص.

## الفرق عن نسخة Firebase
- **تسجيل الدخول:** استبدلت "دخول بحساب Google" بـ Magic Link عبر البريد الإلكتروني (أبسط إعداداً، يشتغل مباشرة بدون ضبط OAuth) — تقدر تضيف Google أو أي مزوّد لاحقاً من إعدادات Auth بلوحة Supabase.
- **الحماية:** بدل Firestore Rules صار عندك Row Level Security + قيود قاعدة بيانات حقيقية (UNIQUE constraints, CHECK constraints) — أقوى تقنياً لأنها مفروضة من محرك قاعدة البيانات نفسه.
- **الذرية (Atomicity):** بدل `db.runTransaction()` بجافاسكربت، صارت دوال `plpgsql` حقيقية تشتغل كمعاملة واحدة تلقائياً — نفس النتيجة لكن بضمانات أقوى.
