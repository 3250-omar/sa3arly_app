# دليل إعداد وتشغيل Supabase + الذكاء الاصطناعي (Gemini 2.5 Flash)

اتبع الخطوات دي لربط التطبيق بمشروع Supabase خاص بمحلك:

## 1. إنشاء مشروع Supabase
1. ادخل على [supabase.com](https://supabase.com) واعمل مشروع جديد (اختر منطقة قريبة زي `eu-central-1`).
2. من **SQL Editor** داخل لوحة تحكم Supabase:
   - افتح ملف `supabase/migrations/0001_initial_schema.sql` وشغّله بالكامل (Run).
   - افتح ملف `supabase/seed.sql` وشغّله لإضافة الأقسام والشركات والـ 20 صنف التجريبيين (أو عدّلهم بأصناف محلك).

## 2. إنشاء حساب المدير (Admin)
1. من **Authentication → Users → Add user** أضف إيميلك وكلمة السر.
2. أول مستخدم يتم إنشاؤه سيحصل تلقائياً على صلاحية **`admin`**، وأي موظف تضيفه بعد كده سيأخذ صلاحية **`staff`** تلقائياً (وتقدر تعدّل صلاحيته من جدول `profiles`).

## 3. تفعيل الـ AI OCR (Edge Function)
1. احصل على مفتاح **Gemini API** من [Google AI Studio](https://aistudio.google.com/apikey).
2. ثبّت Supabase CLI أو استخدم لوحة التحكم لرفع الدالة `supabase/functions/scan-invoice/index.ts`.
3. أضف الأسرار (Secrets) للدالة على سيرفر Supabase (لا تضعها أبداً في كود التطبيق):
   ```bash
   supabase secrets set GEMINI_API_KEY="ضع_مفتاح_جيميناي_هنا"
   supabase secrets set ALLOWED_ORIGINS="https://your-domain.com"
   supabase functions deploy scan-invoice
   ```

## 4. تشغيل تطبيق Flutter مع مفاتيح المشروع
من **Project Settings → API** انسخ `Project URL` و `anon public key`، وشغّل التطبيق بدون تخزين المفاتيح في الكود:

```bash
flutter run -d chrome --web-hostname 127.0.0.1 \
  --dart-define=SUPABASE_URL="https://YOUR-PROJECT.supabase.co" \
  --dart-define=SUPABASE_ANON_KEY="YOUR-ANON-KEY"
```

> **ملاحظة:** لو شغّلت التطبيق من غير `--dart-define`، هيشتغل تلقائياً في **وضع التجربة (Demo Mode)** ببيانات الأدوات الصحية الجاهزة عشان تجرب الشاشات والمميزات فوراً.
