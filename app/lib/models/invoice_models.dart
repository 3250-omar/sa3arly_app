import 'dart:typed_data';

enum InvoiceStatus {
  quote('عرض سعر', 'quote'),
  approved('فاتورة معتمدة', 'approved');

  const InvoiceStatus(this.arabicLabel, this.dbValue);
  final String arabicLabel;
  final String dbValue;

  static InvoiceStatus fromString(String? value) {
    return value == 'approved' ? InvoiceStatus.approved : InvoiceStatus.quote;
  }
}

enum DiscountType {
  none('بدون خصم', 'none'),
  fixed('مبلغ ثابت', 'fixed'),
  percent('نسبة مئوية %', 'percent');

  const DiscountType(this.arabicLabel, this.dbValue);
  final String arabicLabel;
  final String dbValue;

  static DiscountType fromString(String? value) {
    switch (value) {
      case 'fixed':
        return DiscountType.fixed;
      case 'percent':
        return DiscountType.percent;
      default:
        return DiscountType.none;
    }
  }
}

enum OcrConfidence {
  high('مؤكد', 'high'),
  medium('محتاج مراجعة', 'medium'),
  low('غير متطابق', 'low');

  const OcrConfidence(this.arabicLabel, this.dbValue);
  final String arabicLabel;
  final String dbValue;

  static OcrConfidence fromString(String? value) {
    switch (value) {
      case 'high':
        return OcrConfidence.high;
      case 'low':
        return OcrConfidence.low;
      default:
        return OcrConfidence.medium;
    }
  }
}

class InvoiceItemModel {
  const InvoiceItemModel({
    required this.id,
    this.sortOrder = 0,
    this.rawOcrText,
    this.itemTemplateId,
    this.brandId,
    this.productVariantId,
    required this.itemName,
    this.size,
    this.brandName,
    this.unit = 'قطعة',
    required this.quantity,
    required this.unitPrice,
    this.confidence = OcrConfidence.high,
    this.notes,
  });

  final String id;
  final int sortOrder;
  final String? rawOcrText;
  final String? itemTemplateId;
  final String? brandId;
  final String? productVariantId;
  final String itemName;
  final String? size;
  final String? brandName;
  final String unit;
  final double quantity;
  final double unitPrice;
  final OcrConfidence confidence;
  final String? notes;

  double get lineTotal => quantity * unitPrice;

  String get displayName =>
      size != null && size!.trim().isNotEmpty ? '$itemName ($size)' : itemName;

