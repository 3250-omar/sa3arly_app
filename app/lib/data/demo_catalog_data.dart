import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';

class DemoCatalogData {
  const DemoCatalogData._();

  static const String catSupply = '11111111-1111-1111-1111-111111111101';
  static const String catDrain = '11111111-1111-1111-1111-111111111102';
  static const String catValves = '11111111-1111-1111-1111-111111111103';
  static const String catAccessories = '11111111-1111-1111-1111-111111111104';

  static const String brandElSherif = '22222222-2222-2222-2222-222222222201';
  static const String brandBR = '22222222-2222-2222-2222-222222222202';
  static const String brandAquatherm = '22222222-2222-2222-2222-222222222203';
  static const String brandShaabi = '22222222-2222-2222-2222-222222222204';

  static const ShopSettingsModel defaultSettings = ShopSettingsModel(
    shopName: 'أولاد النيل للأدوات الصحية',
    phone: '01001234567',
    address: 'القاهرة - شارع الجمهورية',
    defaultBrandId: brandElSherif,
  );

  static const List<CategoryModel> categories = [
    CategoryModel(id: catSupply, name: 'تغذية (بولي)', sortOrder: 1),
    CategoryModel(id: catDrain, name: 'صرف', sortOrder: 2),
    CategoryModel(id: catValves, name: 'محابس وخلاطات', sortOrder: 3),
    CategoryModel(id: catAccessories, name: 'إكسسوارات ولوازم', sortOrder: 4),
  ];

  static const List<BrandModel> brands = [
    BrandModel(
      id: brandElSherif,
      name: 'الشريف',
      tier: BrandTier.premium,
      isDefault: true,
    ),
    BrandModel(id: brandBR, name: 'BR', tier: BrandTier.mid),
    BrandModel(
      id: brandAquatherm,
      name: 'أكواثيرم',
      tier: BrandTier.premium,
    ),
    BrandModel(id: brandShaabi, name: 'شعبي', tier: BrandTier.economy),
  ];

