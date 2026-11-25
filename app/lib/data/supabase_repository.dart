import 'dart:typed_data';

import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AppException implements Exception {
  const AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.isActive,
  });

  final String id;
  final String fullName;
  final String role;
  final bool isActive;

  bool get isAdmin => role == 'admin' && isActive;
}

class RemoteCatalogBundle {
  const RemoteCatalogBundle({
    required this.categories,
    required this.brands,
    required this.templates,
    required this.variants,
    required this.aliases,
    required this.shopSettings,
  });

  final List<CategoryModel> categories;
  final List<BrandModel> brands;
  final List<ItemTemplateModel> templates;
  final List<ProductVariantModel> variants;
  final List<ItemAliasModel> aliases;
  final ShopSettingsModel shopSettings;
}

class SupabaseRepository {
  SupabaseRepository({SupabaseClient? client})
      : _clientOverride = client;

  final SupabaseClient? _clientOverride;
  static const _uuid = Uuid();
  static const int maxUploadBytes = 5 * 1024 * 1024;
  static const int maxScanImages = 5;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  Future<UserProfile?> fetchCurrentProfile() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    try {
      final data = await _client
          .from('profiles')
          .select('id, full_name, role, is_active')
          .eq('id', user.id)
          .maybeSingle();
      if (data == null) return null;
      return UserProfile(
        id: data['id'] as String,
        fullName: (data['full_name'] as String?) ?? 'مستخدم',
        role: (data['role'] as String?) ?? 'staff',
        isActive: data['is_active'] as bool? ?? false,
      );
    } catch (_) {
      throw const AppException('تعذر التحقق من صلاحيات الحساب حالياً.');
    }
  }

  Future<RemoteCatalogBundle> fetchFullCatalog() async {
    try {
      final results = await Future.wait<dynamic>([
        _client.from('categories').select().order('sort_order', ascending: true),
        _client.from('brands').select().order('name', ascending: true),
        _client.from('item_templates').select().order('name', ascending: true),
        _client.from('product_variants').select(),
        _client.from('item_aliases').select(),
        _client.from('shop_settings').select().limit(1),
      ]);

      final categories = (results[0] as List)
          .map((e) => CategoryModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final brands = (results[1] as List)
          .map((e) => BrandModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final templates = (results[2] as List)
          .map((e) =>
              ItemTemplateModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final variants = (results[3] as List)
          .map((e) =>
              ProductVariantModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final aliases = (results[4] as List)
          .map((e) => ItemAliasModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      final settingsRows = results[5] as List;
      final shopSettings = settingsRows.isNotEmpty
          ? ShopSettingsModel.fromJson(
              Map<String, dynamic>.from(settingsRows.first as Map),
            )
          : const ShopSettingsModel(
              shopName: 'محل الأدوات الصحية',
              phone: '',
              address: '',
            );

      return RemoteCatalogBundle(
        categories: categories,
        brands: brands,
        templates: templates,
        variants: variants,
        aliases: aliases,
        shopSettings: shopSettings,
      );
    } catch (_) {
      throw const AppException('تعذر مزامنة شجرة الأصناف والأسعار.');
    }
  }

  Future<CategoryModel> ensureCategory(String name, {int sortOrder = 10}) async {
    try {
      final row = await _client
          .from('categories')
          .upsert({'name': name.trim(), 'sort_order': sortOrder},
              onConflict: 'name')
          .select()
          .single();
      return CategoryModel.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      throw const AppException('تعذر حفظ القسم في قاعدة البيانات.');
    }
  }

  Future<BrandModel> ensureBrand(
    String name, {
    BrandTier tier = BrandTier.mid,
  }) async {
    try {
      final row = await _client
          .from('brands')
          .upsert({'name': name.trim(), 'tier': tier.dbValue}, onConflict: 'name')
          .select()
          .single();
      return BrandModel.fromJson(Map<String, dynamic>.from(row));
    } catch (_) {
      throw const AppException('تعذر حفظ الشركة في قاعدة البيانات.');
    }
  }

  Future<void> upsertItemTemplateAndVariants({
    required ItemTemplateModel template,
    required List<ProductVariantModel> variants,
  }) async {
    try {
      await _client.from('item_templates').upsert(template.toJson());
      if (variants.isNotEmpty) {
        await _client.from('product_variants').upsert(
              [for (final v in variants) v.toJson()],
              onConflict: 'item_template_id,brand_id',
            );
      }
    } catch (_) {
      throw const AppException('تعذر حفظ الصنف والأسعار على السيرفر.');
    }
  }

  Future<void> upsertVariantPrice(ProductVariantModel variant) async {
    try {
      await _client.from('product_variants').upsert(
            variant.toJson(),
            onConflict: 'item_template_id,brand_id',
          );
    } catch (_) {
      throw const AppException('تعذر تحديث سعر الصنف.');
    }
  }

  /// Batch-upserts variant prices in chunks to speed up bulk profit recalculation.
  Future<void> upsertVariantsBatch(List<ProductVariantModel> variants) async {
    if (variants.isEmpty) return;
    const chunkSize = 100;
    try {
      for (var i = 0; i < variants.length; i += chunkSize) {
        final end =
            i + chunkSize < variants.length ? i + chunkSize : variants.length;
        final chunk = variants.sublist(i, end);
        await _client.from('product_variants').upsert(
              [for (final v in chunk) v.toJson()],
              onConflict: 'item_template_id,brand_id',
            );
      }
    } catch (_) {
      throw const AppException('تعذر تحديث أسعار الأصناف على السيرفر.');
    }
  }

  Future<void> updateShopSettings(ShopSettingsModel settings) async {
    try {
      final payload = settings.toJson();
      if (settings.id != null) {
        await _client.from('shop_settings').upsert(payload);
      } else {
        await _client.from('shop_settings').insert(payload);
      }
    } catch (_) {
      throw const AppException('تعذر حفظ بيانات المحل.');
    }
  }

  Future<void> upsertAlias({
    required String aliasText,
    required String itemTemplateId,
  }) async {
    try {
      await _client.from('item_aliases').insert({
        'alias_text': aliasText.trim(),
        'item_template_id': itemTemplateId,
      });
    } on PostgrestException catch (e) {
      // Ignore duplicate normalized alias error (23505)
      if (e.code == '23505') return;
      throw const AppException('تعذر حفظ المسمى في القاموس.');
    } catch (_) {
      throw const AppException('تعذر حفظ المسمى في القاموس.');
    }
  }

  Future<ItemAliasModel> addAlias({
    required String aliasText,
    required String itemTemplateId,
  }) async {
    try {
      final row = await _client
          .from('item_aliases')
          .insert({
            'alias_text': aliasText.trim(),
            'item_template_id': itemTemplateId,
          })
          .select()
          .single();
      return ItemAliasModel.fromJson(Map<String, dynamic>.from(row));
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const AppException('هذا المسمى مسجل بالفعل في القاموس.');
      }
      throw const AppException('تعذر حفظ المسمى في القاموس.');
    } catch (_) {
      throw const AppException('تعذر حفظ المسمى في القاموس.');
    }
  }

  Future<void> updateAlias({
    required String aliasId,
    required String aliasText,
    required String itemTemplateId,
  }) async {
    try {
      await _client.from('item_aliases').update({
        'alias_text': aliasText.trim(),
        'item_template_id': itemTemplateId,
      }).eq('id', aliasId);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const AppException('هذا المسمى مسجل بالفعل في القاموس.');
      }
      throw const AppException('تعذر تحديث المسمى في القاموس.');
    } catch (_) {
      throw const AppException('تعذر تحديث المسمى في القاموس.');
    }
  }

  Future<void> deleteAlias(String aliasId) async {
    try {
      await _client.from('item_aliases').delete().eq('id', aliasId);
    } catch (_) {
      throw const AppException('تعذر حذف المسمى — متاح للمدير فقط.');
    }
  }

  Future<List<UserProfile>> fetchAllProfiles() async {
    try {
      final rows = await _client
          .from('profiles')
          .select('id, full_name, role, is_active')
          .order('created_at', ascending: true);
      return (rows as List)
          .map((e) => UserProfile(
                id: e['id'] as String,
                fullName: (e['full_name'] as String?) ?? 'مستخدم',
                role: (e['role'] as String?) ?? 'staff',
                isActive: e['is_active'] as bool? ?? true,
              ))
          .toList();
    } catch (_) {
      throw const AppException('تعذر تحميل قائمة الموظفين.');
    }
  }

  Future<void> updateProfile({
    required String id,
    required String role,
    required bool isActive,
  }) async {
    try {
      await _client
          .from('profiles')
          .update({'role': role, 'is_active': isActive}).eq('id', id);
    } catch (_) {
      throw const AppException('تعذر تحديث صلاحيات الموظف.');
    }
  }

  Future<List<InvoiceModel>> fetchInvoices() async {
    try {
      final rows = await _client
          .from('invoices')
          .select('*, brands(name), profiles(full_name), invoice_items(*)')
          .order('created_at', ascending: false);

      return (rows as List)
          .map((e) => InvoiceModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      throw const AppException('تعذر تحميل سجل الفواتير من السيرفر.');
    }
  }

  Future<List<String>> uploadScanImages({
    required String invoiceId,
    required List<Uint8List> images,
  }) async {
    final safeInvoiceId = invoiceId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (safeInvoiceId.isEmpty) {
      throw const AppException('معرّف الفاتورة غير صالح لرفع الصور.');
    }

    final uploadedPaths = <String>[];
    for (final bytes in images.take(maxScanImages)) {
      if (bytes.isEmpty || bytes.length > maxUploadBytes) continue;
      final mime = _detectImageMime(bytes);
      if (mime == null) continue;

      final ext = switch (mime) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
      // Unpredictable UUID filename stored strictly under shop/ prefix for RLS
      final objectPath = 'shop/$safeInvoiceId/${_uuid.v4()}.$ext';
      await _client.storage.from('invoice-scans').uploadBinary(
            objectPath,
            bytes,
            fileOptions: FileOptions(contentType: mime, upsert: false),
          );
      uploadedPaths.add(objectPath);
    }
    return uploadedPaths;
  }

  Future<void> upsertInvoice(InvoiceModel invoice) async {
    try {
      var paths = [...invoice.imagePaths];
      if (invoice.localScanImages.isNotEmpty && paths.isEmpty) {
        paths = await uploadScanImages(
          invoiceId: invoice.id,
          images: invoice.localScanImages,
        );
      }

      final dbPayload = invoice.copyWith(imagePaths: paths).toDbRow();
      await _client.from('invoices').upsert(dbPayload, onConflict: 'id');

      // Replace items cleanly for this invoice
      await _client
          .from('invoice_items')
          .delete()
          .eq('invoice_id', invoice.id);

      if (invoice.items.isNotEmpty) {
        final itemsPayload = [
          for (var i = 0; i < invoice.items.length; i++)
            invoice.items[i].copyWith(sortOrder: i).toJson(invoiceId: invoice.id),
        ];
        await _client.from('invoice_items').insert(itemsPayload);
      }
    } catch (e) {
      if (e is AppException) rethrow;
      throw const AppException('تعذر مزامنة الفاتورة مع السيرفر.');
    }
  }

  Future<void> deleteInvoice(String invoiceId) async {
    try {
      await _client.from('invoices').delete().eq('id', invoiceId);
    } catch (_) {
      throw const AppException('تعذر حذف الفاتورة — هذه العملية متاحة للمدير فقط.');
    }
  }

  static String? _detectImageMime(Uint8List b) {
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
