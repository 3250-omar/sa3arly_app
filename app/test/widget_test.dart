import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/features/shell/main_shell.dart';
import 'package:sanitary_pricing_app/main.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
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
        .importCatalogRows(
          parsed.rows,
          markupType: ProfitMarkupType.percent,
          markupValue: 20,
        );
    expect(importedCount, 1);

    final state = container.read(catalogProvider);
    final tpl = state.templates.firstWhere((t) => t.name == 'كوع ريحة');
    final variant = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id,
    );
    expect(variant.commercialPrice, 135);
    expect(variant.price, 162);

    final exported = CatalogCsvService.exportCatalogCsv(state);
    expect(exported, contains('كوع ريحة'));
    expect(exported, contains('السعر التجاري'));
    expect(exported, contains('سعر البيع'));
  });

  test(
    'Share text omits technician line when blank and includes when provided',
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
    },
  );

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
      await tester.ensureVisible(
        find.byKey(const Key('import_price_mode_commercial')),
      );
      await tester.tap(find.byKey(const Key('import_price_mode_commercial')));
      await tester.pumpAndSettle();

      // Mandatory profit validation must prevent importing before entering markup
      expect(
        find.text('مطلوب إدخال قيمة المكسب لحساب سعر البيع قبل الاستيراد'),
        findsOneWidget,
      );
      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();
      // Dialog remains open because markup is mandatory
      expect(find.byKey(const Key('profit_markup_field')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('profit_markup_field')));
      await tester.enterText(
        find.byKey(const Key('profit_markup_field')),
        '20',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('محابس وخلاطات'));
      await tester.pumpAndSettle();

      expect(find.text('محبس بلي نحاس'), findsOneWidget);
      expect(find.textContaining('بيع 252 ج.م'), findsOneWidget);
      expect(find.textContaining('تجاري 210 ج.م'), findsOneWidget);
    },
  );

  test(
    'Comparison share text summarizes totals, savings, and optional tech',
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

      final text = InvoiceShareService.buildComparisonShareText([
        invA,
        invB,
      ], DemoCatalogData.defaultSettings);
      expect(text, contains('مقارنة عروض أسعار لنفس الكشف'));
      expect(text, contains('50 ج.م'));
      expect(text, contains('BR أوفر'));
      expect(text.contains('الفني:'), isFalse);
    },
  );

  test(
    'CatalogNotifier adds categories/brands and deletes learned aliases',
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
    },
  );

  testWidgets('Opens Reports screen from Dashboard and renders KPIs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: SanitaryPricingApp(enableRemoteFonts: false)),
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
    expect(ScanService.detectBrandFromText('كوع بولي 3/4', brands), isNull);
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

  test('CatalogCsvService handles title rows, reordered headers, optional columns, and semicolon CSV', () {
    // 1. .xlsx with title banner row, reordered Arabic headers, and missing optional columns
    final excel = xl.Excel.createExcel();
    final sheet = excel['Sheet1'];
    sheet.appendRow([xl.TextCellValue('قائمة أسعار المحل التجاري 2026')]);
    sheet.appendRow([
      xl.TextCellValue('اسم الصنف'),
      xl.TextCellValue('الماركة'),
      xl.TextCellValue('السعر التجاري'),
      xl.TextCellValue('المقاس'),
    ]);
    sheet.appendRow([
      xl.TextCellValue('جلبة لحام'),
      xl.TextCellValue('الشريف'),
      xl.DoubleCellValue(32.5),
      xl.TextCellValue('1 بوصة'),
    ]);
    final raw = excel.encode()!;

    final parsedXlsx = CatalogCsvService.parseUploadedFile(
      fileName: 'commercial_list.xlsx',
      bytes: Uint8List.fromList(raw),
    );
    expect(parsedXlsx.rows.length, 1);
    expect(parsedXlsx.rows.first.itemName, 'جلبة لحام');
    expect(parsedXlsx.rows.first.brandName, 'الشريف');
    expect(parsedXlsx.rows.first.price, 32.5);
    expect(parsedXlsx.rows.first.size, '1 بوصة');
    expect(parsedXlsx.rows.first.categoryName, 'عام');
    expect(parsedXlsx.rows.first.unit, 'قطعة');

    // 2. Semicolon CSV
    final parsedSemi = CatalogCsvService.parseImportText(
      'القسم;اسم الصنف;المقاس;الوحدة;الشركة;السعر التجاري\n'
      'تغذية;كوع بسن;1/2 بوصة;قطعة;BR;45',
    );
    expect(parsedSemi.rows.length, 1);
    expect(parsedSemi.rows.first.price, 45);
    expect(parsedSemi.rows.first.brandName, 'BR');
  });

  test(
    'Profit markup calculations and ProductVariantModel commercial_price JSON',
    () async {
      expect(calculateSellingPrice(100, ProfitMarkupType.percent, 20), 120);
      expect(calculateSellingPrice(100, ProfitMarkupType.fixed, 15), 115);

      const variant = ProductVariantModel(
        id: 'v-1',
        itemTemplateId: 't-1',
        brandId: 'b-1',
        price: 115,
        commercialPrice: 100,
      );
      final json = variant.toJson();
      expect(json['commercial_price'], 100);
      expect(json['price'], 115);

      final decoded = ProductVariantModel.fromJson(json);
      expect(decoded.commercialPrice, 100);
      expect(decoded.price, 115);

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final parsed = CatalogCsvService.parseImportText(
        'القسم,اسم الصنف,المقاس,الوحدة,الشركة,السعر التجاري\n'
        'تغذية (بولي),ماسورة اختبار,1 بوصة,متر,الشريف,100',
      );
      await container
          .read(catalogProvider.notifier)
          .importCatalogRows(
            parsed.rows,
            markupType: ProfitMarkupType.fixed,
            markupValue: 15,
          );
      final state = container.read(catalogProvider);
      final tpl = state.templates.firstWhere((t) => t.name == 'ماسورة اختبار');
      final saved = state.variants.firstWhere(
        (v) => v.itemTemplateId == tpl.id,
      );
      expect(saved.commercialPrice, 100);
      expect(saved.price, 115);
    },
  );

  test('CatalogCsvService parses .xlsx with complex/malformed styles.xml and formula cached values', () {
    ArchiveFile xmlEntry(String path, String xml) {
      final bytes = utf8.encode(xml);
      return ArchiveFile(path, bytes.length, bytes);
    }

    final archive = Archive()
      ..addFile(
        xmlEntry(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets>'
              '</workbook>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/styles.xml',
          '<?xml version="1.0"?><styleSheet><numFmts count="1"><numFmt numFmtId="164" formatCode="0.00%"/></numFmts></styleSheet>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/sharedStrings.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<si><t>القسم</t></si>'
              '<si><t>اسم الصنف</t></si>'
              '<si><t>المقاس</t></si>'
              '<si><t>الوحدة</t></si>'
              '<si><t>الشركة</t></si>'
              '<si><t>السعر</t></si>'
              '<si><t>صرف</t></si>'
              '<si><t>كوع عادي</t></si>'
              '<si><t>32 مم</t></si>'
              '<si><t>قطعة</t></si>'
              '<si><t>وايتكس</t></si>'
              '</sst>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/worksheets/sheet1.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<sheetData>'
              '<row r="1">'
              '<c r="A1" t="s"><v>0</v></c>'
              '<c r="B1" t="s"><v>1</v></c>'
              '<c r="C1" t="s"><v>2</v></c>'
              '<c r="D1" t="s"><v>3</v></c>'
              '<c r="E1" t="s"><v>4</v></c>'
              '<c r="F1" t="s"><v>5</v></c>'
              '</row>'
              '<row r="2">'
              '<c r="A2" t="s"><v>6</v></c>'
              '<c r="B2" t="s"><v>7</v></c>'
              '<c r="C2" t="s"><v>8</v></c>'
              '<c r="D2" t="s"><v>9</v></c>'
              '<c r="E2" t="s"><v>10</v></c>'
              '<c r="F2" s="1"><f>Sheet2!F2*(1+Sheet2!\$H\$2)</f><v>16.8</v></c>'
              '</row>'
              '</sheetData>'
              '</worksheet>',
        ),
      );

    final zipped = ZipEncoder().encode(archive)!;
    final parsed = CatalogCsvService.parseUploadedFile(
      fileName: 'waitex.xlsx',
      bytes: Uint8List.fromList(zipped),
    );

    expect(parsed.skippedLines, 0);
    expect(parsed.rows.length, 1);
    expect(parsed.rows.first.categoryName, 'صرف');
    expect(parsed.rows.first.itemName, 'كوع عادي');
    expect(parsed.rows.first.size, '32 مم');
    expect(parsed.rows.first.brandName, 'وايتكس');
    expect(parsed.rows.first.price, 16.8);
  });

  test('CatalogCsvService evaluates uncached multi-sheet formulas and prefixed XML namespaces', () {
    ArchiveFile xmlEntry(String path, String xml) {
      final bytes = utf8.encode(xml);
      return ArchiveFile(path, bytes.length, bytes);
    }

    final archive = Archive()
      ..addFile(
        xmlEntry(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<x:workbook xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
              'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
              '<x:sheets>'
              '<x:sheet name="البيع" sheetId="1" r:id="rId1"/>'
              '<x:sheet name="الأسعار" sheetId="2" r:id="rId2"/>'
              '</x:sheets>'
              '</x:workbook>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
              '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet1.xml"/>'
              '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet2.xml"/>'
              '</Relationships>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/sharedStrings.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<x:sst xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<x:si><x:t>القسم</x:t></x:si>'
              '<x:si><x:t>اسم الصنف</x:t></x:si>'
              '<x:si><x:t>المقاس</x:t></x:si>'
              '<x:si><x:t>الوحدة</x:t></x:si>'
              '<x:si><x:t>الشركة</x:t></x:si>'
              '<x:si><x:t>السعر</x:t></x:si>'
              '<x:si><x:t>صرف</x:t></x:si>'
              '<x:si><x:t>كوع عادي</x:t></x:si>'
              '<x:si><x:t>32 مم</x:t></x:si>'
              '<x:si><x:t>قطعة</x:t></x:si>'
              '<x:si><x:t>وايتكس</x:t></x:si>'
              '</x:sst>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/worksheets/sheet1.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<x:sheetData>'
              '<x:row r="1">'
              '<x:c r="A1" t="s"><x:v>0</x:v></x:c>'
              '<x:c r="B1" t="s"><x:v>1</x:v></x:c>'
              '<x:c r="C1" t="s"><x:v>2</x:v></x:c>'
              '<x:c r="D1" t="s"><x:v>3</x:v></x:c>'
              '<x:c r="E1" t="s"><x:v>4</x:v></x:c>'
              '<x:c r="F1" t="s"><x:v>5</x:v></x:c>'
              '</x:row>'
              '<x:row r="2">'
              '<x:c r="A2" t="s"><x:v>6</x:v></x:c>'
              '<x:c r="B2" t="s"><x:v>7</x:v></x:c>'
              '<x:c r="C2" t="s"><x:v>8</x:v></x:c>'
              '<x:c r="D2" t="s"><x:v>9</x:v></x:c>'
              '<x:c r="E2" t="s"><x:v>10</x:v></x:c>'
              '<x:c r="F2"><x:f>ROUND(\'الأسعار\'!F2*(1+\'الأسعار\'!\$H\$2), 2)</x:f></x:c>'
              '</x:row>'
              '</x:sheetData>'
              '</x:worksheet>',
        ),
      )
      ..addFile(
        xmlEntry(
          'xl/worksheets/sheet2.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
              '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
              '<x:sheetData>'
              '<x:row r="2">'
              '<x:c r="F2"><x:f>19*0.85</x:f></x:c>'
              '<x:c r="H2"><x:v>0.04</x:v></x:c>'
              '</x:row>'
              '</x:sheetData>'
              '</x:worksheet>',
        ),
      );

    final zipped = ZipEncoder().encode(archive)!;
    final parsed = CatalogCsvService.parseUploadedFile(
      fileName: 'uncached_formulas.xlsx',
      bytes: Uint8List.fromList(zipped),
    );

    expect(parsed.skippedLines, 0);
    expect(parsed.rows.length, 1);
    expect(parsed.rows.first.itemName, 'كوع عادي');
    expect(parsed.rows.first.brandName, 'وايتكس');
    expect(parsed.rows.first.price, 16.8);
  });

  test('CatalogNotifier.applyProfitMarkup recalculates selling prices from commercialPrice with filters', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogProvider.notifier);
    final parsed = CatalogCsvService.parseImportText(
      'القسم\tاسم الصنف\tالمقاس\tالوحدة\tالشركة\tالسعر\n'
      'صرف\tكوع عادي\t50 مم\tقطعة\tالشريف\t100\n'
      'صرف\tكوع عادي\t50 مم\tقطعة\tBR\t80',
    );

    final imported = await notifier.importCatalogRows(
      parsed.rows,
      markupType: ProfitMarkupType.percent,
      markupValue: 20,
    );
    expect(imported, 2);

    var state = container.read(catalogProvider);
    final tpl = state.templates.firstWhere((t) => t.name == 'كوع عادي');
    final shBrand = state.brands.firstWhere((b) => b.name == 'الشريف');
    final brBrand = state.brands.firstWhere((b) => b.name == 'BR');

    // Pick an existing demo variant without commercialPrice to ensure it stays untouched
    final demoVariantBefore = state.variants.firstWhere(
      (v) => v.commercialPrice == null,
    );

    // 1. Re-calculate percent markup ONLY for الشريف
    final updatedShCount = await notifier.applyProfitMarkup(
      markupType: ProfitMarkupType.percent,
      markupValue: 30,
      brandId: shBrand.id,
    );
    expect(updatedShCount, 1);

    state = container.read(catalogProvider);
    final shVar = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == shBrand.id,
    );
    final brVar = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == brBrand.id,
    );
    expect(shVar.commercialPrice, 100);
    expect(shVar.price, 130);
    expect(brVar.commercialPrice, 80);
    expect(brVar.price, 96); // unchanged 20%

    // 2. Re-calculate fixed markup (+15) across all items with commercialPrice
    final updatedAllCount = await notifier.applyProfitMarkup(
      markupType: ProfitMarkupType.fixed,
      markupValue: 15,
    );
    expect(updatedAllCount, 2);

    state = container.read(catalogProvider);
    final shVar2 = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == shBrand.id,
    );
    final brVar2 = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == brBrand.id,
    );
    final demoVariantAfter = state.variants.firstWhere(
      (v) => v.id == demoVariantBefore.id,
    );
    expect(shVar2.commercialPrice, 100);
    expect(shVar2.price, 115);
    expect(brVar2.commercialPrice, 80);
    expect(brVar2.price, 95);
    expect(demoVariantAfter.price, demoVariantBefore.price);
  });

  testWidgets(
    'Update profit margin dialog recalculates selling prices after import',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('الأصناف'));
      await tester.pumpAndSettle();

      // First import sample template with 20% profit (تجاري 210 -> بيع 252)
      await tester.tap(find.byIcon(Icons.table_chart_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('إدراج نموذج جاهز'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('import_price_mode_commercial')),
      );
      await tester.tap(find.byKey(const Key('import_price_mode_commercial')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profit_markup_field')));
      await tester.enterText(
        find.byKey(const Key('profit_markup_field')),
        '20',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();

      // Now open the post-upload profit margin update dialog and change to 10%
      await tester.tap(find.byKey(const Key('update_profit_button')));
      await tester.pumpAndSettle();

      expect(find.text('تعديل نسبة / قيمة الربح'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('القسم'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('كل الأقسام'),
        ),
        findsNothing,
      );
      expect(find.byKey(const Key('current_profit_info')), findsOneWidget);
      expect(find.text('الربح الحالي: نسبة مئوية 20%'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('bulk_profit_markup_field')),
        '10',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('apply_profit_button')));
      await tester.pumpAndSettle();

      // Re-open dialog to confirm the displayed current profit updated to 10%
      await tester.tap(find.byKey(const Key('update_profit_button')));
      await tester.pumpAndSettle();
      expect(find.text('الربح الحالي: نسبة مئوية 10%'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();

      // Filter category to view imported item محبس بلي نحاس (210 * 1.1 = 231)
      await tester.tap(find.text('محابس وخلاطات'));
      await tester.pumpAndSettle();

      expect(find.text('محبس بلي نحاس'), findsOneWidget);
      expect(find.textContaining('بيع 231 ج.م'), findsOneWidget);
      expect(find.textContaining('تجاري 210 ج.م'), findsOneWidget);
    },
  );

  test('calculateDiscountedCommercialPrice and importCatalogRows apply company discount before profit markup', () async {
    expect(calculateDiscountedCommercialPrice(100, 15), 85);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(catalogProvider.notifier);
    final parsed = CatalogCsvService.parseImportText(
      'القسم\tاسم الصنف\tالمقاس\tالوحدة\tالشركة\tالسعر\n'
      'صرف\tتيه لحام\t50 مم\tقطعة\tالشريف\t100',
    );

    final imported = await notifier.importCatalogRows(
      parsed.rows,
      markupType: ProfitMarkupType.percent,
      markupValue: 20,
      companyDiscountPercent: 15,
    );
    expect(imported, 1);

    var state = container.read(catalogProvider);
    final tpl = state.templates.firstWhere((t) => t.name == 'تيه لحام');
    final shBrand = state.brands.firstWhere((b) => b.name == 'الشريف');
    final v1 = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == shBrand.id,
    );
    expect(v1.commercialPrice, 85);
    expect(v1.price, 102);

    // Post-upload profit update recalculates from the discounted commercial price (85)
    await notifier.applyProfitMarkup(
      markupType: ProfitMarkupType.percent,
      markupValue: 10,
      brandId: shBrand.id,
    );
    state = container.read(catalogProvider);
    final v2 = state.variants.firstWhere(
      (v) => v.itemTemplateId == tpl.id && v.brandId == shBrand.id,
    );
    expect(v2.commercialPrice, 85);
    expect(v2.price, 93.5);
  });

  testWidgets(
    'Excel import dialog applies optional company discount before profit markup',
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

      await tester.ensureVisible(
        find.byKey(const Key('import_price_mode_commercial')),
      );
      await tester.tap(find.byKey(const Key('import_price_mode_commercial')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('company_discount_toggle')),
      );
      await tester.tap(find.byKey(const Key('company_discount_toggle')));
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('company_discount_field')),
      );
      await tester.enterText(
        find.byKey(const Key('company_discount_field')),
        '10',
      );
      await tester.ensureVisible(find.byKey(const Key('profit_markup_field')));
      await tester.enterText(
        find.byKey(const Key('profit_markup_field')),
        '20',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('محابس وخلاطات'));
      await tester.pumpAndSettle();

      expect(find.text('محبس بلي نحاس'), findsOneWidget);
      expect(find.textContaining('تجاري 189 ج.م'), findsOneWidget);
      expect(find.textContaining('بيع 226.8 ج.م'), findsOneWidget);
    },
  );

  test(
    'CatalogNotifier normalizes وصلات صرف category into صرف on import',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(catalogProvider.notifier);
      final parsed = CatalogCsvService.parseImportText(
        'القسم\tاسم الصنف\tالمقاس\tالوحدة\tالشركة\tالسعر\n'
        'وصلات صرف\tطربوش تهوية\t4 بوصة\tقطعة\tالشريف\t55',
      );

      final count = await notifier.importCatalogRows(
        parsed.rows,
        markupType: ProfitMarkupType.percent,
        markupValue: 10,
      );
      expect(count, 1);

      final state = container.read(catalogProvider);
      expect(state.categories.any((c) => c.name == 'وصلات صرف'), isFalse);
      final drainCat = state.categories.firstWhere((c) => c.name == 'صرف');
      final tpl = state.templates.firstWhere((t) => t.name == 'طربوش تهوية');
      expect(tpl.categoryId, drainCat.id);
    },
  );

  test('InvoiceShareService normalizes Egyptian customer phone and builds wa.me URI', () {
    expect(
      InvoiceShareService.normalizeEgyptianWhatsAppPhone('٠١٠١٢٣٤٥٦٧٨'),
      '201012345678',
    );
    expect(
      InvoiceShareService.normalizeEgyptianWhatsAppPhone('00201128543192'),
      '201128543192',
    );
    expect(InvoiceShareService.normalizeEgyptianWhatsAppPhone('1234'), isNull);

    final invWithPhone = InvoiceModel(
      id: 'w1',
      invoiceNumber: 'INV-00050',
      customerName: 'أحمد علي',
      customerPhone: '01012345678',
      createdAt: DateTime(2026, 11, 25),
    );
    final uriWithPhone = InvoiceShareService.buildWhatsAppUri(
      invoice: invWithPhone,
      shop: DemoCatalogData.defaultSettings,
    );
    expect(uriWithPhone.host, 'wa.me');
    expect(uriWithPhone.path, '/201012345678');
    expect(uriWithPhone.queryParameters['text'], contains('أحمد علي'));

    final uriNoPhone = InvoiceShareService.buildWhatsAppUri(
      invoice: invWithPhone.copyWith(customerPhone: ''),
      shop: DemoCatalogData.defaultSettings,
    );
    expect(uriNoPhone.path, '/');
  });

  testWidgets(
    'ReviewScreen hides inline share buttons, validates customer name, and shows WhatsApp/PDF popup after approval',
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

      // Inline share buttons must be hidden on ReviewScreen
      expect(find.text('مشاركة PDF (واتساب / تليجرام)'), findsNothing);
      expect(find.text('معاينة / طباعة PDF'), findsNothing);

      // Confirm all unconfirmed items via filter tabs so Approve button becomes enabled
      for (final filterKey in [
        const Key('review_filter_medium'),
        const Key('review_filter_low'),
      ]) {
        await tester.ensureVisible(find.byKey(filterKey));
        await tester.tap(find.byKey(filterKey));
        await tester.pumpAndSettle();
        while (find.byIcon(Icons.check_rounded).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.check_rounded).first);
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const Key('review_filter_all')));
      await tester.pumpAndSettle();

      // Clear customer name and verify validation prevents approval
      await tester.dragUntilVisible(
        find.byKey(const Key('review_customer_name_field')),
        find.byType(ListView).first,
        const Offset(0, 200),
      );
      await tester.enterText(
        find.byKey(const Key('review_customer_name_field')),
        '',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('اعتماد ('));
      await tester.pumpAndSettle();

      expect(find.text('مطلوب إدخال اسم العميل أولاً'), findsOneWidget);
      expect(find.text('تم اعتماد الفاتورة بنجاح'), findsNothing);

      // Enter customer name & phone, then approve
      await tester.enterText(
        find.byKey(const Key('review_customer_name_field')),
        'أحمد علي',
      );
      await tester.enterText(
        find.byKey(const Key('review_customer_phone_field')),
        '01012345678',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.textContaining('اعتماد ('));
      await tester.pumpAndSettle();

      // Post-approval dialog appears with direct WhatsApp, PDF, and save-only
      expect(find.text('تم اعتماد الفاتورة بنجاح'), findsOneWidget);
      expect(find.byKey(const Key('approved_whatsapp_btn')), findsOneWidget);
      expect(find.text('إرسال واتساب إلى 01012345678'), findsOneWidget);
      expect(find.byKey(const Key('approved_share_pdf_btn')), findsOneWidget);
      expect(find.byKey(const Key('approved_preview_pdf_btn')), findsOneWidget);
      expect(find.byKey(const Key('approved_save_only_btn')), findsOneWidget);
      expect(find.text('حفظ فقط'), findsOneWidget);

      await tester.tap(find.byKey(const Key('approved_save_only_btn')));
      await tester.pumpAndSettle();

      expect(find.text('تم اعتماد الفاتورة بنجاح'), findsNothing);
    },
  );

  test('PaymentMethod and InvoiceModel compute paid/remaining amounts, DB payload, and share text', () {
    final inv = InvoiceModel(
      id: 'pay-1',
      invoiceNumber: 'INV-00100',
      status: InvoiceStatus.approved,
      customerName: 'حسن إبراهيم',
      paymentMethod: PaymentMethod.deferredWithDeposit,
      paidAmount: 400,
      paymentDueDate: DateTime(2026, 12, 10),
      createdAt: DateTime(2026, 11, 25),
      items: const [
        InvoiceItemModel(
          id: 'pi-1',
          itemName: 'ماسورة',
          quantity: 10,
          unitPrice: 100,
        ),
      ],
    );

    expect(inv.total, 1000);
    expect(inv.effectivePaidAmount, 400);
    expect(inv.remainingAmount, 600);

    final dbRow = inv.toDbRow();
    expect(dbRow['payment_method'], 'deferred_with_deposit');
    expect(dbRow['paid_amount'], 400);
    expect(dbRow['payment_due_date'], '2026-12-10');

    final decoded = InvoiceModel.fromJson({
      ...inv.toCacheJson(),
      'invoice_items': const [],
    });
    expect(decoded.paymentMethod, PaymentMethod.deferredWithDeposit);
    expect(decoded.paidAmount, 400);
    expect(decoded.paymentDueDate, DateTime(2026, 12, 10));

    final shareText = InvoiceShareService.buildShareText(
      inv,
      DemoCatalogData.defaultSettings,
    );
    expect(shareText, contains('طريقة التحصيل: آجل بمقدم'));
    expect(shareText, contains('المدفوع / المقدم: 400 ج.م'));
    expect(shareText, contains('المتبقي: 600 ج.م'));
    expect(shareText, contains('موعد السداد: 2026-12-10'));
  });

  testWidgets(
    'ReviewScreen shows conditional payment collection fields and validates due date on approval',
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

      // Scroll down to Payment Collection Card in the lazy ListView
      await tester.scrollUntilVisible(
        find.byKey(const Key('payment_method_dropdown')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Default is cash — paid_amount_field and payment_due_date_picker are hidden
      expect(find.byKey(const Key('payment_method_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('paid_amount_field')), findsNothing);
      expect(find.byKey(const Key('payment_due_date_picker')), findsNothing);

      // 1. Switch to partialNowRestLater -> shows both paid_amount_field & payment_due_date_picker
      await tester.tap(find.byKey(const Key('payment_method_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('جزء الآن وجزء بعد الانتهاء').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paid_amount_field')), findsOneWidget);
      expect(find.byKey(const Key('payment_due_date_picker')), findsOneWidget);

      // 2. Switch to deferredNoDeposit -> hides paid_amount_field, keeps payment_due_date_picker
      await tester.ensureVisible(
        find.byKey(const Key('payment_method_dropdown')),
      );
      await tester.tap(find.byKey(const Key('payment_method_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('آجل بدون مقدم').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paid_amount_field')), findsNothing);
      expect(find.byKey(const Key('payment_due_date_picker')), findsOneWidget);

      // Confirm all unconfirmed items via filter tabs so Approve button is enabled
      for (final filterKey in [
        const Key('review_filter_medium'),
        const Key('review_filter_low'),
      ]) {
        await tester.dragUntilVisible(
          find.byKey(filterKey),
          find.byType(ListView).first,
          const Offset(0, 200),
        );
        await tester.tap(find.byKey(filterKey));
        await tester.pumpAndSettle();
        while (find.byIcon(Icons.check_rounded).evaluate().isNotEmpty) {
          await tester.tap(find.byIcon(Icons.check_rounded).first);
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.byKey(const Key('review_filter_all')));
      await tester.pumpAndSettle();
      await tester.dragUntilVisible(
        find.byKey(const Key('payment_method_dropdown')),
        find.byType(ListView).first,
        const Offset(0, -250),
      );

      // Approval must block without due date
      await tester.tap(find.textContaining('اعتماد ('));
      await tester.pumpAndSettle();
      expect(find.text('مطلوب تحديد موعد السداد'), findsOneWidget);

      // 3. Switch to deferredWithDeposit -> shows both deposit field & due date picker
      await tester.ensureVisible(
        find.byKey(const Key('payment_method_dropdown')),
      );
      await tester.tap(find.byKey(const Key('payment_method_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('آجل بمقدم').last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('paid_amount_field')), findsOneWidget);
      expect(find.byKey(const Key('payment_due_date_picker')), findsOneWidget);
    },
  );

  test(
    'CatalogNotifier adds, updates, and prevents duplicate aliases',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(catalogProvider.notifier);
      final targetTpl = container.read(catalogProvider).templates.first;

      // 1. Add new alias
      final addErr = await notifier.addAlias(
        aliasText: 'كوع صاروخ نص',
        itemTemplateId: targetTpl.id,
      );
      expect(addErr, isNull);

      var state = container.read(catalogProvider);
      final added = state.aliases.firstWhere(
        (a) => a.aliasText == 'كوع صاروخ نص',
      );
      expect(added.itemTemplateId, targetTpl.id);

      // 2. Duplicate add rejected
      final dupErr = await notifier.addAlias(
        aliasText: '  كوع صاروخ نص  ',
        itemTemplateId: targetTpl.id,
      );
      expect(dupErr, isNotNull);

      // 3. Update existing alias
      final secondTpl = state.templates.last;
      final updErr = await notifier.updateAlias(
        aliasId: added.id,
        aliasText: 'كوع سريع نص',
        itemTemplateId: secondTpl.id,
      );
      expect(updErr, isNull);

      state = container.read(catalogProvider);
      final updated = state.aliases.firstWhere((a) => a.id == added.id);
      expect(updated.aliasText, 'كوع سريع نص');
      expect(updated.itemTemplateId, secondTpl.id);
    },
  );

  testWidgets(
    'Settings technician dictionary supports expanding, adding, and updating aliases',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('الإعدادات'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const Key('technician_dictionary_expansion')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(
        find.byKey(const Key('technician_dictionary_expansion')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('add_alias_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('alias_text_field')),
        'مسمى تجريبي جديد',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_alias_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('مسمى تجريبي جديد'), findsOneWidget);

      // Tap the newly added alias chip to edit it
      await tester.tap(find.textContaining('مسمى تجريبي جديد'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('alias_text_field')),
        'مسمى تجريبي محدث',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('save_alias_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('مسمى تجريبي محدث'), findsOneWidget);
      expect(find.textContaining('مسمى تجريبي جديد'), findsNothing);
    },
  );

  test('InvoiceShareService.buildInvoicePdfFilename uses customer name and sanitizes invalid chars', () {
    final invNamed = InvoiceModel(
      id: 'fn-1',
      invoiceNumber: 'INV-00777',
      customerName: '  أحمد / علي: محمود  ',
      createdAt: DateTime(2026, 11, 25),
    );
    expect(
      InvoiceShareService.buildInvoicePdfFilename(invNamed),
      'أحمد علي محمود.pdf',
    );

    final invEmpty = invNamed.copyWith(customerName: '   ');
    expect(
      InvoiceShareService.buildInvoicePdfFilename(invEmpty),
      'INV-00777.pdf',
    );
  });

  testWidgets(
    'ReviewScreen item card supports direct quantity input between + and - buttons',
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

      final qtyField = find.byKey(const Key('item_qty_field_scan-1'));
      await tester.scrollUntilVisible(
        qtyField,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(qtyField, findsOneWidget);
      await tester.enterText(qtyField, '10');
      await tester.pumpAndSettle();

      // 10 * 18 ج.م = 180 ج.م
      expect(find.text('180 ج.م'), findsOneWidget);
    },
  );

  testWidgets(
    'Excel import dialog supports direct selling price upload without markup fields',
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

      // Must require selecting Commercial vs Selling before import button enables
      expect(
        find.text('مطلوب تحديد هل الأسعار تجارية أم أسعار بيع قبل الاستيراد'),
        findsOneWidget,
      );

      await tester.ensureVisible(
        find.byKey(const Key('import_price_mode_selling')),
      );
      await tester.tap(find.byKey(const Key('import_price_mode_selling')));
      await tester.pumpAndSettle();

      // Profit and company discount inputs are hidden for direct selling price mode
      expect(find.byKey(const Key('profit_markup_field')), findsNothing);
      expect(find.byKey(const Key('company_discount_toggle')), findsNothing);

      await tester.tap(find.text('استيراد للكتالوج'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('محابس وخلاطات'));
      await tester.pumpAndSettle();

      // Sample row محبس بلي نحاس has price 210 uploaded directly as selling price
      expect(find.text('محبس بلي نحاس'), findsOneWidget);
      expect(find.text('BR: 210 ج.م'), findsWidgets);
      expect(find.textContaining('تجاري 210'), findsNothing);
    },
  );

  test('InvoiceModel payment due/overdue helpers distinguish today vs finished due date', () {
    final refNow = DateTime(2026, 11, 26, 14, 0);
    final dueTodayInv = InvoiceModel(
      id: 'due-today-1',
      invoiceNumber: 'INV-00111',
      status: InvoiceStatus.approved,
      customerName: 'حسن',
      paymentMethod: PaymentMethod.deferredNoDeposit,
      paymentDueDate: DateTime(2026, 11, 26),
      createdAt: DateTime(2026, 11, 20),
      items: const [
        InvoiceItemModel(
          id: 'it-dt',
          itemName: 'ماسورة',
          quantity: 1,
          unitPrice: 300,
        ),
      ],
    );

    expect(dueTodayInv.isPaymentDueToday(refNow), isTrue);
    expect(dueTodayInv.isPaymentOverdue(refNow), isFalse);
    expect(dueTodayInv.overdueDays(refNow), 0);
    expect(
      dueTodayInv.paymentReminderBody('300 ج.م', refNow),
      'المفروض حسن يدفع 300 ج.م النهارده',
    );

    final overdueInv = dueTodayInv.copyWith(
      id: 'overdue-1',
      invoiceNumber: 'INV-00112',
      paymentDueDate: DateTime(2026, 11, 24),
    );
    expect(overdueInv.isPaymentDueToday(refNow), isFalse);
    expect(overdueInv.isPaymentOverdue(refNow), isTrue);
    expect(overdueInv.overdueDays(refNow), 2);
    expect(
      overdueInv.paymentReminderBody('300 ج.م', refNow),
      'المفروض حسن كان يدفع 300 ج.م يوم 2026/11/24 (متأخر 2 يوم)',
    );
  });

  test(
    'SupabaseRepository.isNetworkException detects network failures accurately',
    () {
      expect(
        SupabaseRepository.isNetworkException(
          Exception('SocketException: Failed host lookup'),
        ),
        isTrue,
      );
      expect(
        SupabaseRepository.isNetworkException(
          Exception('ClientException: Failed to fetch'),
        ),
        isTrue,
      );
      expect(
        SupabaseRepository.isNetworkException(TimeoutException('timed out')),
        isTrue,
      );
      expect(
        SupabaseRepository.isNetworkException(StateError('bad state')),
        isFalse,
      );
      expect(
        SupabaseRepository.isNetworkException(
          const AppException('DB constraint error', isNetworkError: false),
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'Header notification bell shows unread badge, opens popover with overdue/today wording, and marks read on click',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MainShell)),
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      container
          .read(invoicesProvider.notifier)
          .saveInvoice(
            InvoiceModel(
              id: 'notif-inv-today',
              invoiceNumber: 'INV-00901',
              status: InvoiceStatus.approved,
              customerName: 'عميل اليوم',
              paymentMethod: PaymentMethod.deferredNoDeposit,
              paymentDueDate: today,
              createdAt: now,
              items: const [
                InvoiceItemModel(
                  id: 'ni-1',
                  itemName: 'كوع',
                  quantity: 1,
                  unitPrice: 500,
                ),
              ],
            ),
          );
      container
          .read(invoicesProvider.notifier)
          .saveInvoice(
            InvoiceModel(
              id: 'notif-inv-overdue',
              invoiceNumber: 'INV-00902',
              status: InvoiceStatus.approved,
              customerName: 'عميل متأخر',
              paymentMethod: PaymentMethod.deferredNoDeposit,
              paymentDueDate: twoDaysAgo,
              createdAt: now,
              items: const [
                InvoiceItemModel(
                  id: 'ni-2',
                  itemName: 'ماسورة',
                  quantity: 1,
                  unitPrice: 1000,
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('header_notifications_button')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('header_notifications_button')));
      await tester.pumpAndSettle();

      final popover = find.byKey(const Key('notifications_popover'));
      expect(popover, findsOneWidget);
      expect(
        find.descendant(
          of: popover,
          matching: find.textContaining(
            'المفروض عميل متأخر كان يدفع 1,000 ج.م يوم ${InvoiceModel.formatDisplayDate(twoDaysAgo)}',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: popover,
          matching: find.textContaining(
            'المفروض عميل اليوم يدفع 500 ج.م النهارده',
          ),
        ),
        findsOneWidget,
      );

      // Tap overdue notification: navigates to /review and marks it read
      await tester.tap(
        find.byKey(const Key('notification_item_notif-inv-overdue')),
      );
      await tester.pumpAndSettle();

      expect(find.text('مراجعة INV-00902'), findsOneWidget);

      await tester.tap(find.byType(BackButton).last);
      await tester.pumpAndSettle();

      // Only 1 unread notification remains on the badge
      expect(
        find.descendant(
          of: find.byKey(const Key('notifications_badge')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Approved invoice with remaining balance shows partial/full collection actions instead of approve and updates DB state',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(MainShell)),
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final twoDaysAgo = today.subtract(const Duration(days: 2));

      container
          .read(invoicesProvider.notifier)
          .saveInvoice(
            InvoiceModel(
              id: 'collect-inv-1',
              invoiceNumber: 'INV-00950',
              status: InvoiceStatus.approved,
              customerName: 'عميل التحصيل',
              paymentMethod: PaymentMethod.deferredNoDeposit,
              paymentDueDate: twoDaysAgo,
              createdAt: now,
              items: const [
                InvoiceItemModel(
                  id: 'ci-1',
                  itemName: 'محبس دفن',
                  quantity: 1,
                  unitPrice: 1000,
                ),
              ],
            ),
          );
      await tester.pumpAndSettle();

      // Open the overdue invoice from the header notifications popover
      await tester.tap(find.byKey(const Key('header_notifications_button')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('notification_item_collect-inv-1')),
      );
      await tester.pumpAndSettle();

      // Shows collection buttons instead of quote-approval button
      expect(
        find.byKey(const Key('partial_collection_button')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('full_collection_button')), findsOneWidget);
      expect(find.text('حفظ عرض سعر'), findsNothing);
      expect(find.textContaining('اعتماد ('), findsNothing);

      // Test partial collection: pay 400 now and reschedule rest
      await tester.tap(find.byKey(const Key('partial_collection_button')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('partial_collection_dialog')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('collect_now_amount_field')),
        '400',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('600 ج.م'), findsWidgets);

      await tester.tap(find.byKey(const Key('collect_next_due_date_picker')));
      await tester.pumpAndSettle();
      final pickerEl = tester.element(find.byType(DatePickerDialog));
      final okLabel = MaterialLocalizations.of(pickerEl).okButtonLabel;
      await tester.tap(find.text(okLabel).last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_partial_collection_btn')));
      await tester.pumpAndSettle();

      // Close share dialog via "حفظ فقط"
      await tester.tap(find.byKey(const Key('approved_save_only_btn')));
      await tester.pumpAndSettle();

      final afterPartial = container
          .read(invoicesProvider)
          .firstWhere((i) => i.id == 'collect-inv-1');
      expect(afterPartial.effectivePaidAmount, 400);
      expect(afterPartial.remainingAmount, 600);
      expect(afterPartial.paymentMethod, PaymentMethod.partialNowRestLater);

      // Now test full collection of remaining 600
      await tester.tap(find.byKey(const Key('full_collection_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('approved_save_only_btn')));
      await tester.pumpAndSettle();

      final afterFull = container
          .read(invoicesProvider)
          .firstWhere((i) => i.id == 'collect-inv-1');
      expect(afterFull.paymentMethod, PaymentMethod.cash);
      expect(afterFull.effectivePaidAmount, 1000);
      expect(afterFull.remainingAmount, 0);
      expect(afterFull.isPaymentDueOrOverdue, isFalse);
    },
  );

  test('ScanService.computePipePricing divides 6m drainage pipes and 4m feeding pipes accurately', () {
    // 1. Drainage pipe (مواسير, catalog unit عود = 6m, price 600) requested in متر => 100/m
    final drainagePerMeter = ScanService.computePipePricing(
      templateUnit: 'عود',
      requestedUnit: 'متر',
      rawOcrText: '2 متر ماسورة 4 وايتكس',
      categoryName: 'مواسير',
      itemName: 'ماسورة',
      basePrice: 600,
    );
    expect(drainagePerMeter.unit, 'متر');
    expect(drainagePerMeter.unitPrice, 100.0);

    // 2. Feeding pipe (تغذية (بولي), catalog unit عود = 4m, price 200) requested in متر => 50/m
    final feedingPerMeter = ScanService.computePipePricing(
      templateUnit: 'عود',
      requestedUnit: 'متر',
      rawOcrText: '2 متر ماسورة بولي',
      categoryName: 'تغذية (بولي)',
      itemName: 'ماسورة',
      basePrice: 200,
    );
    expect(feedingPerMeter.unit, 'متر');
    expect(feedingPerMeter.unitPrice, 50.0);

    // 3. Feeding pipe already priced per متر (64) stays 64 when requested in متر
    final alreadyPerMeter = ScanService.computePipePricing(
      templateUnit: 'متر',
      requestedUnit: 'متر',
      rawOcrText: '10 متر ماسورة 3/4',
      categoryName: 'تغذية (بولي)',
      itemName: 'ماسورة عادي PIN20',
      basePrice: 64,
    );
    expect(alreadyPerMeter.unit, 'متر');
    expect(alreadyPerMeter.unitPrice, 64.0);

    // 4. Feeding pipe priced per متر (64) converted to عود (4m) => 256
    final feedingPerStick = ScanService.computePipePricing(
      templateUnit: 'متر',
      requestedUnit: 'عود',
      rawOcrText: 'عود ماسورة 3/4',
      categoryName: 'تغذية (بولي)',
      itemName: 'ماسورة عادي PIN20',
      basePrice: 64,
    );
    expect(feedingPerStick.unit, 'عود');
    expect(feedingPerStick.unitPrice, 256.0);
  });

  testWidgets(
    'Editing an item in ReviewScreen opens smart same-category & similar list and applies selected item price/data',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      // Open Demo AI Scan -> ReviewScreen
      await tester.tap(find.text('تسعير ورقة جديدة (AI)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('تجربة كشف تجريبي جاهز (AI Demo)'));
      await tester.pumpAndSettle();

      // Tap edit button on the first item
      final editBtn = find.byIcon(Icons.edit_outlined).first;
      await tester.ensureVisible(editBtn);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      // Tap the item name selector inside the edit dialog
      expect(find.byKey(const Key('edit_item_name_selector')), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit_item_name_selector')));
      await tester.pumpAndSettle();

      // Smart filter chip ("الأقرب و...") and search field are shown
      expect(find.byKey(const Key('picker_filter_smart')), findsOneWidget);
      expect(
        find.byKey(const Key('smart_catalog_search_field')),
        findsOneWidget,
      );

      // Pick a different item from the same category (e.g. محبس دفن 3/4 بوصة)
      await tester.enterText(
        find.byKey(const Key('smart_catalog_search_field')),
        'محبس دفن',
      );
      await tester.pumpAndSettle();

      final targetOption = find.textContaining('محبس دفن').first;
      await tester.tap(targetOption);
      await tester.pumpAndSettle();

      // Verify price inside edit dialog updated to the selected item's price (> 0)
      final priceField = tester.widget<TextField>(
        find.byKey(const Key('edit_item_price_field')),
      );
      expect(double.tryParse(priceField.controller!.text) ?? 0, greaterThan(0));

      // Apply changes and verify item updated on ReviewScreen
      await tester.tap(find.byKey(const Key('edit_item_apply_btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('محبس دفن'), findsWidgets);
    },
  );

  testWidgets(
    'System back from non-home tab returns to Home, and first back on Home prompts to press again to exit',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: SanitaryPricingApp(enableRemoteFonts: false),
        ),
      );
      await tester.pumpAndSettle();

      // Switch to Catalog tab
      await tester.tap(find.text('الأصناف'));
      await tester.pumpAndSettle();
      expect(find.text('شجرة الأصناف والأسعار'), findsOneWidget);

      // Press system back -> should return to Home tab (index 0)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('تسعير ورقة جديدة (AI)'), findsOneWidget);

      // Press system back once on Home -> should show double-back exit SnackBar
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('اضغط رجوع مرة أخرى للخروج من التطبيق'), findsOneWidget);
    },
  );

  testWidgets(
    'ReviewScreen confidence filter tabs, quick confirm checkmark, and disabled approve until all items confirmed',
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

      // Approve button must be disabled initially because Demo scan has unconfirmed items
      final approveBtnBefore = tester.widget<ElevatedButton>(
        find.byKey(const Key('review_approve_button')),
      );
      expect(approveBtnBefore.onPressed, isNull);
      expect(find.textContaining('يحتاج تأكيد قبل الاعتماد'), findsOneWidget);

      // Filter tabs for all 3 statuses exist
      expect(find.byKey(const Key('review_filter_all')), findsOneWidget);
      expect(find.byKey(const Key('review_filter_high')), findsOneWidget);
      expect(find.byKey(const Key('review_filter_medium')), findsOneWidget);
      expect(find.byKey(const Key('review_filter_low')), findsOneWidget);

      // Switch to medium filter, confirm item via checkmark
      await tester.ensureVisible(find.byKey(const Key('review_filter_medium')));
      await tester.tap(find.byKey(const Key('review_filter_medium')));
      await tester.pumpAndSettle();
      while (find.byIcon(Icons.check_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.check_rounded).first);
        await tester.pumpAndSettle();
      }

      // Switch to low filter, confirm item via checkmark
      await tester.tap(find.byKey(const Key('review_filter_low')));
      await tester.pumpAndSettle();
      while (find.byIcon(Icons.check_rounded).evaluate().isNotEmpty) {
        await tester.tap(find.byIcon(Icons.check_rounded).first);
        await tester.pumpAndSettle();
      }

      // Now all items are confirmed -> Approve button must be enabled!
      final approveBtnAfter = tester.widget<ElevatedButton>(
        find.byKey(const Key('review_approve_button')),
      );
      expect(approveBtnAfter.onPressed, isNotNull);
      expect(find.textContaining('يحتاج تأكيد قبل الاعتماد'), findsNothing);
    },
  );
}
