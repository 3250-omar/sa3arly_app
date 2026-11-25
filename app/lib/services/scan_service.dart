import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
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
      imageQuality: 65,
      maxWidth: 1024,
      maxHeight: 1600,
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
      imageQuality: 65,
      maxWidth: 1024,
      maxHeight: 1600,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxImageBytes) return null;
    return bytes;
  }

  static String toWesternDigits(String value) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    return value.replaceAllMapped(
      RegExp(r'[٠-٩]'),
      (m) => eastern.indexOf(m.group(0)!).toString(),
    );
  }

  static String cleanAliasPhrase(String raw) {
    final normalized = toWesternDigits(raw).trim();
    final stripped = normalized.replaceFirst(
      RegExp(
        r'^\s*\d+(?:[.,]\d+)?(?!\s*\/)\s*(?:[x×*]|قطعه|قطعة|متر|عود|حبه|حبة|عدد)?\s*[-–:]?\s*',
      ),
      '',
    );
    return stripped.trim();
  }

  static String _normalizeBrandText(String value) {
    return toWesternDigits(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'\brak\b'), 'راك')
        .replaceAll('راكثيرم', 'راك ثيرم')
        .replaceAll(RegExp(r'اكواثيرم|اكوا\s*ثيرم|aquatherm'), 'اكواثيرم')
        .replaceAll(RegExp(r'بي\s*ار|بى\s*ار'), 'br')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static BrandModel? detectBrandFromText(
    String? text,
    List<BrandModel> brands,
  ) {
    if (text == null || text.trim().isEmpty || brands.isEmpty) return null;
    final normText = _normalizeBrandText(text);
    if (normText.isEmpty) return null;
    final compactText = normText.replaceAll(' ', '');

    BrandModel? best;
    var bestLen = 0;
    for (final brand in brands) {
      final normBrand = _normalizeBrandText(brand.name);
      if (normBrand.isEmpty) continue;
      final compactBrand = normBrand.replaceAll(' ', '');
      if (normText.contains(normBrand) ||
          compactText.contains(compactBrand) ||
          (compactText.length >= 2 && compactBrand.contains(compactText))) {
        if (compactBrand.length > bestLen) {
          best = brand;
          bestLen = compactBrand.length;
        }
      }
    }
    return best;
  }

  /// Runs AI OCR via Supabase Edge Function when connected, or returns a
  /// realistic Egyptian sanitary ware demo scan when running in Demo Mode.
  static Future<InvoiceModel> analyzePaperImages({
    required List<Uint8List> images,
    required CatalogState catalog,
    required int nextInvoiceSeq,
    String? preferredBrandId,
  }) async {
    final explicitPreferredBrand = catalog.findBrand(preferredBrandId);

    if (AppConfig.isDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return DemoCatalogData.createDemoScannedDraft(nextInvoiceSeq)
          .copyWith(localScanImages: images);
    }

    final encodedImages = images.take(maxImages).map(base64Encode).toList();
    final FunctionResponse response;
    try {
      response = await Supabase.instance.client.functions
          .invoke(
            'scan-invoice',
            body: {
              'images': encodedImages,
              'preferred_brand_id': explicitPreferredBrand?.id,
            },
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const AppException(
        'استغرق تحليل الصورة وقتاً أطول من المتوقع، حاول مرة أخرى.',
      );
    } on FunctionException catch (e) {
      throw AppException(_mapFunctionError(e));
    } catch (_) {
      throw const AppException(
        'تعذر الوصول لسيرفر الذكاء الاصطناعي، تأكد من اتصال الإنترنت.',
      );
    }

    final data = response.data;
    final detectedBrandId =
        data is Map ? data['detected_brand_id'] as String? : null;
    final detectedBrand = catalog.findBrand(detectedBrandId);

    final rawItems = (data is Map && data['items'] is List)
        ? (data['items'] as List)
        : const <dynamic>[];

    final parsedItems = <InvoiceItemModel>[];
    for (var i = 0; i < rawItems.length; i++) {
      final row = Map<String, dynamic>.from(rawItems[i] as Map);
      final templateId = row['item_template_id'] as String?;
      final template = catalog.findTemplate(templateId);
      final rawText = row['raw_ocr_text'] as String?;
      final rawName = row['item_name'] as String?;

      var resolvedBrand =
          detectBrandFromText(rawText, catalog.brands) ??
              detectBrandFromText(rawName, catalog.brands) ??
              catalog.findBrand(row['brand_id'] as String?) ??
              detectedBrand ??
              explicitPreferredBrand;

      var variant = (template != null && resolvedBrand != null)
          ? catalog.findVariant(template.id, resolvedBrand.id)
          : null;

      if (template != null && variant == null && resolvedBrand == null) {
        final available = catalog.variantsForTemplate(template.id);
        if (available.length == 1) {
          variant = available.first;
          resolvedBrand = catalog.findBrand(variant.brandId);
        }
      }

      parsedItems.add(
        InvoiceItemModel(
          id: _uuid.v4(),
          sortOrder: i,
          rawOcrText: rawText,
          itemTemplateId: template?.id,
          brandId: resolvedBrand?.id,
          productVariantId: variant?.id,
          itemName: template?.name ?? (rawName ?? 'صنف'),
          size: template?.size ?? (row['size'] as String?),
          brandName: resolvedBrand?.name,
          unit: template?.unit ?? (row['unit'] as String? ?? 'قطعة'),
          quantity: (row['quantity'] as num?)?.toDouble() ?? 1,
          unitPrice: variant?.price ?? 0,
          confidence: OcrConfidence.fromString(row['confidence'] as String?),
          notes: row['notes'] as String?,
        ),
      );
    }

    final firstWithBrand = parsedItems
        .where((it) => it.brandId != null && it.brandId!.isNotEmpty)
        .firstOrNull;
    final primaryBrandId =
        firstWithBrand?.brandId ?? detectedBrand?.id ?? explicitPreferredBrand?.id;

    final draft = InvoiceModel(
      id: _uuid.v4(),
      invoiceNumber: 'INV-${nextInvoiceSeq.toString().padLeft(5, '0')}',
      status: InvoiceStatus.quote,
      brandId: primaryBrandId,
      brandName:
          firstWithBrand?.brandName ?? detectedBrand?.name ?? explicitPreferredBrand?.name,
      localScanImages: images,
      createdAt: DateTime.now(),
      items: parsedItems,
    );
    return draft.copyWith(brandName: draft.brandSummary ?? draft.brandName);
  }

  static String _mapFunctionError(FunctionException e) {
    final details = e.details;
    final upstreamStatus =
        details is Map ? (details['status'] as num?)?.toInt() : null;
    final effectiveStatus = upstreamStatus ?? e.status;

    if (e.status == 401) {
      return 'انتهت جلسة تسجيل الدخول، سجّل خروج وأعد الدخول مجدداً.';
    }
    if (e.status == 403) {
      return 'هذا الحساب غير مفعّل أو غير مصرح له بتحليل الصور.';
    }
    if (effectiveStatus == 429) {
      return 'تم تجاوز حد الاستخدام أو الرصيد للذكاء الاصطناعي مؤقتاً — تأكد من الرصيد أو حاول بعد دقيقة.';
    }
    if (effectiveStatus == 503) {
      return 'سيرفر الذكاء الاصطناعي عليه ضغط مؤقت الآن، حاول مرة أخرى بعد ثوانٍ.';
    }
    if (effectiveStatus == 400 || effectiveStatus == 401 || effectiveStatus == 403) {
      return 'تعذر قبول الطلب من سيرفر الذكاء الاصطناعي (تأكد من صلاحية مفاتيح الذكاء الاصطناعي في إعدادات السيرفر).';
    }
    if (e.status == 500) {
      return 'إعدادات سيرفر الذكاء الاصطناعي ناقصة (تأكد من إضافة مفاتيح الخدمة في Supabase Secrets).';
    }
    return 'فشل تحليل الصورة عبر الذكاء الاصطناعي (كود: $effectiveStatus).';
  }
}
