import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/data/local_cache_service.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/services/catalog_csv_service.dart';
import 'package:uuid/uuid.dart';

class CatalogState {
  const CatalogState({
    required this.categories,
    required this.brands,
    required this.templates,
    required this.variants,
    required this.aliases,
    required this.shopSettings,
    this.searchQuery = '',
    this.selectedCategoryId,
    this.selectedBrandId,
    this.isAdminMode = true,
    this.isSyncing = false,
    this.isOffline = false,
    this.lastSyncedAt,
  });

  final List<CategoryModel> categories;
  final List<BrandModel> brands;
  final List<ItemTemplateModel> templates;
  final List<ProductVariantModel> variants;
  final List<ItemAliasModel> aliases;
  final ShopSettingsModel shopSettings;
  final String searchQuery;
  final String? selectedCategoryId;
  final String? selectedBrandId;
  final bool isAdminMode;
  final bool isSyncing;
  final bool isOffline;
  final DateTime? lastSyncedAt;

  CatalogState copyWith({
    List<CategoryModel>? categories,
    List<BrandModel>? brands,
    List<ItemTemplateModel>? templates,
    List<ProductVariantModel>? variants,
    List<ItemAliasModel>? aliases,
    ShopSettingsModel? shopSettings,
    String? searchQuery,
    String? selectedCategoryId,
    bool clearCategory = false,
    String? selectedBrandId,
    bool clearBrand = false,
    bool? isAdminMode,
    bool? isSyncing,
    bool? isOffline,
    DateTime? lastSyncedAt,
  }) {
    return CatalogState(
      categories: categories ?? this.categories,
      brands: brands ?? this.brands,
      templates: templates ?? this.templates,
      variants: variants ?? this.variants,
      aliases: aliases ?? this.aliases,
      shopSettings: shopSettings ?? this.shopSettings,
      searchQuery: searchQuery ?? this.searchQuery,
      selectedCategoryId: clearCategory
          ? null
          : (selectedCategoryId ?? this.selectedCategoryId),
      selectedBrandId:
          clearBrand ? null : (selectedBrandId ?? this.selectedBrandId),
      isAdminMode: isAdminMode ?? this.isAdminMode,
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }

  BrandModel? findBrand(String? id) {
    if (id == null) return null;
    for (final b in brands) {
      if (b.id == id) return b;
    }
    return null;
  }

  ItemTemplateModel? findTemplate(String? id) {
    if (id == null) return null;
    for (final t in templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  ProductVariantModel? findVariant(String templateId, String brandId) {
    for (final v in variants) {
      if (v.itemTemplateId == templateId &&
          v.brandId == brandId &&
          v.isAvailable) {
        return v;
      }
    }
    return null;
  }

  List<ProductVariantModel> variantsForTemplate(String templateId) {
    return variants
        .where((v) => v.itemTemplateId == templateId && v.isAvailable)
        .toList();
  }

  List<ItemTemplateModel> get filteredTemplates {
    final query = searchQuery.trim().toLowerCase();
    return templates.where((template) {
      if (selectedCategoryId != null &&
          template.categoryId != selectedCategoryId) {
        return false;
      }
      if (selectedBrandId != null &&
          findVariant(template.id, selectedBrandId!) == null) {
        return false;
      }
      if (query.isEmpty) return true;

      final matchesName = template.name.toLowerCase().contains(query);
      final matchesSize =
          (template.size ?? '').toLowerCase().contains(query);
      final matchesAlias = aliases.any(
        (a) =>
            a.itemTemplateId == template.id &&
            a.aliasText.toLowerCase().contains(query),
      );
      return matchesName || matchesSize || matchesAlias;
    }).toList();
  }
}

class CatalogNotifier extends Notifier<CatalogState> {
  static const _uuid = Uuid();
  bool _disposed = false;

  @override
  CatalogState build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final auth = ref.watch(authProvider);
    final isDemo = AppConfig.isDemoMode;

    Future.microtask(() => _bootstrap(auth));

    if (isDemo) {
      return CatalogState(
        categories: DemoCatalogData.categories,
        brands: DemoCatalogData.brands,
        templates: DemoCatalogData.templates,
        variants: DemoCatalogData.variants,
        aliases: DemoCatalogData.aliases,
        shopSettings: DemoCatalogData.defaultSettings,
      );
    }

    return CatalogState(
      categories: const [],
      brands: const [],
      templates: const [],
      variants: const [],
      aliases: const [],
      shopSettings: const ShopSettingsModel(
        shopName: 'محل الأدوات الصحية',
        phone: '',
        address: '',
      ),
      isAdminMode: auth.isAdmin,
    );
  }

  List<CategoryModel> _filterObsoleteCategories(
    List<CategoryModel> categories,
    List<ItemTemplateModel> templates,
  ) {
    final usedIds = {for (final t in templates) t.categoryId};
    return categories
        .where((c) => !(c.name.trim() == 'وصلات صرف' && !usedIds.contains(c.id)))
        .toList();
  }

  Future<void> _bootstrap(AuthState auth) async {
    final cached = await LocalCacheService.loadCatalogSnapshot();
    if (_disposed) return;
    if (cached != null) {
      state = state.copyWith(
        categories: _filterObsoleteCategories(
          cached.categories,
          cached.templates,
        ),
        brands: cached.brands,
        templates: cached.templates,
        variants: cached.variants,
        aliases: cached.aliases,
        shopSettings: cached.shopSettings,
        lastSyncedAt: cached.lastSyncedAt,
      );
    }

    if (!AppConfig.isDemoMode && auth.isAuthenticated && !auth.isLoading) {
      await syncFromSupabase();
    }
  }

  Future<void> syncFromSupabase() async {
    if (AppConfig.isDemoMode || _disposed) return;
    state = state.copyWith(isSyncing: true);
    final repo = SupabaseRepository();

    try {
      // Flush offline learned aliases first
      final pendingAliases = await LocalCacheService.loadPendingAliases();
      for (final a in pendingAliases) {
        final text = a['alias_text'];
        final tplId = a['item_template_id'];
        if (text != null && tplId != null) {
          await repo.upsertAlias(aliasText: text, itemTemplateId: tplId);
        }
      }
      if (pendingAliases.isNotEmpty) {
        await LocalCacheService.clearPendingAliases();
      }

      final bundle = await repo.fetchFullCatalog();
      if (_disposed) return;
      final filteredCategories = _filterObsoleteCategories(
        bundle.categories,
        bundle.templates,
      );
      final syncedAt = DateTime.now();
      state = state.copyWith(
        categories: filteredCategories,
        brands: bundle.brands,
        templates: bundle.templates,
        variants: bundle.variants,
        aliases: bundle.aliases,
        shopSettings: bundle.shopSettings,
        isSyncing: false,
        isOffline: false,
        lastSyncedAt: syncedAt,
      );

      await LocalCacheService.saveCatalogSnapshot(
        categories: filteredCategories,
        brands: bundle.brands,
        templates: bundle.templates,
        variants: bundle.variants,
        aliases: bundle.aliases,
        shopSettings: bundle.shopSettings,
        syncedAt: syncedAt,
      );
    } catch (e) {
      if (_disposed) return;
      final networkErr =
          (e is AppException && e.isNetworkError) ||
          SupabaseRepository.isNetworkException(e);
      state = state.copyWith(isSyncing: false, isOffline: networkErr);
    }
  }

  Future<void> _persistSnapshot() async {
    await LocalCacheService.saveCatalogSnapshot(
      categories: state.categories,
      brands: state.brands,
      templates: state.templates,
      variants: state.variants,
      aliases: state.aliases,
      shopSettings: state.shopSettings,
      syncedAt: state.lastSyncedAt,
    );
  }

  void setSearchQuery(String value) {
    state = state.copyWith(searchQuery: value);
  }

  void setSelectedCategory(String? categoryId) {
    if (categoryId == null) {
      state = state.copyWith(clearCategory: true);
    } else {
      state = state.copyWith(selectedCategoryId: categoryId);
    }
  }

  void setSelectedBrand(String? brandId) {
    if (brandId == null) {
      state = state.copyWith(clearBrand: true);
    } else {
      state = state.copyWith(selectedBrandId: brandId);
    }
  }

  void setAdminMode(bool isAdmin) {
    if (!AppConfig.isDemoMode) return;
    state = state.copyWith(isAdminMode: isAdmin);
  }

  String _normalizeCategoryName(String raw) {
    final trimmed = raw.trim();
    if (trimmed == 'وصلات صرف') return 'صرف';
    return trimmed;
  }

  Future<void> addCategory(String name) async {
    if (!state.isAdminMode) return;
    final clean = _normalizeCategoryName(name);
    if (clean.isEmpty) return;

    final exists = state.categories.any(
      (c) => c.name.trim().toLowerCase() == clean.toLowerCase(),
    );
    if (exists) return;

    final sortOrder = state.categories.length + 1;
    final CategoryModel created;
    if (!AppConfig.isDemoMode) {
      created = await SupabaseRepository()
          .ensureCategory(clean, sortOrder: sortOrder);
    } else {
      created = CategoryModel(
        id: _uuid.v4(),
        name: clean,
        sortOrder: sortOrder,
      );
    }

    state = state.copyWith(categories: [...state.categories, created]);
    await _persistSnapshot();
  }

  Future<void> addBrand({
    required String name,
    BrandTier tier = BrandTier.mid,
  }) async {
    if (!state.isAdminMode) return;
    final clean = name.trim();
    if (clean.isEmpty) return;

    final exists = state.brands.any(
      (b) => b.name.trim().toLowerCase() == clean.toLowerCase(),
    );
    if (exists) return;

    final BrandModel created;
    if (!AppConfig.isDemoMode) {
      created = await SupabaseRepository().ensureBrand(clean, tier: tier);
    } else {
      created = BrandModel(
        id: _uuid.v4(),
        name: clean,
        tier: tier,
      );
    }

    state = state.copyWith(brands: [...state.brands, created]);
    await _persistSnapshot();
  }

  Future<String?> addAlias({
    required String aliasText,
    required String itemTemplateId,
  }) async {
    if (!state.isAdminMode) return 'هذه العملية متاحة للمدير فقط';
    final clean = aliasText.trim();
    if (clean.isEmpty) return 'مطلوب كتابة المسمى الدارج';

    final normalized = clean.toLowerCase();
    final duplicate = state.aliases.any(
      (a) => a.aliasText.trim().toLowerCase() == normalized,
    );
    if (duplicate) return 'هذا المسمى مسجل بالفعل في القاموس';

    try {
      final ItemAliasModel created;
      if (!AppConfig.isDemoMode) {
        created = await SupabaseRepository().addAlias(
          aliasText: clean,
          itemTemplateId: itemTemplateId,
        );
      } else {
        created = ItemAliasModel(
          id: _uuid.v4(),
          aliasText: clean,
          itemTemplateId: itemTemplateId,
        );
      }

      state = state.copyWith(aliases: [created, ...state.aliases]);
      await _persistSnapshot();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر حفظ المسمى في القاموس';
    }
  }

  Future<String?> updateAlias({
    required String aliasId,
    required String aliasText,
    required String itemTemplateId,
  }) async {
    if (!state.isAdminMode) return 'هذه العملية متاحة للمدير فقط';
    final clean = aliasText.trim();
    if (clean.isEmpty) return 'مطلوب كتابة المسمى الدارج';

    final normalized = clean.toLowerCase();
    final duplicate = state.aliases.any(
      (a) => a.id != aliasId && a.aliasText.trim().toLowerCase() == normalized,
    );
    if (duplicate) return 'هذا المسمى مسجل بالفعل في القاموس';

    try {
      if (!AppConfig.isDemoMode) {
        await SupabaseRepository().updateAlias(
          aliasId: aliasId,
          aliasText: clean,
          itemTemplateId: itemTemplateId,
        );
      }

      final updatedList = [
        for (final a in state.aliases)
          if (a.id == aliasId)
            ItemAliasModel(
              id: aliasId,
              aliasText: clean,
              itemTemplateId: itemTemplateId,
            )
          else
            a,
      ];
      state = state.copyWith(aliases: updatedList);
      await _persistSnapshot();
      return null;
    } on AppException catch (e) {
      return e.message;
    } catch (_) {
      return 'تعذر تحديث المسمى في القاموس';
    }
  }

  void deleteAlias(String aliasId) {
    if (!state.isAdminMode) return;
    state = state.copyWith(
      aliases: state.aliases.where((a) => a.id != aliasId).toList(),
    );
    unawaited(_persistSnapshot());
    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository().deleteAlias(aliasId).catchError((_) {}),
      );
    }
  }

