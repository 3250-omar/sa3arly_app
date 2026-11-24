enum ProfitMarkupType {
  percent('نسبة مئوية %'),
  fixed('مبلغ ثابت (ج.م)');

  const ProfitMarkupType(this.arabicLabel);
  final String arabicLabel;
}

double calculateSellingPrice(
  double commercialPrice,
  ProfitMarkupType type,
  double value,
) {
  final raw = switch (type) {
    ProfitMarkupType.percent => commercialPrice * (1 + value / 100.0),
    ProfitMarkupType.fixed => commercialPrice + value,
  };
  return (raw * 100).round() / 100.0;
}

double calculateDiscountedCommercialPrice(
  double listPrice,
  double discountPercent,
) {
  final clamped = discountPercent.clamp(0.0, 100.0);
  final raw = listPrice * (1 - clamped / 100.0);
  return (raw * 100).round() / 100.0;
}

enum BrandTier {
  economy('شعبي / اقتصادي', 'economy'),
  mid('متوسط', 'mid'),
  premium('ممتاز', 'premium');

  const BrandTier(this.arabicLabel, this.dbValue);
  final String arabicLabel;
  final String dbValue;

  static BrandTier fromString(String? value) {
    switch (value) {
      case 'economy':
        return BrandTier.economy;
      case 'premium':
        return BrandTier.premium;
      default:
        return BrandTier.mid;
    }
  }
}

class CategoryModel {
  const CategoryModel({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int sortOrder;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
      };

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
}

class BrandModel {
  const BrandModel({
    required this.id,
    required this.name,
    required this.tier,
    this.isDefault = false,
  });

  final String id;
  final String name;
  final BrandTier tier;
  final bool isDefault;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'tier': tier.dbValue,
        'is_default': isDefault,
      };

  factory BrandModel.fromJson(Map<String, dynamic> json) {
    return BrandModel(
      id: json['id'] as String,
      name: json['name'] as String,
      tier: BrandTier.fromString(json['tier'] as String?),
      isDefault: json['is_default'] as bool? ?? false,
    );
  }
}

class ItemTemplateModel {
  const ItemTemplateModel({
    required this.id,
    required this.categoryId,
    required this.name,
    this.size,
    this.unit = 'قطعة',
    this.description,
  });

  final String id;
  final String categoryId;
  final String name;
  final String? size;
  final String unit;
  final String? description;

  String get displayLabel =>
      size != null && size!.trim().isNotEmpty ? '$name - $size' : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category_id': categoryId,
        'name': name,
        'size': size,
        'unit': unit,
        'description': description,
      };

  factory ItemTemplateModel.fromJson(Map<String, dynamic> json) {
    return ItemTemplateModel(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      size: json['size'] as String?,
      unit: (json['unit'] as String?) ?? 'قطعة',
      description: json['description'] as String?,
    );
  }
}

class ProductVariantModel {
  const ProductVariantModel({
    required this.id,
    required this.itemTemplateId,
    required this.brandId,
    required this.price,
    this.commercialPrice,
    this.costPrice,
    this.isAvailable = true,
  });

  final String id;
  final String itemTemplateId;
  final String brandId;
  final double price;
  final double? commercialPrice;
  final double? costPrice;
  final bool isAvailable;

  ProductVariantModel copyWith({
    double? price,
    double? commercialPrice,
    bool clearCommercialPrice = false,
    double? costPrice,
    bool? isAvailable,
  }) {
    return ProductVariantModel(
      id: id,
      itemTemplateId: itemTemplateId,
      brandId: brandId,
      price: price ?? this.price,
      commercialPrice:
          clearCommercialPrice ? null : (commercialPrice ?? this.commercialPrice),
      costPrice: costPrice ?? this.costPrice,
      isAvailable: isAvailable ?? this.isAvailable,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_template_id': itemTemplateId,
        'brand_id': brandId,
        'price': price,
        'commercial_price': commercialPrice,
        'cost_price': costPrice ?? commercialPrice,
        'is_available': isAvailable,
      };

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) {
    final commercial = (json['commercial_price'] as num?)?.toDouble() ??
        (json['cost_price'] as num?)?.toDouble();
    return ProductVariantModel(
      id: json['id'] as String,
      itemTemplateId: json['item_template_id'] as String,
      brandId: json['brand_id'] as String,
      price: (json['price'] as num).toDouble(),
      commercialPrice: commercial,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? commercial,
      isAvailable: json['is_available'] as bool? ?? true,
    );
  }
}

class ItemAliasModel {
  const ItemAliasModel({
    required this.id,
    required this.aliasText,
    required this.itemTemplateId,
  });

  final String id;
  final String aliasText;
  final String itemTemplateId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'alias_text': aliasText,
        'item_template_id': itemTemplateId,
      };

  factory ItemAliasModel.fromJson(Map<String, dynamic> json) {
    return ItemAliasModel(
      id: json['id'] as String,
      aliasText: json['alias_text'] as String,
      itemTemplateId: json['item_template_id'] as String,
    );
  }
}

class ShopSettingsModel {
  const ShopSettingsModel({
    this.id,
    required this.shopName,
    required this.phone,
    required this.address,
    this.defaultBrandId,
  });

  final String? id;
  final String shopName;
  final String phone;
  final String address;
  final String? defaultBrandId;

  ShopSettingsModel copyWith({
    String? id,
    String? shopName,
    String? phone,
    String? address,
    String? defaultBrandId,
  }) {
    return ShopSettingsModel(
      id: id ?? this.id,
      shopName: shopName ?? this.shopName,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      defaultBrandId: defaultBrandId ?? this.defaultBrandId,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'shop_name': shopName,
        'phone': phone,
        'address': address,
        'default_brand_id': defaultBrandId,
      };

  factory ShopSettingsModel.fromJson(Map<String, dynamic> json) {
    return ShopSettingsModel(
      id: json['id'] as String?,
      shopName: (json['shop_name'] as String?) ?? 'محل الأدوات الصحية',
      phone: (json['phone'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      defaultBrandId: json['default_brand_id'] as String?,
    );
  }
}
