# خطة تنفيذ واختبار المهام المطلوبة

> يتم تنفيذ كل مهمة بالترتيب وتشغيل اختباراتها كاملة قبل الانتقال للمهمة التالية.

---

## Task 1: إصلاح رفع ملفات Excel / CSV يدوياً
- [x] إنشاء `app/lib/services/file_bytes_reader.dart` + `file_bytes_reader_io.dart` + `file_bytes_reader_stub.dart` لقراءة الملفات عبر `path` على Android/iOS/Desktop عند غياب `bytes`.
- [x] تحديث `_pickSpreadsheetFile` في `app/lib/features/catalog/catalog_tree_screen.dart` لدعم fallback إلى `FileType.any` عند قيود Android SAF وقراءة الملف من `bytes` أو `path` أو `readStream`.
- [x] تقوية `app/lib/services/catalog_csv_service.dart`:
  - [x] دعم الفاصل `;` بجانب `,` و`\t` في CSV/TSV.
  - [x] اكتشاف صف العناوين تلقائياً (حتى لو سبقه صف عنوان أو تغير ترتيب الأعمدة) ودعم الأعمدة الاختيارية.
  - [x] استخراج نصوص `TextCellValue` (بما فيها rich-text `TextSpan`) وقيم الخلايا الرقمية والصيغ، مع رسالة واضحة لملفات `.xlsx` التالفة.
- [x] **اختبارات Task 1:**
  - [x] ملف `.xlsx` به صف عنوان قبل الـ header وأعمدة بترتيب مختلف وعناوين عربية (`السعر التجاري`، `الماركة`).
  - [x] ملف CSV مفصول بـ `;`.
  - [x] ملف `.xlsx` بأعمدة اختيارية ناقصة (`القسم`/`الوحدة`).
  - [x] نجاح `flutter analyze` و`flutter test` بدون أخطاء (12/12).

---

## Task 2: السعر التجاري + نسبة/مبلغ مكسب إجباري + عرض السعرين
- [x] إضافة عمود `commercial_price numeric(12,2)` في جدول `product_variants` (بدون إنشاء جدول جديد) عبر `supabase/migrations/0003_add_commercial_price.sql` وتنفيذه على قاعدة البيانات الحية.
- [x] تحديث `ProductVariantModel` في `app/lib/models/catalog_models.dart` بإضافة `commercialPrice` و`ProfitMarkupType` ودالة `calculateSellingPrice`.
- [x] تحديث `app/lib/providers/catalog_provider.dart` و`app/lib/services/catalog_csv_service.dart` لحساب وتخزين السعر التجاري وسعر البيع معاً في الاستيراد والتصدير والتعديل اليدوي.
- [x] تحديث واجهة `app/lib/features/catalog/catalog_tree_screen.dart`:
  - [x] إضافة اختيار إجباري في نافذة الاستيراد لتحديد نوع المكسب (**نسبة مئوية %** أو **رقم ثابت ج.م**) مع تعطيل زر الاستيراد حتى إدخال قيمة صالحة، ومعاينة السعر التجاري وسعر البيع.
  - [x] عرض السعرين (`بيع` و`تجاري`) في شرائح الأصناف وفي نافذة تعديل السعر.
- [x] **اختبارات Task 2:**
  - [x] حساب المكسب بالنسبة المئوية والمبلغ الثابت بدقة.
  - [x] حفظ واسترجاع `commercial_price` و`price` في `ProductVariantModel.toJson/fromJson`.
  - [x] اختبار نافذة الاستيراد (زر الاستيراد معطّل قبل إدخال المكسب ويعمل بعده) وعرض السعرين في شجرة الأصناف.
  - [x] التحقق من وجود العمود `commercial_price` في قاعدة بيانات Supabase الحية.
  - [x] نجاح `flutter analyze` و`flutter test` بدون أخطاء (13/13).

---

## Task 3: إزالة Gemini API والاعتماد على البدائل المجانية بالكامل
- [x] تحديث `supabase/functions/scan-invoice/index.ts` لإزالة `GEMINI_API_KEY` و`GEMINI_MODELS` و`attemptGemini` بالكامل.
- [x] تشغيل سباق متوازي على المزودين المجانيين غير التابعين لـ Gemini:
  - [x] Wave 1 (12s): GitHub Models `openai/gpt-4.1-mini` + OpenRouter (`google/gemma-4-31b-it:free`, `google/gemma-4-26b-a4b-it:free`).
  - [x] Wave 2 (18s): GitHub Models `openai/gpt-4o-mini` + OpenRouter (`nvidia/nemotron-3.5-super-vl:free`, `openrouter/free`).
- [x] نشر دالة `scan-invoice` على Supabase (`odcwpdoopefakvjhngor`).
- [x] **اختبارات والتحقق من Task 3:**
  - [x] التأكد من عدم وجود أي إشارة لـ `GEMINI` في `supabase/functions/scan-invoice/index.ts`.
  - [x] التأكد عبر `list_edge_functions` أن `scan-invoice` بحالة `ACTIVE` وبإصدار محدث.