  void updateShopSettings(ShopSettingsModel settings) {
    if (!state.isAdminMode) return;
    state = state.copyWith(shopSettings: settings);
    unawaited(_persistSnapshot());
    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository().updateShopSettings(settings).catchError((_) {}),
      );
    }
  }

  void addItemTemplate({
    required String categoryId,
    required String name,
    String? size,
    String unit = 'قطعة',
    required Map<String, double> brandPrices,
  }) {
    if (!state.isAdminMode) return;
    final templateId = _uuid.v4();
    final newTemplate = ItemTemplateModel(
      id: templateId,
      categoryId: categoryId,
      name: name.trim(),
      size: size?.trim().isEmpty == true ? null : size?.trim(),
      unit: unit.trim().isEmpty ? 'قطعة' : unit.trim(),
    );

    final newVariants = <ProductVariantModel>[];
    brandPrices.forEach((brandId, price) {
      if (price >= 0) {
        newVariants.add(
          ProductVariantModel(
            id: _uuid.v4(),
            itemTemplateId: templateId,
            brandId: brandId,
            price: price,
          ),
        );
      }
    });

    state = state.copyWith(
      templates: [newTemplate, ...state.templates],
      variants: [...state.variants, ...newVariants],
    );
    unawaited(_persistSnapshot());

    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository()
            .upsertItemTemplateAndVariants(
              template: newTemplate,
              variants: newVariants,
            )
            .catchError((_) {}),
      );
    }
  }

  void upsertVariantPrice({
    required String itemTemplateId,
    required String brandId,
    required double price,
    double? commercialPrice,
    bool clearCommercialPrice = false,
  }) {
    if (!state.isAdminMode || price < 0) return;
    final existingIdx = state.variants.indexWhere(
      (v) => v.itemTemplateId == itemTemplateId && v.brandId == brandId,
    );

    final updated = [...state.variants];
    late final ProductVariantModel targetVariant;
    if (existingIdx >= 0) {
      targetVariant = updated[existingIdx].copyWith(
        price: price,
        commercialPrice: commercialPrice,
        clearCommercialPrice: clearCommercialPrice,
        costPrice: clearCommercialPrice
            ? null
            : (commercialPrice ?? updated[existingIdx].costPrice),
        isAvailable: true,
      );
      updated[existingIdx] = targetVariant;
    } else {
      targetVariant = ProductVariantModel(
        id: _uuid.v4(),
        itemTemplateId: itemTemplateId,
        brandId: brandId,
        price: price,
        commercialPrice: commercialPrice,
        costPrice: commercialPrice,
      );
      updated.add(targetVariant);
    }
    state = state.copyWith(variants: updated);
    unawaited(_persistSnapshot());

    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository()
            .upsertVariantPrice(targetVariant)
            .catchError((_) {}),
      );
    }
  }

  void learnAlias(String rawText, String itemTemplateId) {
    final normalized = rawText.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final alreadyExists = state.aliases.any(
      (a) => a.aliasText.trim().toLowerCase() == normalized,
    );
    if (alreadyExists) return;

    final newAlias = ItemAliasModel(
      id: _uuid.v4(),
      aliasText: rawText.trim(),
      itemTemplateId: itemTemplateId,
    );
    state = state.copyWith(aliases: [...state.aliases, newAlias]);
    unawaited(_persistSnapshot());

    if (!AppConfig.isDemoMode) {
      unawaited(
        SupabaseRepository()
            .upsertAlias(
              aliasText: rawText.trim(),
              itemTemplateId: itemTemplateId,
            )
            .catchError((_) async {
          await LocalCacheService.queuePendingAlias(
            aliasText: rawText.trim(),
            itemTemplateId: itemTemplateId,
          );
        }),
      );
    }
  }

  /// Imports parsed Excel/CSV rows into the Product Tree (and Supabase if online).
  /// When [priceMode] is [ImportPriceMode.selling], [CatalogCsvRow.price] is saved
  /// directly as the selling price without touching `commercialPrice`.
  /// When [priceMode] is [ImportPriceMode.commercial] (default), any
  /// [companyDiscountPercent] > 0 is deducted first to store the commercial price,
  /// and [markupType]/[markupValue] calculates the selling price on top of it.
  Future<int> importCatalogRows(
    List<CatalogCsvRow> rows, {
    ImportPriceMode priceMode = ImportPriceMode.commercial,
    ProfitMarkupType markupType = ProfitMarkupType.percent,
    double markupValue = 0,
    double companyDiscountPercent = 0,
  }) async {
    if (!state.isAdminMode || rows.isEmpty) return 0;
    if (priceMode == ImportPriceMode.commercial &&
        (markupValue < 0 ||
            companyDiscountPercent < 0 ||
            companyDiscountPercent >= 100)) {
      return 0;
    }

    final categories = [...state.categories];
    final brands = [...state.brands];
    final templates = [...state.templates];
    final variants = [...state.variants];
    final repo = AppConfig.isDemoMode ? null : SupabaseRepository();

    var processed = 0;

    for (final row in rows) {
      // 1. Find or create Category
      final categoryName = _normalizeCategoryName(row.categoryName);
      var cat = categories.where(
        (c) => c.name.trim().toLowerCase() == categoryName.toLowerCase(),
      ).firstOrNull;
      if (cat == null) {
        if (repo != null) {
          cat = await repo.ensureCategory(
            categoryName,
            sortOrder: categories.length + 1,
          );
        } else {
          cat = CategoryModel(
            id: _uuid.v4(),
            name: categoryName,
            sortOrder: categories.length + 1,
          );
        }
        categories.add(cat);
      }

      // 2. Find or create Brand
      var brand = brands.where(
        (b) => b.name.trim().toLowerCase() == row.brandName.toLowerCase(),
      ).firstOrNull;
      if (brand == null) {
        if (repo != null) {
          brand = await repo.ensureBrand(row.brandName);
        } else {
          brand = BrandModel(
            id: _uuid.v4(),
            name: row.brandName,
            tier: BrandTier.mid,
          );
        }
        brands.add(brand);
      }

      // 3. Find or create ItemTemplate
      var template = templates.where((t) {
        final sameCat = t.categoryId == cat!.id;
        final sameName = t.name.trim().toLowerCase() == row.itemName.toLowerCase();
        final sameSize =
            (t.size ?? '').trim().toLowerCase() == (row.size ?? '').toLowerCase();
        return sameCat && sameName && sameSize;
      }).firstOrNull;

      var createdTemplate = false;
      if (template == null) {
        template = ItemTemplateModel(
          id: _uuid.v4(),
          categoryId: cat.id,
          name: row.itemName,
          size: row.size,
          unit: row.unit,
        );
        templates.insert(0, template);
        createdTemplate = true;
      }

      // 4. Upsert Variant commercial & selling prices
      final existingIdx = variants.indexWhere(
        (v) => v.itemTemplateId == template!.id && v.brandId == brand!.id,
      );
      late final ProductVariantModel variant;
      if (priceMode == ImportPriceMode.selling) {
        final sellingPrice = row.price;
        if (existingIdx >= 0) {
          variant = variants[existingIdx].copyWith(
            price: sellingPrice,
            isAvailable: true,
          );
          variants[existingIdx] = variant;
        } else {
          variant = ProductVariantModel(
            id: _uuid.v4(),
            itemTemplateId: template.id,
            brandId: brand.id,
            price: sellingPrice,
          );
          variants.add(variant);
        }
      } else {
        final commercialPrice = companyDiscountPercent > 0
            ? calculateDiscountedCommercialPrice(
                row.price,
                companyDiscountPercent,
              )
            : row.price;
        final sellingPrice =
            calculateSellingPrice(commercialPrice, markupType, markupValue);
        if (existingIdx >= 0) {
          variant = variants[existingIdx].copyWith(
            price: sellingPrice,
            commercialPrice: commercialPrice,
            costPrice: commercialPrice,
            isAvailable: true,
          );
          variants[existingIdx] = variant;
        } else {
          variant = ProductVariantModel(
            id: _uuid.v4(),
            itemTemplateId: template.id,
            brandId: brand.id,
            price: sellingPrice,
            commercialPrice: commercialPrice,
            costPrice: commercialPrice,
          );
          variants.add(variant);
        }
      }

      if (repo != null) {
        if (createdTemplate) {
          await repo.upsertItemTemplateAndVariants(
            template: template,
            variants: [variant],
          );
        } else {
          await repo.upsertVariantPrice(variant);
        }
      }

      processed++;
    }

    state = state.copyWith(
      categories: categories,
      brands: brands,
      templates: templates,
      variants: variants,
    );
    await _persistSnapshot();
    return processed;
  }

  /// Recalculates selling prices from stored [ProductVariantModel.commercialPrice]
  /// for variants matching the optional [brandId] and [categoryId] filters.
  Future<int> applyProfitMarkup({
    required ProfitMarkupType markupType,
    required double markupValue,
    String? brandId,
    String? categoryId,
  }) async {
    if (!state.isAdminMode || markupValue < 0) return 0;

    final allowedTemplateIds = categoryId == null
        ? null
        : {
            for (final t in state.templates)
              if (t.categoryId == categoryId) t.id,
          };

    final updatedVariants = <ProductVariantModel>[];
    final changedVariants = <ProductVariantModel>[];

    for (final v in state.variants) {
      final matchesBrand = brandId == null || v.brandId == brandId;
      final matchesCategory =
          allowedTemplateIds == null ||
          allowedTemplateIds.contains(v.itemTemplateId);

      if (v.commercialPrice != null && matchesBrand && matchesCategory) {
        final newSellingPrice = calculateSellingPrice(
          v.commercialPrice!,
          markupType,
          markupValue,
        );
        final updated = v.copyWith(price: newSellingPrice);
        updatedVariants.add(updated);
        changedVariants.add(updated);
      } else {
        updatedVariants.add(v);
      }
    }

    if (changedVariants.isEmpty) return 0;

    if (!AppConfig.isDemoMode) {
      await SupabaseRepository().upsertVariantsBatch(changedVariants);
    }

    state = state.copyWith(variants: updatedVariants);
    await _persistSnapshot();
    return changedVariants.length;
  }
}

final catalogProvider = NotifierProvider<CatalogNotifier, CatalogState>(
  CatalogNotifier.new,
);
