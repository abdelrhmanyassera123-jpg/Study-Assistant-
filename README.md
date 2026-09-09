# مساعد المذاكرة — Study Assistant

موقع Flutter للمذاكرة: مؤقت بومودورو بيسجل وقتك، بطاقات مراجعة بتكرار متباعد،
مهام بمواعيد تسليم، ملاحظات، وإحصائيات — كله متزامن على Supabase وبيشتغل بالعربي
والإنجليزي بزر تبديل واحد.

A Flutter web study companion: a Pomodoro timer that logs your focus time,
spaced-repetition flashcards, tasks with due dates, notes, and stats — synced
through Supabase, in Arabic or English at the flip of one button.

---

## التشغيل — Getting started

### 1. اعمل مشروع Supabase / Create a Supabase project

1. روح [supabase.com](https://supabase.com) واضغط **Start your project**.
2. سجّل دخول بـ GitHub أو بإيميل.
3. من الداشبورد اضغط **New project**.
4. املا الفورم:
   - **Organization** — لو أول مرة، هيطلب منك تعمل واحدة (أي اسم، خطة Free).
   - **Project name** — مثلاً `study-assistant`.
   - **Database Password** — اضغط Generate a password واحفظها عندك. مش هتحتاجها
     للتطبيق، بس هي الطريقة الوحيدة للدخول على الداتابيز مباشرة، ومش هتقدر
     تشوفها تاني بعد كده.
   - **Region** — اختار الأقرب ليك جغرافيًا (من مصر: `Central EU (Frankfurt)`).
     الاختيار ده مش بيتغير بعدين.
5. اضغط **Create new project** واستنى دقيقة أو اتنين لحد ما التجهيز يخلص.

### 2. اعمل الجداول / Create the tables

1. من القايمة الجنب اختار **SQL Editor** ← **New query**.
2. افتح [`supabase/migrations/20260908000000_init_study_assistant.sql`](supabase/migrations/20260908000000_init_study_assistant.sql)،
   انسخ الملف **كله**، والزقه.
3. اضغط **Run** (أو `Ctrl+Enter`). المفروض تلاقي `Success. No rows returned`.
4. كرر نفس الخطوة مع
   [`supabase/migrations/20260908120000_style_samples.sql`](supabase/migrations/20260908120000_style_samples.sql).
5. اتأكد إن كل حاجة تمام: من **Table Editor** لازم تشوف 7 جداول —
   `subjects`, `tasks`, `notes`, `flashcards`, `study_sessions`, `card_reviews`,
   `style_samples` — وكل واحد فيهم مكتوب جنبه **RLS enabled**.

الملفات دي بتعمل الجداول وبتفعّل Row Level Security عليهم كلهم مع سياسات
select/insert/update/delete، يعني كل مستخدم يقدر يشوف ويعدّل داتاه هو بس. والملف
مكتوب بـ `if not exists` و `drop policy if exists`، فتقدر تشغّله تاني من غير ضرر.

#### أو بالـ CLI / Or with the CLI

المشروع متظبط لـ Supabase CLI، فبدل اللزق اليدوي:

```bash
npx supabase login
```

```bash
npx supabase link --project-ref <project-ref>
```

```bash
npx supabase db push
```

الـ `project-ref` هو الجزء اللي في الـ URL بتاع الداشبورد
(`supabase.com/dashboard/project/<project-ref>`).

الطريقة دي أحسن على المدى الطويل: أي تعديل جاي على الداتابيز بيتحط كملف جديد في
`supabase/migrations/` و `db push` بيطبّق الجديد بس.

### 3. (اختياري) اقفل تأكيد الإيميل وانت بتجرب

Supabase بيبعت إيميل تأكيد لكل حساب جديد افتراضيًا. عشان تجرب من غير ما تستنى:
**Authentication ← Sign In / Providers ← Email ← Confirm email ← Off ← Save**.

سيبها مقفولة وانت بتجرب بس، وارجّعها لو التطبيق هيستخدمه ناس تانية.

### 4. حط بيانات الاتصال / Add your credentials

من **Project Settings ← API Keys** (في نسخ أقدم: **Settings ← API**) انسخ حاجتين:

| الحاجة | شكلها |
|---|---|
| **Project URL** | `https://abcdefghijkl.supabase.co` |
| **anon public** أو **Publishable key** | `eyJhbGciOi...` أو `sb_publishable_...` |

⚠️ متاخدش الـ **service_role** أو الـ **secret key** — دول بيتخطّوا الـ RLS ولازم
يفضلوا على السيرفر بس، عمرهم ما يتحطوا في كود واجهة.

حطهم في [`lib/core/supabase_config.dart`](lib/core/supabase_config.dart):

```dart
static const String _fallbackUrl = 'https://abcdefghijkl.supabase.co';
static const String _fallbackAnonKey = 'eyJhbGciOi...';
```

> الـ anon key مصمم إنه يتحط في كود الواجهة — الحماية الحقيقية جاية من RLS في
> الداتابيز، مش من إخفاء المفتاح.
>
> The anon key is meant to ship in client code; RLS in the database is what
> protects the data, not hiding the key.

بديل من غير ما تعدّل الملف — لو مش عايز المفتاح في الكود:

```bash
flutter run -d chrome --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
```

### 5. شغّل / Run

```bash
flutter run -d chrome
```

أول مرة: اضغط **إنشاء حساب**، وبعد ما تدخل ابدأ من قسم **المواد** وضيف مادة أو
اتنين — المهام والكروت والملاحظات كلها بتتربط بيهم.

### 6. التلخيص بأسلوبك (اختياري) / Style-matched summarizing

قسم **التلخيص** بيشتغل بمزودين، وتبدّل بينهم من داخل التطبيق:

| المزود | مميزاته | حدوده |
|---|---|---|
| **موديل محلي (Ollama)** | مجاني تمامًا، وداتاك ما بتخرجش من جهازك | لازم جهازك يكون شغال، وأبطأ |
| **Gemini** | بيشتغل من أي جهاز، وأسرع | بياناتك بتروح لجوجل، ومحتاج مفتاح |

#### أ. الموديل المحلي (Ollama)

1. نزّل Ollama وشغّله، وبعدين نزّل موديل يفهم عربي كويس:

```bash
ollama pull qwen3.6:35b-a3b
```

2. من التطبيق: **التلخيص ← أيقونة الإعدادات** واختار الموديل. الاتصال بيتفحص
   تلقائي، ومحتاج Ollama يكون شغال.
3. **الأهم:** من **التلخيص ← أمثلة أسلوبك**، اكتب 3-5 من تلخيصاتك بنفسك. الموديل
   بيقلد شكلها ونبرتها بالظبط، فاختار أحسن اللي عندك مش أول اللي يقع تحت إيدك.
4. ارفع محاضرة `pptx` أو `docx` (أو الزق النص) واضغط **لخّص**.

#### ب. Gemini

المفتاح **لازم** يفضل على السيرفر. لو اتحط في كود الفلاتر هيبقى في ملفات
الجافاسكريبت وأي حد يفتح الموقع يقدر يستخرجه ويستهلك حصتك — فالنداء بيعدي من
Edge Function.

1. هات مفتاح مجاني من [Google AI Studio](https://aistudio.google.com/apikey).
2. حطه كـ secret (المفتاح ما بيتكتبش في أي ملف في المشروع):

```bash
npx supabase secrets set GEMINI_API_KEY=your-key-here
```

3. انشر الفنكشن:

```bash
npx supabase functions deploy summarize
```

4. من التطبيق: **التلخيص ← الإعدادات ← Gemini**، واختار موديل.

> الفنكشن بترفض أي نداء مش من مستخدم مسجّل دخول. التحقق الافتراضي بتاع Supabase
> بيقبل الـ anon key نفسه — وهو عام — فالفنكشن بتفحص إن الـ JWT بتاع مستخدم
> حقيقي (`role == authenticated`) مش الـ anon.

> **ليه أمثلة مش تدريب؟** نقل الأسلوب بالـ fine-tuning محتاج مئات الأمثلة
> وإعادة تدريب مع كل تغيير. الأمثلة في البرومبت بتوصل لنتيجة أحسن من 3-4 أمثلة،
> وبتتعدّل في ثانية.
>
> **إضافة مزود تالت:** الصفحة بتاخد `Summarizer` مجرّد، والاختيار بيتم في
> [`summarizer_provider.dart`](lib/features/summarize/summarizer_provider.dart).
> إضافة Claude مثلاً = ملف تنفيذ جديد + سطر في الـ switch. البرومبت نفسه مشترك
> في [`summarizer.dart`](lib/features/summarize/summarizer.dart) عشان الأسلوب
> ما يتغيرش لما تبدّل.

للنشر / to build for deployment:

```bash
flutter build web --release
```

الناتج بيطلع في `build/web` — ارفعه على أي استضافة ثابتة (Netlify, Vercel,
GitHub Pages, Firebase Hosting).

---

## المزايا — Features

| القسم | إيه اللي بيعمله |
|---|---|
| **الرئيسية** | تركيز النهاردة، أيام متتالية، الكروت المستحقة، مهام النهاردة — وزراير تودّيك على طول لأي حاجة منهم |
| **المؤقت** | بومودورو بمدد قابلة للتعديل، بيربط الجلسة بمادة، وبيسجّل كل بلوك تركيز تلقائي |
| **المهام** | مقسومة تلقائي لـ متأخرة / النهاردة / قريبة / بدون تاريخ، بأولويات وفلترة بالمادة |
| **المراجعة** | بطاقات بخوارزمية SM-2: تقيّم نفسك بأربع أزرار والتطبيق يحدد امتى تشوف الكارت تاني |
| **الملاحظات** | ملاحظات مربوطة بالمواد مع بحث في العنوان والمحتوى |
| **الإحصائيات** | رسم بياني لآخر 7 أيام، توزيع الوقت على المواد، متوسط يومي، streak |
| **التلخيص** | ترفع محاضرة pptx/docx، والموديل يلخصها **بأسلوبك انت** بناءً على أمثلة بتكتبها بنفسك |
| **المواد** | كل حاجة بتتربط بمادة بلون مميز |

### حاجات تفصيلية تستاهل الذكر

- **المؤقت بيفضل شغال** وانت بتتنقل بين الأقسام — عايش على مستوى التطبيق مش
  الصفحة.
- **الجلسات الناقصة بتتسجل**: لو وقفت المؤقت بعد 12 دقيقة تركيز، الـ 12 دقيقة
  بتتحسب. أقل من دقيقة بيتم تجاهلها.
- **"تاني" في المراجعة** بترجّع الكارت آخر طابور نفس الجلسة، مش بس بتأجله لبكرة.
- **الـ streak** بيبدأ العد من إمبارح لو لسه ما ذاكرتش النهاردة، فما بتخسرهوش
  بدري في اليوم.
- **ملف المحاضرة ما بيخرجش من جهازك**: ملفات pptx/docx أصلاً أرشيف ZIP جواه
  XML، والتطبيق بيفكها في المتصفح نفسه ويبعت النص المستخرج بس.
- **التلخيص بيرفض بدل ما يقص**: لو المحاضرة أطول من سياق الموديل، بتيجي رسالة
  واضحة بدل تلخيص ناقص وواثق.

---

## بنية المشروع — Project structure

```
lib/
├── main.dart                     نقطة البداية + MaterialApp
├── core/
│   ├── supabase_config.dart      الـ URL والمفتاح  ← عدّل هنا
│   ├── l10n.dart                 كل النصوص عربي/إنجليزي
│   ├── app_theme.dart            Material 3، فاتح/غامق، خط Cairo
│   ├── settings.dart             اللغة والمظهر ومدد المؤقت (محفوظة محليًا)
│   └── format.dart               تنسيق الوقت والتواريخ
├── models/models.dart            Subject, Task, Note, Flashcard (+SM-2), StudySession
├── data/
│   ├── repository.dart           كل قراءة/كتابة من Supabase
│   ├── providers.dart            providers للداتا والمصادقة
│   └── stats.dart                الإحصائيات المحسوبة
├── features/                     صفحة (أو صفحتين) لكل قسم
│   └── summarize/
│       ├── document_text.dart    فك pptx/docx واستخراج النص في المتصفح
│       ├── summarizer.dart       الواجهة المجردة + البرومبت المشترك
│       ├── ollama_summarizer.dart موديل محلي
│       ├── gemini_summarizer.dart Gemini من ورا Edge Function
│       └── ...                   صفحات التلخيص وأمثلة الأسلوب
└── widgets/common.dart           عناصر مشتركة
supabase/
├── config.toml                   إعدادات Supabase CLI
├── functions/summarize/          Edge Function ماسكة مفتاح Gemini
└── migrations/                   الجداول + سياسات RLS
```

---

## لو حاجة مامشيتش — Troubleshooting

| اللي بيحصل | السبب والحل |
|---|---|
| التطبيق فاتح على شاشة **"الاتصال بـ Supabase مش متظبط"** | المفتاح لسه ما اتحطش، أو التطبيق ما اتعادش تشغيله. القيم دي `const` فالـ hot reload مش بيلقطها — اقفل `flutter run` وشغّله تاني. |
| **Invalid login credentials** وانت متأكد من الباسورد | الإيميل لسه ما اتأكدش. دوّر على إيميل Supabase (بصّ في الـ Spam)، أو اقفل تأكيد الإيميل زي ما في خطوة 3. |
| **new row violates row-level security policy** | ملف الـ migration ما اتشغّلش كامل. رجّع خطوة 2 وشغّله تاني من أوله لآخره. |
| **relation "public.subjects" does not exist** | نفس الحاجة — الجداول ما اتعملتش. |
| التطبيق بيدي timeout بعد فترة ما استعملتوش | مشاريع الخطة المجانية بتتوقف بعد أسبوع من عدم الاستخدام. من الداشبورد اضغط **Restore project**. |
| **مش قادر أوصل لـ Ollama** في قسم التلخيص | Ollama مش شغال، أو المتصفح مش مسموح له. Ollama بيسمح لـ localhost تلقائيًا؛ لو بتفتح التطبيق من عنوان تاني شغّله بـ `OLLAMA_ORIGINS=*`. |
| **لازم تكون مسجّل دخول** من Gemini | التوكن انتهى. سجّل خروج ودخول تاني. |
| **خدمة التلخيص مش موجودة** | الفنكشن مش متنشرة: `npx supabase functions deploy summarize`. |
| **المفتاح ناقص أو غلط في الخدمة** | `npx supabase secrets set GEMINI_API_KEY=...` وبعدها انشر الفنكشن تاني. |
| **المحاضرة أطول من سياق الموديل** | كبّر حجم السياق من إعدادات التلخيص، أو قسّم المحاضرة. زيادة السياق بتاكل رام أكتر. |
| التلخيص طالع مش بأسلوبك | عدد الأمثلة قليل أو مش متسقة مع بعض. زوّدها لـ 4 واتأكد إنهم بنفس الشكل. |
| الخط العربي شكله مش زي الصورة | خط Cairo بيتحمّل من Google Fonts، فمحتاج نت في أول تشغيل. |

## ملاحظات — Notes

- **الخطوط**: التطبيق بيجيب خط Cairo من Google Fonts أول مرة. لو عايزه يشتغل
  أوفلاين، نزّل الخط وحطه في `assets/` واربطه في `pubspec.yaml`.
- **الصوت**: تنبيه آخر الجلسة بيستعمل صوت النظام — المتصفحات بتتجاهله غالبًا،
  فالإشارة على الويب بصرية.
- **الاختبارات**: `flutter test` بيشغّل اختبارات خوارزمية SM-2 وحسابات
  الإحصائيات والـ streak.
