import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/main.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/services/catalog_csv_service.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';
import 'package:sanitary_pricing_app/services/scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'Renders Arabic Dashboard, navigates to Product Tree, and opens Demo AI Scan',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      // Dashboard renders Arabic hero action
      expect(find.text('تسعير ورقة جديدة (AI)'), findsOneWidget);

      // Navigate to Product Tree tab
      await tester.tap(find.text('الأصناف'));
      await tester.pumpAndSettle();

      expect(find.text('تغذية (بولي) (11)'), findsOneWidget);
      expect(find.text('كوع لحام'), findsWidgets);

      // Back to Home tab and launch Demo AI Scan
      await tester.tap(find.text('الرئيسية'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تسعير ورقة جديدة (AI)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تجربة كشف تجريبي جاهز (AI Demo)'));
      await tester.pumpAndSettle();

      // Review Screen shows brand switch/comparison and optional technician hint
      expect(find.text('تغيير الشركة / مقارنة'), findsOneWidget);
      expect(find.text('اسم الفني / السباك (اختياري)'), findsOneWidget);

      // Test switching brand to BR
      await tester.tap(find.text('تغيير الشركة / مقارنة'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('BR (متوسط)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تبديل الكشف الحالي إلى BR'));
      await tester.pumpAndSettle();

      expect(find.text('الشركة الحالية: BR'), findsOneWidget);
    },
  );

  test('CSV/Excel import parses rows and updates catalog state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final parsed = CatalogCsvService.parseImportText(
      'القسم\tاسم الصنف\tالمقاس\tالوحدة\tالشركة\tالسعر\n'
      'صرف\tكوع ريحة\t٤ بوصة\tقطعة\tالشريف\t١٣٥',
    );
    expect(parsed.rows.length, 1);
    expect(parsed.rows.first.price, 135);

    final importedCount = await container
        .read(catalogProvider.notifier)
        .importCatalogRows(parsed.rows);
    expect(importedCount, 1);

    final state = container.read(catalogProvider);
    expect(state.templates.any((t) => t.name == 'كوع ريحة'), isTrue);

    final exported = CatalogCsvService.exportCatalogCsv(state);
    expect(exported, contains('كوع ريحة'));
  });

  test('Share text omits technician line when blank and includes when provided',
      () {
    final baseInvoice = InvoiceModel(
      id: 'inv-t1',
      invoiceNumber: 'INV-00099',
      customerName: 'سعيد',
      createdAt: DateTime(2026, 11, 23),
      items: const [
        InvoiceItemModel(
          id: 'it-1',
          itemName: 'كوع لحام',
          size: '1/2 بوصة',
          quantity: 5,
          unitPrice: 18,
        ),
      ],
    );

    final withoutTech = InvoiceShareService.buildShareText(
      baseInvoice,
      DemoCatalogData.defaultSettings,
    );
    expect(withoutTech.contains('الفني:'), isFalse);

    final withTech = InvoiceShareService.buildShareText(
      baseInvoice.copyWith(technicianName: 'الأسطى رضا'),
      DemoCatalogData.defaultSettings,
    );
    expect(withTech.contains('الفني: الأسطى رضا'), isTrue);
  });

  testWidgets(
    'Excel sample template dialog imports cleanly without controller disposal errors',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('الأصناف'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.table_chart_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('إدراج نموذج جاهز'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('محابس وخلاطات'));
      await tester.pumpAndSettle();

      expect(find.text('محبس بلي نحاس'), findsOneWidget);
    },
  );

  test('Comparison share text summarizes totals, savings, and optional tech',
      () {
    final invA = InvoiceModel(
      id: 'c1',
      invoiceNumber: 'INV-00010',
      brandName: 'الشريف',
      customerName: 'طارق',
      createdAt: DateTime(2026, 11, 23),
      items: const [
        InvoiceItemModel(
          id: 'i1',
          itemName: 'كوع',
          quantity: 10,
          unitPrice: 20,
        ),
      ],
    );
    final invB = invA.copyWith(
      id: 'c2',
      invoiceNumber: 'INV-00011',
      brandName: 'BR',
      items: const [
        InvoiceItemModel(
          id: 'i2',
          itemName: 'كوع',
          quantity: 10,
          unitPrice: 15,
        ),
      ],
    );

    final text = InvoiceShareService.buildComparisonShareText(
      [invA, invB],
      DemoCatalogData.defaultSettings,
    );
    expect(text, contains('مقارنة عروض أسعار لنفس الكشف'));
    expect(text, contains('50 ج.م'));
    expect(text, contains('BR أوفر'));
    expect(text.contains('الفني:'), isFalse);
  });

  test('CatalogNotifier adds categories/brands and deletes learned aliases',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogProvider.notifier);
    await notifier.addCategory('عدد وأدوات');
    await notifier.addBrand(name: 'جروهي', tier: BrandTier.premium);

    var state = container.read(catalogProvider);
    expect(state.categories.any((c) => c.name == 'عدد وأدوات'), isTrue);
    expect(state.brands.any((b) => b.name == 'جروهي'), isTrue);

    final firstAliasId = state.aliases.first.id;
    notifier.deleteAlias(firstAliasId);
    state = container.read(catalogProvider);
    expect(state.aliases.any((a) => a.id == firstAliasId), isFalse);
  });

  testWidgets('Opens Reports screen from Dashboard and renders KPIs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SanitaryPricingApp(enableRemoteFonts: false),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('التقارير'));
    await tester.pumpAndSettle();

    expect(find.text('تقارير المبيعات والأداء'), findsOneWidget);
    expect(find.text('أداء الموظفين'), findsOneWidget);
    expect(find.text('الأصناف الأكثر طلباً'), findsOneWidget);
  });

  test('InvoiceModel.brandSummary formats 0, 1, and multiple brands', () {
    final emptyInv = InvoiceModel(
      id: 'b0',
      invoiceNumber: 'INV-00001',
      createdAt: DateTime(2026, 11, 23),
    );
    expect(emptyInv.brandSummary, isNull);

    final singleInv = emptyInv.copyWith(
      items: const [
        InvoiceItemModel(
          id: 'i1',
          itemName: 'كوع',
          brandName: 'راك',
          quantity: 1,
          unitPrice: 15,
        ),
        InvoiceItemModel(
          id: 'i2',
          itemName: 'ماسورة',
          brandName: 'راك',
          quantity: 2,
          unitPrice: 50,
        ),
      ],
    );
    expect(singleInv.brandSummary, 'راك');

    final multiInv = emptyInv.copyWith(
      items: const [
        InvoiceItemModel(
          id: 'i1',
          itemName: 'كوع',
          brandName: 'راك',
          quantity: 1,
          unitPrice: 15,
        ),
        InvoiceItemModel(
          id: 'i2',
          itemName: 'ماسورة',
          brandName: 'الشريف',
          quantity: 2,
          unitPrice: 50,
        ),
        InvoiceItemModel(
          id: 'i3',
          itemName: 'محبس',
          brandName: 'BR',
          quantity: 1,
          unitPrice: 80,
        ),
      ],
    );
    expect(multiInv.brandSummary, 'راك +2');
  });

  test('ScanService.detectBrandFromText detects brand from noisy text', () {
    const brands = [
      BrandModel(id: 'b-rak', name: 'راك', tier: BrandTier.mid),
      BrandModel(id: 'b-sh', name: 'الشريف', tier: BrandTier.premium),
    ];

    expect(
      ScanService.detectBrandFromText('كوع راك ثيرم 3/4', brands)?.name,
      'راك',
    );
    expect(
      ScanService.detectBrandFromText('ماسورة RAK 20 مم', brands)?.name,
      'راك',
    );
    expect(
      ScanService.detectBrandFromText('كوع بولي 3/4', brands),
      isNull,
    );
  });

  testWidgets(
    'Prompts to save or discard when leaving ReviewScreen with unsaved scan',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('تسعير ورقة جديدة (AI)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('تجربة كشف تجريبي جاهز (AI Demo)'));
      await tester.pumpAndSettle();

      expect(find.text('تغيير الشركة / مقارنة'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('حفظ الكشف قبل الخروج؟'), findsOneWidget);
      expect(find.text('حفظ كعرض سعر'), findsOneWidget);
      expect(find.text('مسح والخروج'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'حفظ كعرض سعر'));
      await tester.pumpAndSettle();

      expect(find.text('تسعير ورقة جديدة (AI)'), findsOneWidget);
    },
  );

  test('CatalogCsvService.parseUploadedFile decodes .xlsx workbook bytes', () {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([
      xl.TextCellValue('القسم'),
      xl.TextCellValue('اسم الصنف'),
      xl.TextCellValue('المقاس'),
      xl.TextCellValue('الوحدة'),
      xl.TextCellValue('الشركة'),
      xl.TextCellValue('السعر'),
    ]);
    sheet.appendRow([
      xl.TextCellValue('تغذية (بولي)'),
      xl.TextCellValue('كوع لحام'),
      xl.TextCellValue('3/4 بوصة'),
      xl.TextCellValue('قطعة'),
      xl.TextCellValue('راك'),
      xl.DoubleCellValue(24.5),
    ]);
    sheet.appendRow([
      xl.TextCellValue('صرف'),
      xl.TextCellValue('سيفونة أرضية'),
      xl.TextCellValue('غير مذكور'),
      xl.TextCellValue('قطعة'),
      xl.TextCellValue('راك'),
      xl.TextCellValue('١٣٥'),
    ]);

    final raw = excel.encode();
    expect(raw, isNotNull);

    final parsed = CatalogCsvService.parseUploadedFile(
      fileName: 'prices.xlsx',
      bytes: Uint8List.fromList(raw!),
    );
    expect(parsed.skippedLines, 0);
    expect(parsed.rows.length, 2);
    expect(parsed.rows[0].itemName, 'كوع لحام');
    expect(parsed.rows[0].size, '3/4 بوصة');
    expect(parsed.rows[0].price, 24.5);
    expect(parsed.rows[1].size, isNull);
    expect(parsed.rows[1].price, 135);
  });
}
