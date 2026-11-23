import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ScanService {
  ScanService._();

  static const int maxImages = 5;
  static const int maxImageBytes = 5 * 1024 * 1024;
  static const _uuid = Uuid();
  static final ImagePicker _picker = ImagePicker();

  static Future<List<Uint8List>> pickImagesFromGallery() async {
    final files = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1800,
    );
    final result = <Uint8List>[];
    for (final file in files.take(maxImages)) {
      final bytes = await file.readAsBytes();
      if (bytes.isNotEmpty && bytes.length <= maxImageBytes) {
        result.add(bytes);
      }
    }
    return result;
  }

  static Future<Uint8List?> pickImageFromCamera() async {
    final file = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1800,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxImageBytes) return null;
    return bytes;
  }

  /// Runs AI OCR via Supabase Edge Function when connected, or returns a
  /// realistic Egyptian sanitary ware demo scan when running in Demo Mode.
  static Future<InvoiceModel> analyzePaperImages({
    required List<Uint8List> images,
    required CatalogState catalog,
    required int nextInvoiceSeq,
    String? preferredBrandId,
  }) async {
    final brand = catalog.findBrand(
          preferredBrandId ?? catalog.shopSettings.defaultBrandId,
        ) ??
        catalog.brands.firstOrNull;

    if (AppConfig.isDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return DemoCatalogData.createDemoScannedDraft(nextInvoiceSeq)
          .copyWith(localScanImages: images);
    }

    final encodedImages = images.take(maxImages).map(base64Encode).toList();
    final response = await Supabase.instance.client.functions.invoke(
      'scan-invoice',
      body: {
        'images': encodedImages,
        'preferred_brand_id': brand?.id,
      },
    );

    final data = response.data;
    final rawItems = (data is Map && data['items'] is List)
        ? (data['items'] as List)
        : const <dynamic>[];

    final parsedItems = <InvoiceItemModel>[];
    for (var i = 0; i < rawItems.length; i++) {
      final row = Map<String, dynamic>.from(rawItems[i] as Map);
      final templateId = row['item_template_id'] as String?;
      final rowBrandId = (row['brand_id'] as String?) ?? brand?.id;
      final template = catalog.findTemplate(templateId);
      final resolvedBrand = catalog.findBrand(rowBrandId) ?? brand;
      final variant = (template != null && resolvedBrand != null)
          ? catalog.findVariant(template.id, resolvedBrand.id)
          : null;

      parsedItems.add(
        InvoiceItemModel(
          id: _uuid.v4(),
          sortOrder: i,
          rawOcrText: row['raw_ocr_text'] as String?,
          itemTemplateId: template?.id,
          brandId: variant != null ? resolvedBrand?.id : null,
          productVariantId: variant?.id,
          itemName: template?.name ?? (row['item_name'] as String? ?? 'صنف'),
          size: template?.size ?? (row['size'] as String?),
          brandName: variant != null ? resolvedBrand?.name : 'غير محدد',
          unit: template?.unit ?? (row['unit'] as String? ?? 'قطعة'),
          quantity: (row['quantity'] as num?)?.toDouble() ?? 1,
          unitPrice: variant?.price ?? 0,
          confidence: OcrConfidence.fromString(row['confidence'] as String?),
          notes: row['notes'] as String?,
        ),
      );
    }

    return InvoiceModel(
      id: _uuid.v4(),
      invoiceNumber: 'INV-${nextInvoiceSeq.toString().padLeft(5, '0')}',
      status: InvoiceStatus.quote,
      brandId: brand?.id,
      brandName: brand?.name,
      localScanImages: images,
      createdAt: DateTime.now(),
      items: parsedItems,
    );
  }
}