  static const List<ItemTemplateModel> templates = [
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333301',
      categoryId: catSupply,
      name: 'كوع لحام',
      size: '1/2 بوصة',
      description: 'كوع بولي 90 درجة لحام',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333302',
      categoryId: catSupply,
      name: 'كوع لحام',
      size: '3/4 بوصة',
      description: 'كوع بولي 90 درجة لحام',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333303',
      categoryId: catSupply,
      name: 'كوع بسن داخلي',
      size: '1/2 بوصة',
      description: 'كوع نحاس بسن داخلي',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333304',
      categoryId: catSupply,
      name: 'كوع بسن خارجي',
      size: '1/2 بوصة',
      description: 'كوع نحاس بسن خارجي',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333305',
      categoryId: catSupply,
      name: 'تيه لحام',
      size: '1/2 بوصة',
      description: 'مشترك بولي لحام',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333306',
      categoryId: catSupply,
      name: 'تيه لحام',
      size: '3/4 بوصة',
      description: 'مشترك بولي لحام',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333307',
      categoryId: catSupply,
      name: 'تيه بسن داخلي',
      size: '1/2 بوصة',
      description: 'مشترك بسن نحاس داخلي',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333308',
      categoryId: catSupply,
      name: 'جلبة لحام',
      size: '1/2 بوصة',
      description: 'جلبة وصل بولي',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333309',
      categoryId: catSupply,
      name: 'ماسورة بولي 4 متر',
      size: '1/2 بوصة',
      unit: 'عود',
      description: 'ماسورة تغذية ضغط 20 بار',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333310',
      categoryId: catSupply,
      name: 'ماسورة بولي 4 متر',
      size: '3/4 بوصة',
      unit: 'عود',
      description: 'ماسورة تغذية ضغط 20 بار',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333311',
      categoryId: catSupply,
      name: 'نبل بولي بسن',
      size: '1/2 بوصة',
      description: 'نبل توصيل بسن نحاس',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333312',
      categoryId: catDrain,
      name: 'ماسورة صرف 4 متر',
      size: '4 بوصة',
      unit: 'عود',
      description: 'ماسورة صرف PVC',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333313',
      categoryId: catDrain,
      name: 'كوع صرف 45',
      size: '4 بوصة',
      description: 'كوع صرف مفتوح بجوان',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333314',
      categoryId: catDrain,
      name: 'كوع صرف 90',
      size: '2 بوصة',
      description: 'كوع صرف 2 بوصة',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333315',
      categoryId: catDrain,
      name: 'سيفون أرضية (بيبة)',
      size: '4 بوصة',
      description: 'بيبة صرف أرضية متعددة المخارج',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333316',
      categoryId: catValves,
      name: 'محبس دفن',
      size: '1/2 بوصة',
      description: 'محبس دفن قلب نحاس',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333317',
      categoryId: catValves,
      name: 'محبس زاوية',
      size: '1/2 بوصة',
      description: 'محبس زاوية نيكل كروم',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333318',
      categoryId: catValves,
      name: 'خلاط مطبخ شجرة',
      size: 'قياسي',
      description: 'خلاط حوض مطبخ نحاس',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333319',
      categoryId: catAccessories,
      name: 'شريط تفلون',
      size: 'كبير',
      unit: 'بكرة',
      description: 'بكرة تفلون مانع تسريب',
    ),
    ItemTemplateModel(
      id: '33333333-3333-3333-3333-333333333320',
      categoryId: catAccessories,
      name: 'كولة صرف',
      size: '250 جرام',
      unit: 'علبة',
      description: 'لاصق مواسير PVC',
    ),
  ];

  static final List<ProductVariantModel> variants = [
    // كوع لحام 1/2
    _v('v01', '33333333-3333-3333-3333-333333333301', brandElSherif, 18, 14),
    _v('v02', '33333333-3333-3333-3333-333333333301', brandBR, 14, 10.5),
    _v('v03', '33333333-3333-3333-3333-333333333301', brandAquatherm, 26, 20),
    _v('v04', '33333333-3333-3333-3333-333333333301', brandShaabi, 9, 6.5),
    // كوع لحام 3/4
    _v('v05', '33333333-3333-3333-3333-333333333302', brandElSherif, 24, 19),
    _v('v06', '33333333-3333-3333-3333-333333333302', brandBR, 19, 15),
    _v('v07', '33333333-3333-3333-3333-333333333302', brandAquatherm, 34, 27),
    _v('v08', '33333333-3333-3333-3333-333333333302', brandShaabi, 12, 9),
    // كوع بسن داخلي 1/2
    _v('v09', '33333333-3333-3333-3333-333333333303', brandElSherif, 85, 70),
    _v('v10', '33333333-3333-3333-3333-333333333303', brandBR, 68, 54),
    _v('v11', '33333333-3333-3333-3333-333333333303', brandAquatherm, 115, 95),
    _v('v12', '33333333-3333-3333-3333-333333333303', brandShaabi, 45, 35),
    // كوع بسن خارجي 1/2
    _v('v13', '33333333-3333-3333-3333-333333333304', brandElSherif, 90, 74),
    _v('v14', '33333333-3333-3333-3333-333333333304', brandBR, 72, 58),
    _v('v15', '33333333-3333-3333-3333-333333333304', brandShaabi, 48, 38),
    // تيه لحام 1/2
    _v('v16', '33333333-3333-3333-3333-333333333305', brandElSherif, 22, 17),
    _v('v17', '33333333-3333-3333-3333-333333333305', brandBR, 17, 13),
    _v('v18', '33333333-3333-3333-3333-333333333305', brandAquatherm, 32, 25),
    _v('v19', '33333333-3333-3333-3333-333333333305', brandShaabi, 11, 8),
    // تيه لحام 3/4
    _v('v20', '33333333-3333-3333-3333-333333333306', brandElSherif, 30, 24),
    _v('v21', '33333333-3333-3333-3333-333333333306', brandBR, 23, 18),
    _v('v22', '33333333-3333-3333-3333-333333333306', brandShaabi, 15, 11),
    // تيه بسن داخلي 1/2
    _v('v23', '33333333-3333-3333-3333-333333333307', brandElSherif, 95, 78),
    _v('v24', '33333333-3333-3333-3333-333333333307', brandBR, 75, 60),
    _v('v25', '33333333-3333-3333-3333-333333333307', brandShaabi, 52, 40),
    // جلبة لحام 1/2
    _v('v26', '33333333-3333-3333-3333-333333333308', brandElSherif, 14, 10),
    _v('v27', '33333333-3333-3333-3333-333333333308', brandBR, 11, 8),
    _v('v28', '33333333-3333-3333-3333-333333333308', brandAquatherm, 21, 16),
    _v('v29', '33333333-3333-3333-3333-333333333308', brandShaabi, 7, 5),
    // ماسورة بولي 1/2
    _v('v30', '33333333-3333-3333-3333-333333333309', brandElSherif, 240, 200),
    _v('v31', '33333333-3333-3333-3333-333333333309', brandBR, 195, 160),
    _v('v32', '33333333-3333-3333-3333-333333333309', brandAquatherm, 360, 310),
    _v('v33', '33333333-3333-3333-3333-333333333309', brandShaabi, 140, 115),
    // ماسورة بولي 3/4
    _v('v34', '33333333-3333-3333-3333-333333333310', brandElSherif, 320, 270),
    _v('v35', '33333333-3333-3333-3333-333333333310', brandBR, 260, 215),
    _v('v36', '33333333-3333-3333-3333-333333333310', brandAquatherm, 470, 405),
    _v('v37', '33333333-3333-3333-3333-333333333310', brandShaabi, 185, 150),
    // نبل بولي 1/2
    _v('v38', '33333333-3333-3333-3333-333333333311', brandElSherif, 65, 52),
    _v('v39', '33333333-3333-3333-3333-333333333311', brandBR, 52, 41),
    // ماسورة صرف 4 بوصة
    _v('v40', '33333333-3333-3333-3333-333333333312', brandElSherif, 520, 445),
    _v('v41', '33333333-3333-3333-3333-333333333312', brandBR, 430, 365),
    _v('v42', '33333333-3333-3333-3333-333333333312', brandShaabi, 310, 260),
    // كوع صرف 45 - 4 بوصة
    _v('v43', '33333333-3333-3333-3333-333333333313', brandElSherif, 75, 60),
    _v('v44', '33333333-3333-3333-3333-333333333313', brandBR, 60, 48),
    _v('v45', '33333333-3333-3333-3333-333333333313', brandShaabi, 38, 29),
    // كوع صرف 90 - 2 بوصة
    _v('v46', '33333333-3333-3333-3333-333333333314', brandElSherif, 42, 33),
    _v('v47', '33333333-3333-3333-3333-333333333314', brandBR, 34, 27),
    _v('v48', '33333333-3333-3333-3333-333333333314', brandShaabi, 22, 17),
    // بيبة
    _v('v49', '33333333-3333-3333-3333-333333333315', brandElSherif, 180, 145),
    _v('v50', '33333333-3333-3333-3333-333333333315', brandBR, 145, 115),
    _v('v51', '33333333-3333-3333-3333-333333333315', brandShaabi, 90, 70),
    // محبس دفن 1/2
    _v('v52', '33333333-3333-3333-3333-333333333316', brandElSherif, 260, 215),
    _v('v53', '33333333-3333-3333-3333-333333333316', brandBR, 210, 170),
    _v('v54', '33333333-3333-3333-3333-333333333316', brandAquatherm, 390, 330),
    _v('v55', '33333333-3333-3333-3333-333333333316', brandShaabi, 135, 105),
    // محبس زاوية
    _v('v56', '33333333-3333-3333-3333-333333333317', brandElSherif, 145, 115),
    _v('v57', '33333333-3333-3333-3333-333333333317', brandBR, 115, 90),
    _v('v58', '33333333-3333-3333-3333-333333333317', brandShaabi, 70, 52),
    // خلاط مطبخ
    _v('v59', '33333333-3333-3333-3333-333333333318', brandElSherif, 1250, 1020),
    _v('v60', '33333333-3333-3333-3333-333333333318', brandBR, 950, 780),
    _v('v61', '33333333-3333-3333-3333-333333333318', brandShaabi, 620, 490),
    // شريط تفلون
    _v('v62', '33333333-3333-3333-3333-333333333319', brandElSherif, 25, 18),
    _v('v63', '33333333-3333-3333-3333-333333333319', brandBR, 20, 14),
    _v('v64', '33333333-3333-3333-3333-333333333319', brandShaabi, 12, 8),
    // كولة صرف
    _v('v65', '33333333-3333-3333-3333-333333333320', brandElSherif, 110, 88),
    _v('v66', '33333333-3333-3333-3333-333333333320', brandBR, 90, 72),
    _v('v67', '33333333-3333-3333-3333-333333333320', brandShaabi, 65, 50),
  ];

  static ProductVariantModel _v(
    String id,
    String templateId,
    String brandId,
    double price,
    double costPrice,
  ) {
    return ProductVariantModel(
      id: id,
      itemTemplateId: templateId,
      brandId: brandId,
      price: price,
      costPrice: costPrice,
    );
  }

  static const List<ItemAliasModel> aliases = [
    ItemAliasModel(
      id: 'a1',
      aliasText: 'كوع نص',
      itemTemplateId: '33333333-3333-3333-3333-333333333301',
    ),
    ItemAliasModel(
      id: 'a2',
      aliasText: 'كوع نص سن',
      itemTemplateId: '33333333-3333-3333-3333-333333333303',
    ),
    ItemAliasModel(
      id: 'a3',
      aliasText: 'مشترك نص',
      itemTemplateId: '33333333-3333-3333-3333-333333333305',
    ),
    ItemAliasModel(
      id: 'a4',
      aliasText: 'تفلون',
      itemTemplateId: '33333333-3333-3333-3333-333333333319',
    ),
    ItemAliasModel(
      id: 'a5',
      aliasText: 'بيبة',
      itemTemplateId: '33333333-3333-3333-3333-333333333315',
    ),
  ];

  static List<InvoiceModel> initialInvoices() {
    final now = DateTime.now();
    return [
      InvoiceModel(
        id: 'inv-1001',
        invoiceNumber: 'INV-00001',
        status: InvoiceStatus.approved,
        brandId: brandElSherif,
        brandName: 'الشريف',
        customerName: 'أحمد محمود',
        customerPhone: '01012345678',
        // technicianName omitted intentionally to show it is hidden when empty
        createdByName: 'عمر (المالك)',
        createdAt: now.subtract(const Duration(hours: 3)),
        items: const [
          InvoiceItemModel(
            id: 'ii-1',
            sortOrder: 0,
            rawOcrText: '10 كوع لحام نص',
            itemTemplateId: '33333333-3333-3333-3333-333333333301',
            brandId: brandElSherif,
            brandName: 'الشريف',
            itemName: 'كوع لحام',
            size: '1/2 بوصة',
            quantity: 10,
            unitPrice: 18,
          ),
          InvoiceItemModel(
            id: 'ii-2',
            sortOrder: 1,
            rawOcrText: '3 عود ماسورة نص',
            itemTemplateId: '33333333-3333-3333-3333-333333333309',
            brandId: brandElSherif,
            brandName: 'الشريف',
            itemName: 'ماسورة بولي 4 متر',
            size: '1/2 بوصة',
            unit: 'عود',
            quantity: 3,
            unitPrice: 240,
          ),
          InvoiceItemModel(
            id: 'ii-3',
            sortOrder: 2,
            rawOcrText: '2 محبس دفن نص',
            itemTemplateId: '33333333-3333-3333-3333-333333333316',
            brandId: brandElSherif,
            brandName: 'الشريف',
            itemName: 'محبس دفن',
            size: '1/2 بوصة',
            quantity: 2,
            unitPrice: 260,
          ),
        ],
      ),
      InvoiceModel(
        id: 'inv-1002',
        invoiceNumber: 'INV-00002',
        status: InvoiceStatus.quote,
        comparisonGroupId: 'cmp-group-1',
        brandId: brandElSherif,
        brandName: 'الشريف',
        customerName: 'كريم عبد الله',
        customerPhone: '01122334455',
        technicianName: 'الأسطى حسن',
        createdByName: 'محمد (بائع)',
        createdAt: now.subtract(const Duration(days: 1)),
        items: const [
          InvoiceItemModel(
            id: 'ii-4',
            sortOrder: 0,
            itemTemplateId: '33333333-3333-3333-3333-333333333305',
            brandId: brandElSherif,
            brandName: 'الشريف',
            itemName: 'تيه لحام',
            size: '1/2 بوصة',
            quantity: 8,
            unitPrice: 22,
          ),
          InvoiceItemModel(
            id: 'ii-5',
            sortOrder: 1,
            itemTemplateId: '33333333-3333-3333-3333-333333333312',
            brandId: brandElSherif,
            brandName: 'الشريف',
            itemName: 'ماسورة صرف 4 متر',
            size: '4 بوصة',
            unit: 'عود',
            quantity: 4,
            unitPrice: 520,
          ),
        ],
      ),
      InvoiceModel(
        id: 'inv-1003',
        invoiceNumber: 'INV-00003',
        status: InvoiceStatus.quote,
        comparisonGroupId: 'cmp-group-1',
        brandId: brandBR,
        brandName: 'BR',
        customerName: 'كريم عبد الله',
        customerPhone: '01122334455',
        technicianName: 'الأسطى حسن',
        createdByName: 'محمد (بائع)',
        createdAt: now.subtract(const Duration(days: 1)),
        items: const [
          InvoiceItemModel(
            id: 'ii-6',
            sortOrder: 0,
            itemTemplateId: '33333333-3333-3333-3333-333333333305',
            brandId: brandBR,
            brandName: 'BR',
            itemName: 'تيه لحام',
            size: '1/2 بوصة',
            quantity: 8,
            unitPrice: 17,
          ),
          InvoiceItemModel(
            id: 'ii-7',
            sortOrder: 1,
            itemTemplateId: '33333333-3333-3333-3333-333333333312',
            brandId: brandBR,
            brandName: 'BR',
            itemName: 'ماسورة صرف 4 متر',
            size: '4 بوصة',
            unit: 'عود',
            quantity: 4,
            unitPrice: 430,
          ),
        ],
      ),
    ];
  }

  /// Simulates an AI OCR response on a typical handwritten Egyptian plumbing paper.
  static InvoiceModel createDemoScannedDraft(int nextNumber) {
    final numStr = 'INV-${nextNumber.toString().padLeft(5, '0')}';
    return InvoiceModel(
      id: 'draft-${DateTime.now().millisecondsSinceEpoch}',
      invoiceNumber: numStr,
      status: InvoiceStatus.quote,
      brandId: brandElSherif,
      brandName: 'الشريف',
      customerName: 'عميل جديد',
      createdAt: DateTime.now(),
      items: const [
        InvoiceItemModel(
          id: 'scan-1',
          sortOrder: 0,
          rawOcrText: '١٥ كوع نص لحام',
          itemTemplateId: '33333333-3333-3333-3333-333333333301',
          brandId: brandElSherif,
          brandName: 'الشريف',
          itemName: 'كوع لحام',
          size: '1/2 بوصة',
          quantity: 15,
          unitPrice: 18,
          confidence: OcrConfidence.high,
        ),
        InvoiceItemModel(
          id: 'scan-2',
          sortOrder: 1,
          rawOcrText: '٦ تيه نص بسن',
          itemTemplateId: '33333333-3333-3333-3333-333333333307',
          brandId: brandElSherif,
          brandName: 'الشريف',
          itemName: 'تيه بسن داخلي',
          size: '1/2 بوصة',
          quantity: 6,
          unitPrice: 95,
          confidence: OcrConfidence.high,
        ),
        InvoiceItemModel(
          id: 'scan-3',
          sortOrder: 2,
          rawOcrText: '٤ عود ماسورة بولي ٣/٤',
          itemTemplateId: '33333333-3333-3333-3333-333333333310',
          brandId: brandElSherif,
          brandName: 'الشريف',
          itemName: 'ماسورة بولي 4 متر',
          size: '3/4 بوصة',
          unit: 'عود',
          quantity: 4,
          unitPrice: 320,
          confidence: OcrConfidence.high,
        ),
        InvoiceItemModel(
          id: 'scan-4',
          sortOrder: 3,
          rawOcrText: '٢ محبس دفن',
          itemTemplateId: '33333333-3333-3333-3333-333333333316',
          brandId: brandElSherif,
          brandName: 'الشريف',
          itemName: 'محبس دفن',
          size: '1/2 بوصة',
          quantity: 2,
          unitPrice: 260,
          confidence: OcrConfidence.medium,
          notes: 'المقاس غير مكتوب — تم افتراض 1/2 بوصة',
        ),
        InvoiceItemModel(
          id: 'scan-5',
          sortOrder: 4,
          rawOcrText: '٣ قلب خلاط سيراميك',
          itemTemplateId: null,
          brandId: null,
          brandName: 'غير محدد',
          itemName: 'قلب خلاط سيراميك',
          quantity: 3,
          unitPrice: 0,
          confidence: OcrConfidence.low,
          notes: 'غير موجود في الكتالوج — أدخل السعر أو اربطه بصنف',
        ),
      ],
    );
  }
}
