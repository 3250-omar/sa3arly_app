import 'dart:convert';

import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CachedCatalogSnapshot {
  const CachedCatalogSnapshot({
    required this.categories,
    required this.brands,
    required this.templates,
    required this.variants,
    required this.aliases,
    required this.shopSettings,
    this.lastSyncedAt,
  });

  final List<CategoryModel> categories;
  final List<BrandModel> brands;
  final List<ItemTemplateModel> templates;
  final List<ProductVariantModel> variants;
  final List<ItemAliasModel> aliases;
  final ShopSettingsModel shopSettings;
  final DateTime? lastSyncedAt;
}

class LocalCacheService {
  LocalCacheService._();

  static const _kCatalogKey = 'cached_catalog_v1';
  static const _kInvoicesKey = 'cached_invoices_v1';
  static const _kPendingInvoiceIdsKey = 'pending_invoice_ids_v1';
  static const _kPendingAliasesKey = 'pending_aliases_v1';
  static const _kReadNotificationIdsKey = 'read_notification_ids_v1';
  static const _kDeliveredDeviceNotificationsKey =
      'delivered_device_notifications_v1';

  static Future<void> saveCatalogSnapshot({
    required List<CategoryModel> categories,
    required List<BrandModel> brands,
    required List<ItemTemplateModel> templates,
    required List<ProductVariantModel> variants,
    required List<ItemAliasModel> aliases,
    required ShopSettingsModel shopSettings,
    DateTime? syncedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'categories': [for (final c in categories) c.toJson()],
      'brands': [for (final b in brands) b.toJson()],
      'templates': [for (final t in templates) t.toJson()],
      'variants': [for (final v in variants) v.toJson()],
      'aliases': [for (final a in aliases) a.toJson()],
      'shop_settings': shopSettings.toJson(),
      if (syncedAt != null) 'last_synced_at': syncedAt.toIso8601String(),
    };
    await prefs.setString(_kCatalogKey, jsonEncode(payload));
  }

  static Future<CachedCatalogSnapshot?> loadCatalogSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCatalogKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return CachedCatalogSnapshot(
        categories: ((decoded['categories'] as List?) ?? const [])
            .map((e) => CategoryModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        brands: ((decoded['brands'] as List?) ?? const [])
            .map((e) => BrandModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        templates: ((decoded['templates'] as List?) ?? const [])
            .map((e) =>
                ItemTemplateModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        variants: ((decoded['variants'] as List?) ?? const [])
            .map((e) =>
                ProductVariantModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        aliases: ((decoded['aliases'] as List?) ?? const [])
            .map((e) => ItemAliasModel.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        shopSettings: decoded['shop_settings'] is Map
            ? ShopSettingsModel.fromJson(
                Map<String, dynamic>.from(decoded['shop_settings'] as Map),
              )
            : const ShopSettingsModel(
                shopName: 'محل الأدوات الصحية',
                phone: '',
                address: '',
              ),
        lastSyncedAt: decoded['last_synced_at'] != null
            ? DateTime.tryParse(decoded['last_synced_at'].toString())
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveInvoices(List<InvoiceModel> invoices) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode([for (final inv in invoices) inv.toCacheJson()]);
    await prefs.setString(_kInvoicesKey, encoded);
  }

  static Future<List<InvoiceModel>?> loadInvoices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kInvoicesKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => InvoiceModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<Set<String>> loadPendingInvoiceIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kPendingInvoiceIdsKey) ?? const [];
    return list.toSet();
  }

  static Future<void> markInvoicePending(String invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_kPendingInvoiceIdsKey) ?? const []).toSet()
      ..add(invoiceId);
    await prefs.setStringList(_kPendingInvoiceIdsKey, ids.toList());
  }

  static Future<void> clearInvoicePending(String invoiceId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_kPendingInvoiceIdsKey) ?? const []).toSet()
      ..remove(invoiceId);
    await prefs.setStringList(_kPendingInvoiceIdsKey, ids.toList());
  }

  static Future<void> queuePendingAlias({
    required String aliasText,
    required String itemTemplateId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadPendingAliases();
    final exists = current.any(
      (a) => a['alias_text']?.toLowerCase() == aliasText.trim().toLowerCase(),
    );
    if (exists) return;
    current.add({
      'alias_text': aliasText.trim(),
      'item_template_id': itemTemplateId,
    });
    await prefs.setString(_kPendingAliasesKey, jsonEncode(current));
  }

  static Future<List<Map<String, String>>> loadPendingAliases() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPendingAliasesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Map<String, String>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearPendingAliases() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingAliasesKey);
  }

  static Future<Set<String>> loadReadNotificationIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kReadNotificationIdsKey) ?? const [];
    return list.toSet();
  }

  static Future<void> markNotificationRead(String notificationId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids =
        (prefs.getStringList(_kReadNotificationIdsKey) ?? const []).toSet()
          ..add(notificationId);
    await prefs.setStringList(_kReadNotificationIdsKey, ids.toList());
  }

  static Future<void> markAllNotificationsRead(Iterable<String> notificationIds) async {
    final prefs = await SharedPreferences.getInstance();
    final ids =
        (prefs.getStringList(_kReadNotificationIdsKey) ?? const []).toSet()
          ..addAll(notificationIds);
    await prefs.setStringList(_kReadNotificationIdsKey, ids.toList());
  }

  static Future<Set<String>> loadDeliveredDeviceNotificationKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final list =
        prefs.getStringList(_kDeliveredDeviceNotificationsKey) ?? const [];
    return list.toSet();
  }

  static Future<void> markDeviceNotificationDelivered(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        (prefs.getStringList(_kDeliveredDeviceNotificationsKey) ?? const [])
            .toSet()
          ..add(key);
    await prefs.setStringList(_kDeliveredDeviceNotificationsKey, keys.toList());
  }

  static Future<void> clearSessionCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kCatalogKey);
    await prefs.remove(_kInvoicesKey);
    await prefs.remove(_kPendingInvoiceIdsKey);
    await prefs.remove(_kPendingAliasesKey);
    await prefs.remove(_kReadNotificationIdsKey);
    await prefs.remove(_kDeliveredDeviceNotificationsKey);
  }
}
