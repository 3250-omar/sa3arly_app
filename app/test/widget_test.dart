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
}