  InvoiceItemModel copyWith({
    String? id,
    int? sortOrder,
    String? rawOcrText,
    String? itemTemplateId,
    String? brandId,
    String? productVariantId,
    String? itemName,
    String? size,
    String? brandName,
    String? unit,
    double? quantity,
    double? unitPrice,
    OcrConfidence? confidence,
    String? notes,
    bool clearNotes = false,
  }) {
    return InvoiceItemModel(
      id: id ?? this.id,
      sortOrder: sortOrder ?? this.sortOrder,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      itemTemplateId: itemTemplateId ?? this.itemTemplateId,
      brandId: brandId ?? this.brandId,
      productVariantId: productVariantId ?? this.productVariantId,
      itemName: itemName ?? this.itemName,
      size: size ?? this.size,
      brandName: brandName ?? this.brandName,
      unit: unit ?? this.unit,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      confidence: confidence ?? this.confidence,
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  Map<String, dynamic> toJson({String? invoiceId}) => {
        'id': id,
        'invoice_id': ?invoiceId,
        'sort_order': sortOrder,
        'raw_ocr_text': rawOcrText,
        'item_template_id': itemTemplateId,
        'brand_id': brandId,
        'product_variant_id': productVariantId,
        'item_name': itemName,
        'size': size,
        'brand_name': brandName,
        'unit': unit,
        'quantity': quantity,
        'unit_price': unitPrice,
        'line_total': lineTotal,
        'confidence': confidence.dbValue,
      };

  factory InvoiceItemModel.fromJson(Map<String, dynamic> json) {
    return InvoiceItemModel(
      id: json['id'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      rawOcrText: json['raw_ocr_text'] as String?,
      itemTemplateId: json['item_template_id'] as String?,
      brandId: json['brand_id'] as String?,
      productVariantId: json['product_variant_id'] as String?,
      itemName: (json['item_name'] as String?) ?? 'صنف',
      size: json['size'] as String?,
      brandName: json['brand_name'] as String?,
      unit: (json['unit'] as String?) ?? 'قطعة',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      confidence: OcrConfidence.fromString(json['confidence'] as String?),
      notes: json['notes'] as String?,
    );
  }
}

class InvoiceModel {
  const InvoiceModel({
    required this.id,
    required this.invoiceNumber,
    this.status = InvoiceStatus.quote,
    this.comparisonGroupId,
    this.brandId,
    this.brandName,
    this.customerName = '',
    this.customerPhone,
    this.technicianName,
    this.discountType = DiscountType.none,
    this.discountValue = 0,
    this.notes,
    this.imagePaths = const [],
    this.localScanImages = const [],
    this.createdByName = 'أحمد (المدير)',
    required this.createdAt,
    this.items = const [],
  });

  final String id;
  final String invoiceNumber;
  final InvoiceStatus status;
  final String? comparisonGroupId;
  final String? brandId;
  final String? brandName;
  final String customerName;
  final String? customerPhone;

  /// Optional technician name. Hidden from invoice UI and PDF when null or blank.
  final String? technicianName;
  final DiscountType discountType;
  final double discountValue;
  final String? notes;
  final List<String> imagePaths;

  /// Transient in-memory scan bytes used for zoomable paper review & Storage upload.
  final List<Uint8List> localScanImages;
  final String createdByName;
  final DateTime createdAt;
  final List<InvoiceItemModel> items;

  bool get hasTechnician =>
      technicianName != null && technicianName!.trim().isNotEmpty;

  List<String> get distinctBrandNames {
    final seen = <String>{};
    final result = <String>[];
    for (final item in items) {
      final name = item.brandName?.trim();
      if (name != null && name.isNotEmpty && name != 'غير محدد') {
        if (seen.add(name)) {
          result.add(name);
        }
      }
    }
    if (result.isEmpty) {
      final top = brandName?.trim();
      if (top != null && top.isNotEmpty && top != 'غير محدد') {
        result.add(top);
      }
    }
    return result;
  }

  String? get brandSummary {
    final names = distinctBrandNames;
    if (names.isEmpty) return null;
    if (names.length == 1) return names.first;
    return '${names.first} +${names.length - 1}';
  }

  double get subtotal =>
      items.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get discountAmount {
    if (discountType == DiscountType.fixed) {
      return discountValue.clamp(0.0, subtotal);
    }
    if (discountType == DiscountType.percent) {
      return subtotal * (discountValue.clamp(0.0, 100.0) / 100.0);
    }
    return 0.0;
  }

  double get total => (subtotal - discountAmount).clamp(0.0, double.infinity);

  InvoiceModel copyWith({
    String? id,
    String? invoiceNumber,
    InvoiceStatus? status,
    String? comparisonGroupId,
    String? brandId,
    String? brandName,
    String? customerName,
    String? customerPhone,
    String? technicianName,
    DiscountType? discountType,
    double? discountValue,
    String? notes,
    List<String>? imagePaths,
    List<Uint8List>? localScanImages,
    String? createdByName,
    DateTime? createdAt,
    List<InvoiceItemModel>? items,
  }) {
    return InvoiceModel(
      id: id ?? this.id,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      status: status ?? this.status,
      comparisonGroupId: comparisonGroupId ?? this.comparisonGroupId,
      brandId: brandId ?? this.brandId,
      brandName: brandName ?? this.brandName,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      technicianName: technicianName ?? this.technicianName,
      discountType: discountType ?? this.discountType,
      discountValue: discountValue ?? this.discountValue,
      notes: notes ?? this.notes,
      imagePaths: imagePaths ?? this.imagePaths,
      localScanImages: localScanImages ?? this.localScanImages,
      createdByName: createdByName ?? this.createdByName,
      createdAt: createdAt ?? this.createdAt,
      items: items ?? this.items,
    );
  }

  Map<String, dynamic> toDbRow() => {
        'id': id,
        'invoice_number': invoiceNumber,
        'status': status.dbValue,
        'comparison_group_id': comparisonGroupId,
        'brand_id': brandId,
        'customer_name': customerName,
        'customer_phone':
            (customerPhone ?? '').trim().isEmpty ? null : customerPhone!.trim(),
        'technician_name':
            hasTechnician ? technicianName!.trim() : null,
        'discount_type': discountType.dbValue,
        'discount_value': discountValue,
        'subtotal': subtotal,
        'total': total,
        'notes': notes,
        'image_paths': imagePaths,
      };

  Map<String, dynamic> toCacheJson() => {
        ...toDbRow(),
        'brand_name': brandName,
        'created_by_name': createdByName,
        'created_at': createdAt.toIso8601String(),
        'invoice_items': [
          for (var i = 0; i < items.length; i++)
            items[i].copyWith(sortOrder: i).toJson(invoiceId: id),
        ],
      };

  factory InvoiceModel.fromJson(
    Map<String, dynamic> json, {
    String? resolvedBrandName,
  }) {
    final rawItems = (json['invoice_items'] as List?) ?? const [];
    final parsedItems = rawItems
        .map((e) => InvoiceItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    final brandRel = json['brands'];
    final brandNameFromRel =
        brandRel is Map ? (brandRel['name'] as String?) : null;
    final profileRel = json['profiles'];
    final creatorFromRel =
        profileRel is Map ? (profileRel['full_name'] as String?) : null;

    return InvoiceModel(
      id: json['id'] as String,
      invoiceNumber: (json['invoice_number'] as String?) ?? 'INV-00001',
      status: InvoiceStatus.fromString(json['status'] as String?),
      comparisonGroupId: json['comparison_group_id'] as String?,
      brandId: json['brand_id'] as String?,
      brandName: resolvedBrandName ??
          brandNameFromRel ??
          (json['brand_name'] as String?),
      customerName: (json['customer_name'] as String?) ?? '',
      customerPhone: json['customer_phone'] as String?,
      technicianName: json['technician_name'] as String?,
      discountType: DiscountType.fromString(json['discount_type'] as String?),
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      imagePaths: ((json['image_paths'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      createdByName: creatorFromRel ??
          (json['created_by_name'] as String?) ??
          'موظف المحل',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      items: parsedItems,
    );
  }
}
