import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/features/shell/main_shell.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/providers/notifications_provider.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';
import 'package:sanitary_pricing_app/services/scan_service.dart';
import 'package:uuid/uuid.dart';

class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  static const _uuid = Uuid();

  late final TextEditingController _customerCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _techCtrl;
  late final TextEditingController _discountCtrl;
  late final TextEditingController _paidAmountCtrl;
  late final FocusNode _customerFocusNode;
  String? _loadedDraftId;
  String? _customerNameError;
  String? _paymentError;
  bool _hasUnsavedChanges = false;
  OcrConfidence? _confidenceFilter;

  @override
  void initState() {
    super.initState();
    _customerCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _techCtrl = TextEditingController();
    _discountCtrl = TextEditingController(text: '0');
    _paidAmountCtrl = TextEditingController();
    _customerFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _customerCtrl.dispose();
    _phoneCtrl.dispose();
    _techCtrl.dispose();
    _discountCtrl.dispose();
    _paidAmountCtrl.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  double _parseNumericText(String raw) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    final normalized = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'[٠-٩]'),
          (m) => eastern.indexOf(m.group(0)!).toString(),
        )
        .replaceAll('،', '.')
        .replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }

  void _syncControllersIfNeeded(InvoiceModel draft) {
    if (_loadedDraftId == draft.id) return;
    _loadedDraftId = draft.id;
    _customerCtrl.text = draft.customerName;
    _phoneCtrl.text = draft.customerPhone ?? '';
    _techCtrl.text = draft.technicianName ?? '';
    _discountCtrl.text = draft.discountValue > 0
        ? draft.discountValue.toStringAsFixed(0)
        : '0';
    _paidAmountCtrl.text = draft.paidAmount > 0
        ? (draft.paidAmount == draft.paidAmount.roundToDouble()
            ? draft.paidAmount.toInt().toString()
            : draft.paidAmount.toString())
        : '';
    _paymentError = null;

    final existsInSaved =
        ref.read(invoicesProvider).any((inv) => inv.id == draft.id);
    if (existsInSaved) {
      _hasUnsavedChanges = false;
    } else {
      _hasUnsavedChanges = draft.items.isNotEmpty ||
          draft.localScanImages.isNotEmpty ||
          draft.customerName.trim().isNotEmpty ||
          (draft.customerPhone ?? '').trim().isNotEmpty ||
          (draft.technicianName ?? '').trim().isNotEmpty;
    }
  }

  InvoiceModel _withFormFields(InvoiceModel draft) {
    final techText = _techCtrl.text.trim();
    final phoneText = _phoneCtrl.text.trim();
    final discountVal = _parseNumericText(_discountCtrl.text);
    final paidVal = _parseNumericText(_paidAmountCtrl.text);

    return InvoiceModel(
      id: draft.id,
      invoiceNumber: draft.invoiceNumber,
      status: draft.status,
      comparisonGroupId: draft.comparisonGroupId,
      brandId: draft.brandId,
      brandName: draft.brandName,
      customerName: _customerCtrl.text.trim(),
      customerPhone: phoneText.isEmpty ? null : phoneText,
      technicianName: techText.isEmpty ? null : techText,
      discountType: draft.discountType,
      discountValue: discountVal < 0 ? 0 : discountVal,
      paymentMethod: draft.paymentMethod,
      paidAmount: draft.paymentMethod.requiresPaidNow
          ? (paidVal < 0 ? 0 : paidVal)
          : 0,
      paymentDueDate:
          draft.paymentMethod.requiresDueDate ? draft.paymentDueDate : null,
      notes: draft.notes,
      imagePaths: draft.imagePaths,
      localScanImages: draft.localScanImages,
      createdByName: draft.createdByName,
      createdAt: draft.createdAt,
      items: draft.items,
    );
  }

  InvoiceModel _syncBrandSummary(InvoiceModel draft) {
    final firstWithBrand = draft.items
        .where((it) => it.brandId != null && it.brandId!.isNotEmpty)
        .firstOrNull;
    final nextBrandId = firstWithBrand?.brandId ?? draft.brandId;
    final nextBrandName = draft.brandSummary ?? draft.brandName;
    return InvoiceModel(
      id: draft.id,
      invoiceNumber: draft.invoiceNumber,
      status: draft.status,
      comparisonGroupId: draft.comparisonGroupId,
      brandId: nextBrandId,
      brandName: nextBrandName,
      customerName: draft.customerName,
      customerPhone: draft.customerPhone,
      technicianName: draft.technicianName,
      discountType: draft.discountType,
      discountValue: draft.discountValue,
      paymentMethod: draft.paymentMethod,
      paidAmount: draft.paidAmount,
      paymentDueDate: draft.paymentDueDate,
      notes: draft.notes,
      imagePaths: draft.imagePaths,
      localScanImages: draft.localScanImages,
      createdByName: draft.createdByName,
      createdAt: draft.createdAt,
      items: draft.items,
    );
  }

  void _updateDraft(InvoiceModel updated, {bool markDirty = true}) {
    if (markDirty) {
      _hasUnsavedChanges = true;
    }
    ref.read(activeDraftProvider.notifier).setDraft(updated);
  }

  void _updateItem(InvoiceModel draft, int index, InvoiceItemModel updated) {
    final items = [...draft.items];
    items[index] = updated;
    _updateDraft(_syncBrandSummary(_withFormFields(draft).copyWith(items: items)));
  }

  void _removeItem(InvoiceModel draft, int index) {
    final items = [...draft.items]..removeAt(index);
    _updateDraft(_syncBrandSummary(_withFormFields(draft).copyWith(items: items)));
  }

  Future<void> _showPerItemBrandSheet(
    InvoiceModel draft,
    int index,
    InvoiceItemModel item,
  ) async {
    if (item.itemTemplateId == null) return;
    final catalog = ref.read(catalogProvider);
    final variants = catalog.variantsForTemplate(item.itemTemplateId!);
    if (variants.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أسعار لشركات أخرى لهذا الصنف')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          children: [
            Text(
              'اختر الشركة لهذا البند: ${item.displayName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 10),
            for (final v in variants)
              Builder(
                builder: (context) {
                  final b = catalog.findBrand(v.brandId);
                  final isSelected = item.brandId == v.brandId;
                  return ListTile(
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: AppTheme.primaryColor,
                    ),
                    title: Text(
                      b?.name ?? 'شركة',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      InvoiceShareService.formatCurrency(v.price),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                    onTap: () {
                      _updateItem(
                        draft,
                        index,
                        item.copyWith(
                          brandId: v.brandId,
                          brandName: b?.name,
                          productVariantId: v.id,
                          unitPrice: v.price,
                          confidence: OcrConfidence.high,
                          clearNotes: true,
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomerQuickPickDialog(InvoiceModel draft) async {
    final invoices = ref.read(invoicesProvider);
    final seen = <String, String?>{};
    for (final inv in invoices) {
      final name = inv.customerName.trim();
      if (name.isEmpty || name == 'عميل نقدي' || name == 'عميل جديد') continue;
      seen.putIfAbsent(name, () => inv.customerPhone);
    }

    if (seen.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد عملاء مسجلون سابقاً بعد')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختيار عميل سابق'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in seen.entries)
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(entry.key),
                  subtitle: entry.value != null ? Text(entry.value!) : null,
                  onTap: () {
                    _customerCtrl.text = entry.key;
                    if (entry.value != null) {
                      _phoneCtrl.text = entry.value!;
                    }
                    _updateDraft(_withFormFields(draft));
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTechnicianQuickPickDialog(InvoiceModel draft) async {
    final invoices = ref.read(invoicesProvider);
    final names = <String>{};
    for (final inv in invoices) {
      if (inv.hasTechnician) {
        names.add(inv.technicianName!.trim());
      }
    }

    if (names.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد فنيون مسجلون سابقاً بعد')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختيار فني سابق'),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final tech in names)
                ListTile(
                  leading: const Icon(Icons.engineering_outlined),
                  title: Text(tech),
                  onTap: () {
                    _techCtrl.text = tech;
                    _updateDraft(_withFormFields(draft));
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBrandSwitchSheet(InvoiceModel currentDraft) async {
    final draft = _withFormFields(currentDraft);
    _updateDraft(draft);

    final catalog = ref.read(catalogProvider);
    if (catalog.brands.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد شركات مسجلة في الكتالوج حالياً')),
      );
      return;
    }
    BrandModel selectedBrand = catalog.brands.firstWhere(
      (b) => b.id != draft.brandId,
      orElse: () => catalog.brands.first,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تغيير الشركة أو مقارنة الأسعار',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'الشركة الحالية: ${draft.brandSummary ?? "غير محددة"} — اختر الشركة الجديدة ثم حدد هل تريد استبدال الكشف أم الاحتفاظ بالاتنين للمقارنة:',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final brand in catalog.brands)
                          ChoiceChip(
                            label: Text(
                              '${brand.name} (${brand.tier.arabicLabel})',
                            ),
                            selected: selectedBrand.id == brand.id,
                            onSelected: (_) =>
                                setSheetState(() => selectedBrand = brand),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: () {
                        final switched = ref
                            .read(invoicesProvider.notifier)
                            .applyBrandSwitch(draft, selectedBrand);
                        _updateDraft(switched);
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'تم تبديل أسعار الكشف إلى شركة ${selectedBrand.name}',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.swap_horiz_rounded),
                      label: Text(
                        'تبديل الكشف الحالي إلى ${selectedBrand.name}',
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () {
                        final pair = ref
                            .read(invoicesProvider.notifier)
                            .saveComparisonPair(draft, selectedBrand);
                        _hasUnsavedChanges = false;
                        Navigator.pop(ctx);
                        _showComparisonResultDialog(pair.first, pair.second);
                      },
                      icon: const Icon(Icons.compare_arrows_rounded),
                      label: Text(
                        'الاحتفاظ بالاتنين للمقارنة (${draft.brandSummary ?? "الحالي"} و ${selectedBrand.name})',
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showComparisonResultDialog(
    InvoiceModel first,
    InvoiceModel second,
  ) {
    final shop = ref.read(catalogProvider).shopSettings;
    final diff = (first.total - second.total).abs();
    final cheaper =
        first.total <= second.total ? first.brandSummary : second.brandSummary;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تم حفظ النسختين للمقارنة'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ComparisonCard(
                invoice: first,
                onSelect: () {
                  Navigator.pop(ctx);
                  _updateDraft(first, markDirty: false);
                },
                onWhatsApp: () => InvoiceShareService.shareInvoicePdf(
                  invoice: first,
                  shop: shop,
                ),
              ),
              const SizedBox(height: 10),
              _ComparisonCard(
                invoice: second,
                onSelect: () {
                  Navigator.pop(ctx);
                  _loadedDraftId = null;
                  _updateDraft(second, markDirty: false);
                },
                onWhatsApp: () => InvoiceShareService.shareInvoicePdf(
                  invoice: second,
                  shop: shop,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.highConfidenceBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  diff == 0
                      ? 'الإجمالي متساوٍ بين الشركتين'
                      : 'الفرق: ${InvoiceShareService.formatCurrency(diff)} (${cheaper ?? "الأولى"} أوفر للعميل)',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.highConfidenceColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => InvoiceShareService.shareComparisonPdf(
              groupInvoices: [first, second],
              shop: shop,
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('مشاركة المقارنة PDF'),
          ),
          TextButton.icon(
            onPressed: () => InvoiceShareService.previewOrPrintComparisonPdf(
              groupInvoices: [first, second],
              shop: shop,
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF مقارنة'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('متابعة المراجعة'),
          ),
        ],
      ),
    );
  }

  static String _normalizeSearchAr(String value) {
    return ScanService.toWesternDigits(value)
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static List<String> _searchTokens(String value) {
    return _normalizeSearchAr(value)
        .split(RegExp(r'[\s/\-×*(),]+'))
        .where((w) => w.length >= 2 || w == 't')
        .toList();
  }

  ({
    ItemTemplateModel template,
    ProductVariantModel? variant,
    BrandModel? brand,
    String categoryName,
    String unit,
    double unitPrice,
  }) _resolveCatalogSelection({
    required CatalogState catalog,
    required ItemTemplateModel template,
    String? preferredBrandId,
    String? fallbackBrandId,
    String? currentUnit,
    String? rawOcrText,
  }) {
    final categoryName = catalog.categories
            .where((c) => c.id == template.categoryId)
            .firstOrNull
            ?.name ??
        '';

    BrandModel? resolvedBrand =
        catalog.findBrand(preferredBrandId) ?? catalog.findBrand(fallbackBrandId);
    ProductVariantModel? variant = resolvedBrand != null
        ? catalog.findVariant(template.id, resolvedBrand.id)
        : null;

    if (variant == null &&
        fallbackBrandId != null &&
        fallbackBrandId != preferredBrandId) {
      final fb = catalog.findBrand(fallbackBrandId);
      if (fb != null) {
        final fbVar = catalog.findVariant(template.id, fb.id);
        if (fbVar != null) {
          variant = fbVar;
          resolvedBrand = fb;
        }
      }
    }

    // Brand-pairing fallback: راك (تغذية) <-> وايتكس (صرف ومواسير)
    if (variant == null) {
      final isDrainageCat =
          categoryName.contains('صرف') || categoryName.contains('مواسير');
      final pairedBrand = ScanService.detectBrandFromText(
        isDrainageCat ? 'وايتكس' : 'راك',
        catalog.brands,
      );
      if (pairedBrand != null) {
        final pairedVar = catalog.findVariant(template.id, pairedBrand.id);
        if (pairedVar != null) {
          variant = pairedVar;
          resolvedBrand = pairedBrand;
        }
      }
    }

    if (variant == null) {
      final firstVar = catalog.variantsForTemplate(template.id).firstOrNull;
      if (firstVar != null) {
        variant = firstVar;
        resolvedBrand = catalog.findBrand(firstVar.brandId) ?? resolvedBrand;
      }
    }

    final pipePricing = ScanService.computePipePricing(
      templateUnit: template.unit,
      requestedUnit: currentUnit == 'متر' ? 'متر' : null,
      rawOcrText: currentUnit == 'متر' ? rawOcrText : null,
      categoryName: categoryName,
      itemName: template.name,
      basePrice: variant?.price ?? 0,
    );

    return (
      template: template,
      variant: variant,
      brand: resolvedBrand,
      categoryName: categoryName,
      unit: pipePricing.unit,
      unitPrice: pipePricing.unitPrice,
    );
  }

  Future<ItemTemplateModel?> _pickCatalogTemplateSheet({
    required CatalogState catalog,
    required String? preferredBrandId,
    required String? fallbackBrandId,
    InvoiceItemModel? referenceItem,
    String? title,
  }) async {
    final currentTemplate = referenceItem != null
        ? catalog.findTemplate(referenceItem.itemTemplateId)
        : null;
    final refNameNorm =
        referenceItem != null ? _normalizeSearchAr(referenceItem.itemName) : '';
    final refTokens = referenceItem != null
        ? _searchTokens(
            '${referenceItem.itemName} ${referenceItem.rawOcrText ?? ''}',
          ).toSet()
        : <String>{};
    final refSizeNorm =
        referenceItem?.size != null ? _normalizeSearchAr(referenceItem!.size!) : '';

    final categoryNameById = <String, String>{
      for (final c in catalog.categories) c.id: c.name,
    };

    // Score similarity for every template relative to referenceItem
    final similarityById = <String, int>{};
    if (referenceItem != null) {
      for (final t in catalog.templates) {
        var score = 0;
        if (t.id == referenceItem.itemTemplateId) {
          score += 1000;
        }
        final tNameNorm = _normalizeSearchAr(t.name);
        if (refNameNorm.isNotEmpty && tNameNorm == refNameNorm) {
          score += 50;
        } else if (refNameNorm.isNotEmpty &&
            (tNameNorm.contains(refNameNorm) || refNameNorm.contains(tNameNorm))) {
          score += 24;
        }
        final tTokens = _searchTokens(t.name);
        for (final tok in tTokens) {
          if (refTokens.contains(tok)) {
            score += 10;
          }
        }
        if (refSizeNorm.isNotEmpty &&
            t.size != null &&
            _normalizeSearchAr(t.size!) == refSizeNorm) {
          score += 4;
        }
        similarityById[t.id] = score;
      }
    }

    String? referenceCategoryId = currentTemplate?.categoryId;
    if (referenceCategoryId == null && referenceItem != null) {
      ItemTemplateModel? bestTpl;
      var bestScore = 0;
      for (final t in catalog.templates) {
        final s = similarityById[t.id] ?? 0;
        if (s > bestScore) {
          bestScore = s;
          bestTpl = t;
        }
      }
      if (bestScore >= 10) {
        referenceCategoryId = bestTpl?.categoryId;
      }
    }

    // '__smart__' = الأقرب ونفس النوع, '__all__' = الكل, otherwise categoryId
    String filterMode =
        referenceItem != null ? '__smart__' : '__all__';
    String query = '';

    return showModalBottomSheet<ItemTemplateModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final qNorm = _normalizeSearchAr(query);
            final qTokens = _searchTokens(query);

            final matches = <ItemTemplateModel>[];
            for (final t in catalog.templates) {
              if (qNorm.isNotEmpty) {
                if (filterMode != '__smart__' &&
                    filterMode != '__all__' &&
                    t.categoryId != filterMode) {
                  continue;
                }
                final hay = _normalizeSearchAr(
                  '${t.name} ${t.size ?? ''} ${categoryNameById[t.categoryId] ?? ''}',
                );
                final matchesText = hay.contains(qNorm) ||
                    (qTokens.isNotEmpty && qTokens.every(hay.contains));
                final matchesAlias = !matchesText &&
                    catalog.aliases.any(
                      (a) =>
                          a.itemTemplateId == t.id &&
                          _normalizeSearchAr(a.aliasText).contains(qNorm),
                    );
                if (!matchesText && !matchesAlias) continue;
                matches.add(t);
              } else {
                if (filterMode == '__smart__') {
                  final sim = similarityById[t.id] ?? 0;
                  final sameCat = referenceCategoryId != null &&
                      t.categoryId == referenceCategoryId;
                  if (sameCat || sim >= 10 || referenceCategoryId == null) {
                    matches.add(t);
                  }
                } else if (filterMode == '__all__' ||
                    t.categoryId == filterMode) {
                  matches.add(t);
                }
              }
            }

            // Sort: current item first, then closest/similar matches, then same category, then name
            matches.sort((a, b) {
              final sa = (similarityById[a.id] ?? 0) +
                  (referenceCategoryId != null &&
                          a.categoryId == referenceCategoryId
                      ? 5
                      : 0);
              final sb = (similarityById[b.id] ?? 0) +
                  (referenceCategoryId != null &&
                          b.categoryId == referenceCategoryId
                      ? 5
                      : 0);
              if (sb != sa) return sb.compareTo(sa);
              return a.displayLabel.compareTo(b.displayLabel);
            });

            final refCatName = referenceCategoryId != null
                ? categoryNameById[referenceCategoryId]
                : null;

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.78,
              maxChildSize: 0.92,
              builder: (_, scrollCtrl) => Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  4,
                  16,
                  16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title ??
                          (referenceItem != null
                              ? 'اختر الصنف المطابق من الكتالوج'
                              : 'إضافة صنف من شجرة الأسعار'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    if (referenceItem != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'البند الحالي: ${referenceItem.displayName}${refCatName != null ? ' • $refCatName' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      key: const Key('smart_catalog_search_field'),
                      onChanged: (v) => setSheetState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'ابحث بالاسم أو المقاس أو مسمى السباك...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (referenceItem != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                key: const Key('picker_filter_smart'),
                                label: Text(
                                  refCatName != null
                                      ? 'الأقرب و$refCatName'
                                      : 'الأقرب',
                                ),
                                selected: filterMode == '__smart__',
                                onSelected: (_) => setSheetState(
                                  () => filterMode = '__smart__',
                                ),
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: ChoiceChip(
                              key: const Key('picker_filter_all'),
                              label: const Text('الكل'),
                              selected: filterMode == '__all__',
                              onSelected: (_) =>
                                  setSheetState(() => filterMode = '__all__'),
                            ),
                          ),
                          for (final cat in catalog.categories)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: ChoiceChip(
                                label: Text(cat.name),
                                selected: filterMode == cat.id,
                                onSelected: (_) =>
                                    setSheetState(() => filterMode = cat.id),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: matches.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد أصناف مطابقة للبحث',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            )
                          : ListView.separated(
                              controller: scrollCtrl,
                              itemCount: matches.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, idx) {
                                final t = matches[idx];
                                final isCurrent =
                                    referenceItem?.itemTemplateId == t.id;
                                final resolved = _resolveCatalogSelection(
                                  catalog: catalog,
                                  template: t,
                                  preferredBrandId: preferredBrandId,
                                  fallbackBrandId: fallbackBrandId,
                                  currentUnit: referenceItem?.unit,
                                  rawOcrText: referenceItem?.rawOcrText,
                                );
                                final subtitleParts = <String>[
                                  if (resolved.categoryName.isNotEmpty)
                                    resolved.categoryName,
                                  if (resolved.brand != null)
                                    resolved.brand!.name,
                                  resolved.unit,
                                ];

                                return ListTile(
                                  selected: isCurrent,
                                  selectedTileColor: AppTheme.primaryColor
                                      .withValues(alpha: 0.08),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          t.displayLabel,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      if (isCurrent)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'الحالي',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    subtitleParts.isNotEmpty
                                        ? subtitleParts.join(' • ')
                                        : 'غير مسعر',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade700,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        resolved.variant != null
                                            ? InvoiceShareService
                                                .formatCurrency(
                                                resolved.unitPrice,
                                              )
                                            : 'غير مسعر',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13,
                                          color: resolved.variant != null
                                              ? AppTheme.primaryColor
                                              : Colors.grey.shade500,
                                        ),
                                      ),
                                      if (isCurrent)
                                        const Icon(
                                          Icons.check_circle,
                                          size: 16,
                                          color: AppTheme.primaryColor,
                                        ),
                                    ],
                                  ),
                                  onTap: () => Navigator.pop(ctx, t),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCatalogPicker({
    required InvoiceModel draft,
    int? replaceIndex,
  }) async {
    final catalog = ref.read(catalogProvider);
    final oldItem = replaceIndex != null ? draft.items[replaceIndex] : null;
    final selectedTemplate = await _pickCatalogTemplateSheet(
      catalog: catalog,
      preferredBrandId: oldItem?.brandId ?? draft.brandId,
      fallbackBrandId: draft.brandId,
      referenceItem: oldItem,
      title: replaceIndex != null
          ? 'اختر الصنف من نفس النوع أو الأقرب'
          : 'إضافة صنف من شجرة الأسعار',
    );
    if (selectedTemplate == null || !mounted) return;

    final resolved = _resolveCatalogSelection(
      catalog: catalog,
      template: selectedTemplate,
      preferredBrandId: oldItem?.brandId ?? draft.brandId,
      fallbackBrandId: draft.brandId,
      currentUnit: oldItem?.unit,
      rawOcrText: oldItem?.rawOcrText,
    );

    if (replaceIndex != null && oldItem != null) {
      final rawPhrase = oldItem.rawOcrText ?? oldItem.itemName;
      final cleanedAlias = ScanService.cleanAliasPhrase(rawPhrase);
      if (cleanedAlias.isNotEmpty && oldItem.itemTemplateId != selectedTemplate.id) {
        ref
            .read(catalogProvider.notifier)
            .learnAlias(cleanedAlias, selectedTemplate.id);
      }

      _updateItem(
        draft,
        replaceIndex,
        InvoiceItemModel(
          id: oldItem.id,
          sortOrder: oldItem.sortOrder,
          rawOcrText: oldItem.rawOcrText,
          itemTemplateId: selectedTemplate.id,
          brandId: resolved.brand?.id,
          productVariantId: resolved.variant?.id,
          brandName: resolved.brand?.name,
          itemName: selectedTemplate.name,
          size: selectedTemplate.size,
          unit: resolved.unit,
          quantity: oldItem.quantity,
          unitPrice: resolved.unitPrice,
          confidence: OcrConfidence.high,
          notes: null,
        ),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تطبيق "${selectedTemplate.displayLabel}" بسعر ${InvoiceShareService.formatCurrency(resolved.unitPrice)}',
          ),
        ),
      );
    } else {
      final newItem = InvoiceItemModel(
        id: _uuid.v4(),
        sortOrder: draft.items.length,
        itemTemplateId: selectedTemplate.id,
        brandId: resolved.brand?.id,
        productVariantId: resolved.variant?.id,
        brandName: resolved.brand?.name,
        itemName: selectedTemplate.name,
        size: selectedTemplate.size,
        unit: resolved.unit,
        quantity: 1,
        unitPrice: resolved.unitPrice,
        confidence: OcrConfidence.high,
      );
      _updateDraft(
        _syncBrandSummary(
          _withFormFields(draft).copyWith(
            items: [...draft.items, newItem],
          ),
        ),
      );
    }
  }

  Future<void> _showEditItemDialog(
    InvoiceModel draft,
    int index,
    InvoiceItemModel item,
  ) async {
    final catalog = ref.read(catalogProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditInvoiceItemDialog(
        item: item,
        catalog: catalog,
        draftBrandId: draft.brandId,
        parseNumeric: _parseNumericText,
        onPickCatalogTemplate: (currentItem) => _pickCatalogTemplateSheet(
          catalog: catalog,
          preferredBrandId: currentItem.brandId ?? draft.brandId,
          fallbackBrandId: draft.brandId,
          referenceItem: currentItem,
          title: 'اختر الصنف من نفس النوع أو الأقرب',
        ),
        resolveTemplate: (tpl, currentItem) => _resolveCatalogSelection(
          catalog: catalog,
          template: tpl,
          preferredBrandId: currentItem.brandId ?? draft.brandId,
          fallbackBrandId: draft.brandId,
          currentUnit: currentItem.unit,
          rawOcrText: currentItem.rawOcrText,
        ),
        onSave: (updatedItem) {
          if (updatedItem.itemTemplateId != null &&
              updatedItem.itemTemplateId != item.itemTemplateId) {
            final rawPhrase = item.rawOcrText ?? item.itemName;
            final cleanedAlias = ScanService.cleanAliasPhrase(rawPhrase);
            if (cleanedAlias.isNotEmpty) {
              ref
                  .read(catalogProvider.notifier)
                  .learnAlias(cleanedAlias, updatedItem.itemTemplateId!);
            }
          }
          _updateItem(draft, index, updatedItem);
        },
      ),
    );
  }

  void _showZoomImageDialog(Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 5.0,
                child: Image.memory(bytes),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showApprovedShareDialog(
    InvoiceModel invoice, {
    String? customTitle,
    String? customSubtitle,
    String? saveOnlyMessage,
  }) async {
    final shop = ref.read(catalogProvider).shopSettings;
    final messenger = ScaffoldMessenger.of(context);
    final normalizedPhone = InvoiceShareService.normalizeEgyptianWhatsAppPhone(
      invoice.customerPhone,
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.check_circle_rounded,
          color: AppTheme.highConfidenceColor,
          size: 42,
        ),
        title: Text(
          customTitle ?? 'تم اعتماد الفاتورة بنجاح',
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                customSubtitle ??
                    'فاتورة ${invoice.invoiceNumber} — الإجمالي: ${InvoiceShareService.formatCurrency(invoice.total)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('approved_whatsapp_btn'),
                onPressed: () => InvoiceShareService.openWhatsApp(
                  invoice: invoice,
                  shop: shop,
                ),
                icon: const Icon(Icons.chat_outlined),
                label: Text(
                  normalizedPhone != null
                      ? 'إرسال واتساب إلى ${invoice.customerPhone!.trim()}'
                      : 'إرسال عبر واتساب',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('approved_share_pdf_btn'),
                onPressed: () => InvoiceShareService.shareInvoicePdf(
                  invoice: invoice,
                  shop: shop,
                ),
                icon: const Icon(Icons.share_outlined),
                label: const Text('مشاركة ملف PDF'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('approved_preview_pdf_btn'),
                onPressed: () => InvoiceShareService.previewOrPrintPdf(
                  invoice: invoice,
                  shop: shop,
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('معاينة / طباعة PDF'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                key: const Key('approved_save_only_btn'),
                onPressed: () {
                  Navigator.pop(ctx);
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(
                        saveOnlyMessage ?? 'تم اعتماد الفاتورة وحفظها بنجاح',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.done_all_rounded),
                label: const Text('حفظ فقط'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatNumInput(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }

  void _collectFullPayment(InvoiceModel draft) {
    final formDraft = _withFormFields(draft);
    final collectedNow = formDraft.remainingAmount;
    final settled = formDraft.copyWith(
      status: InvoiceStatus.approved,
      paymentMethod: PaymentMethod.cash,
      paidAmount: formDraft.total,
      clearPaymentDueDate: true,
    );

    _paidAmountCtrl.clear();
    _paymentError = null;
    _hasUnsavedChanges = false;
    _updateDraft(settled, markDirty: false);
    ref.read(invoicesProvider.notifier).saveInvoice(settled);
    ref
        .read(notificationsProvider.notifier)
        .markInvoiceNotificationsRead(settled.id);

    _showApprovedShareDialog(
      settled,
      customTitle: 'تم تحصيل الفاتورة بالكامل',
      customSubtitle:
          'تم تحصيل ${InvoiceShareService.formatCurrency(collectedNow)} وإغلاق مديونية فاتورة ${settled.invoiceNumber}',
      saveOnlyMessage: 'تم تأكيد التحصيل بالكامل وحفظ الفاتورة',
    );
  }

  Future<void> _showPartialCollectionDialog(InvoiceModel draft) async {
    final formDraft = _withFormFields(draft);
    await showDialog<void>(
      context: context,
      builder: (ctx) => _PartialPaymentCollectionDialog(
        invoice: formDraft,
        parseNumeric: _parseNumericText,
        onConfirm: (collectedNow, nextDueDate) {
          final previouslyPaid = formDraft.effectivePaidAmount;
          final nextTotalPaid =
              (previouslyPaid + collectedNow).clamp(0.0, formDraft.total);
          final nextRemaining =
              (formDraft.total - nextTotalPaid).clamp(0.0, double.infinity);

          final isNowSettled = nextRemaining <= 0.01;
          final updated = isNowSettled
              ? formDraft.copyWith(
                  status: InvoiceStatus.approved,
                  paymentMethod: PaymentMethod.cash,
                  paidAmount: formDraft.total,
                  clearPaymentDueDate: true,
                )
              : formDraft.copyWith(
                  status: InvoiceStatus.approved,
                  paymentMethod: PaymentMethod.partialNowRestLater,
                  paidAmount: nextTotalPaid,
                  paymentDueDate: nextDueDate,
                );

          if (isNowSettled) {
            _paidAmountCtrl.clear();
          } else {
            _paidAmountCtrl.text = _formatNumInput(nextTotalPaid);
          }
          _paymentError = null;
          _hasUnsavedChanges = false;
          _updateDraft(updated, markDirty: false);
          ref.read(invoicesProvider.notifier).saveInvoice(updated);
          ref
              .read(notificationsProvider.notifier)
              .markInvoiceNotificationsRead(updated.id);

          final nextDateStr = updated.paymentDueDate != null
              ? InvoiceModel.formatDisplayDate(updated.paymentDueDate!)
              : null;
          _showApprovedShareDialog(
            updated,
            customTitle: isNowSettled
                ? 'تم تحصيل الفاتورة بالكامل'
                : 'تم تسجيل دفعة وتحديث موعد الباقي',
            customSubtitle: isNowSettled
                ? 'تم تحصيل ${InvoiceShareService.formatCurrency(collectedNow)} وإغلاق المديونية'
                : 'دُفع الآن ${InvoiceShareService.formatCurrency(collectedNow)} • المتبقي: ${InvoiceShareService.formatCurrency(nextRemaining)}${nextDateStr != null ? ' • موعد السداد: $nextDateStr' : ''}',
            saveOnlyMessage: isNowSettled
                ? 'تم تحصيل الفاتورة بالكامل وحفظها'
                : 'تم تسجيل الدفعة وجدولة إشعار المبلغ المتبقي',
          );
        },
      ),
    );
  }

  Future<void> _pickPaymentDueDate(InvoiceModel draft) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = draft.paymentDueDate != null &&
            !draft.paymentDueDate!.isBefore(today)
        ? draft.paymentDueDate!
        : today;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _paymentError = null);
    _updateDraft(_withFormFields(draft).copyWith(paymentDueDate: picked));
  }

  bool _saveDraft(InvoiceModel rawDraft, InvoiceStatus targetStatus) {
    if (_customerCtrl.text.trim().isEmpty) {
      setState(() => _customerNameError = 'مطلوب إدخال اسم العميل أولاً');
      _customerFocusNode.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('مطلوب إدخال اسم العميل قبل حفظ أو اعتماد الفاتورة'),
        ),
      );
      return false;
    }

    if (_customerNameError != null) {
      setState(() => _customerNameError = null);
    }

    final finalized = _withFormFields(rawDraft).copyWith(status: targetStatus);

    if (targetStatus == InvoiceStatus.approved) {
      if (finalized.paymentMethod.requiresPaidNow &&
          (finalized.paidAmount <= 0 ||
              finalized.paidAmount >= finalized.total)) {
        final msg = finalized.paidAmount <= 0
            ? 'مطلوب إدخال المبلغ المدفوع الآن (أكبر من صفر)'
            : 'المبلغ المدفوع يجب أن يكون أقل من إجمالي الفاتورة';
        setState(() => _paymentError = msg);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
        return false;
      }
      if (finalized.paymentMethod.requiresDueDate &&
          finalized.paymentDueDate == null) {
        setState(() => _paymentError = 'مطلوب تحديد موعد السداد');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('مطلوب تحديد موعد السداد قبل الاعتماد')),
        );
        return false;
      }
    }

    if (_paymentError != null) {
      setState(() => _paymentError = null);
    }

    _hasUnsavedChanges = false;
    _updateDraft(finalized, markDirty: false);
    ref.read(invoicesProvider.notifier).saveInvoice(finalized);
    if (targetStatus == InvoiceStatus.approved) {
      _showApprovedShareDialog(finalized);
      return true;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم حفظ عرض السعر بنجاح'),
      ),
    );
    return true;
  }

  Future<void> _handleUnsavedExit(InvoiceModel draft) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ الكشف قبل الخروج؟'),
        content: const Text(
          'لم تقم بحفظ التغييرات على هذا الكشف بعد. هل تريد حفظه كعرض سعر للرجوع إليه لاحقاً أم مسحه والخروج؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.lowConfidenceColor,
            ),
            child: const Text('مسح والخروج'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('حفظ كعرض سعر'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (choice == 'save') {
      final saved = _saveDraft(draft, InvoiceStatus.quote);
      if (!saved) return;
      _exitToHome();
    } else if (choice == 'discard') {
      final draftNotifier = ref.read(activeDraftProvider.notifier);
      setState(() => _hasUnsavedChanges = false);
      _exitToHome();
      draftNotifier.clear();
    }
  }

  void _exitToHome() {
    ref.read(shellTabIndexProvider.notifier).setIndex(0);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawDraft = ref.watch(activeDraftProvider);

    if (rawDraft == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          _exitToHome();
        },
        child: Scaffold(
          appBar: AppBar(title: const Text('مراجعة التسعير')),
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('لا يوجد كشف مفتوح للمراجعة حالياً'),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _exitToHome,
                  child: const Text('العودة للرئيسية'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    _syncControllersIfNeeded(rawDraft);
    final draft = _withFormFields(rawDraft);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          _handleUnsavedExit(draft);
        } else {
          _exitToHome();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('مراجعة ${draft.invoiceNumber}'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Chip(
              label: Text(
                draft.brandSummary ?? 'غير محدد',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primaryColor,
                ),
              ),
              backgroundColor: Colors.white,
              side: BorderSide.none,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
            children: [
              if (draft.localScanImages.isNotEmpty) ...[
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: true,
                    shape: const Border(),
                    leading: const Icon(
                      Icons.image_search_rounded,
                      color: AppTheme.primaryColor,
                    ),
                    title: Text(
                      'صورة الورقة الأصلية (${draft.localScanImages.length}) — اضغط للتكبير',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    children: [
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          scrollDirection: Axis.horizontal,
                          itemCount: draft.localScanImages.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (_, idx) {
                            final bytes = draft.localScanImages[idx];
                            return InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _showZoomImageDialog(bytes),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Stack(
                                  children: [
                                    Image.memory(
                                      bytes,
                                      width: 100,
                                      height: 110,
                                      fit: BoxFit.cover,
                                    ),
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: const Icon(
                                          Icons.zoom_in,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              // Quick Action Strip: Brand Switch + Add Item
              Card(
                color: const Color(0xFFF0F9FF),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الشركة الحالية: ${draft.brandSummary ?? "غير محددة"}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const Text(
                            'يمكنك تبديل الشركة أو الاحتفاظ بنسختين للمقارنة',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _showBrandSwitchSheet(draft),
                            icon: const Icon(Icons.compare_arrows_rounded),
                            label: const Text('تغيير الشركة / مقارنة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _showCatalogPicker(draft: draft),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة بند'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Customer & Optional Technician Data
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'بيانات العميل والفني',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('review_customer_name_field'),
                              controller: _customerCtrl,
                              focusNode: _customerFocusNode,
                              onChanged: (v) {
                                if (_customerNameError != null &&
                                    v.trim().isNotEmpty) {
                                  setState(() => _customerNameError = null);
                                }
                                _updateDraft(_withFormFields(draft));
                              },
                              decoration: InputDecoration(
                                labelText: 'اسم العميل *',
                                errorText: _customerNameError,
                                prefixIcon: const Icon(Icons.person_outline),
                                suffixIcon: IconButton(
                                  tooltip: 'اختيار عميل سابق',
                                  icon: const Icon(Icons.contacts_outlined),
                                  onPressed: () =>
                                      _showCustomerQuickPickDialog(draft),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              key: const Key('review_customer_phone_field'),
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              onChanged: (_) =>
                                  _updateDraft(_withFormFields(draft)),
                              decoration: const InputDecoration(
                                labelText: 'رقم الواتساب / الهاتف',
                                prefixIcon: Icon(Icons.phone_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _techCtrl,
                        onChanged: (_) => _updateDraft(_withFormFields(draft)),
                        decoration: InputDecoration(
                          labelText: 'اسم الفني / السباك (اختياري)',
                          hintText:
                              'إذا تُرك فارغاً لن يظهر في الفاتورة أو الـ PDF',
                          prefixIcon: const Icon(Icons.engineering_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'اختيار فني سابق',
                            icon: const Icon(Icons.history_outlined),
                            onPressed: () =>
                                _showTechnicianQuickPickDialog(draft),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Confidence Filter Tabs
              Builder(
                builder: (context) {
                  final highCount = draft.items
                      .where((i) => i.confidence == OcrConfidence.high)
                      .length;
                  final mediumCount = draft.items
                      .where((i) => i.confidence == OcrConfidence.medium)
                      .length;
                  final lowCount = draft.items
                      .where((i) => i.confidence == OcrConfidence.low)
                      .length;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _ConfidenceFilterTab(
                          key: const Key('review_filter_all'),
                          label: 'الكل (${draft.items.length})',
                          selected: _confidenceFilter == null,
                          color: AppTheme.primaryColor,
                          bg: const Color(0xFFE0F2FE),
                          onTap: () =>
                              setState(() => _confidenceFilter = null),
                        ),
                        const SizedBox(width: 8),
                        _ConfidenceFilterTab(
                          key: const Key('review_filter_high'),
                          label: 'مؤكد ($highCount)',
                          selected: _confidenceFilter == OcrConfidence.high,
                          color: AppTheme.highConfidenceColor,
                          bg: AppTheme.highConfidenceBg,
                          onTap: () => setState(
                            () => _confidenceFilter = OcrConfidence.high,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ConfidenceFilterTab(
                          key: const Key('review_filter_medium'),
                          label: 'محتاج تأكيد ($mediumCount)',
                          selected: _confidenceFilter == OcrConfidence.medium,
                          color: AppTheme.mediumConfidenceColor,
                          bg: AppTheme.mediumConfidenceBg,
                          onTap: () => setState(
                            () => _confidenceFilter = OcrConfidence.medium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _ConfidenceFilterTab(
                          key: const Key('review_filter_low'),
                          label: 'غير متطابق ($lowCount)',
                          selected: _confidenceFilter == OcrConfidence.low,
                          color: AppTheme.lowConfidenceColor,
                          bg: AppTheme.lowConfidenceBg,
                          onTap: () => setState(
                            () => _confidenceFilter = OcrConfidence.low,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),

              // Items List
              if (draft.items.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: Text('لا توجد بنود بعد — اضغط "إضافة بند"'),
                    ),
                  ),
                )
              else ...[
                Builder(
                  builder: (context) {
                    final visibleEntries = [
                      for (var i = 0; i < draft.items.length; i++)
                        if (_confidenceFilter == null ||
                            draft.items[i].confidence == _confidenceFilter)
                          (index: i, item: draft.items[i]),
                    ];
                    if (visibleEntries.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.check_circle_outline_rounded,
                                color: AppTheme.highConfidenceColor,
                                size: 32,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'لا توجد بنود في هذه الحالة حالياً',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 6),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _confidenceFilter = null),
                                child: const Text('عرض كل البنود'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      children: [
                        for (final entry in visibleEntries)
                          _ReviewItemCard(
                            key: ValueKey(entry.item.id),
                            item: entry.item,
                            onIncrement: () => _updateItem(
                              draft,
                              entry.index,
                              entry.item.copyWith(
                                quantity: entry.item.quantity + 1,
                              ),
                            ),
                            onDecrement: () {
                              if (entry.item.quantity > 1) {
                                _updateItem(
                                  draft,
                                  entry.index,
                                  entry.item.copyWith(
                                    quantity: entry.item.quantity - 1,
                                  ),
                                );
                              }
                            },
                            onQuantityChanged: (qty) => _updateItem(
                              draft,
                              entry.index,
                              entry.item.copyWith(quantity: qty),
                            ),
                            onConfirm: entry.item.confidence !=
                                    OcrConfidence.high
                                ? () => _updateItem(
                                      draft,
                                      entry.index,
                                      entry.item.copyWith(
                                        confidence: OcrConfidence.high,
                                        clearNotes: true,
                                      ),
                                    )
                                : null,
                            onEdit: () => _showEditItemDialog(
                              draft,
                              entry.index,
                              entry.item,
                            ),
                            onLinkToCatalog: () => _showCatalogPicker(
                              draft: draft,
                              replaceIndex: entry.index,
                            ),
                            onPickBrand: entry.item.itemTemplateId != null
                                ? () => _showPerItemBrandSheet(
                                      draft,
                                      entry.index,
                                      entry.item,
                                    )
                                : null,
                            onDelete: () => _removeItem(draft, entry.index),
                          ),
                      ],
                    );
                  },
                ),
              ],

              const SizedBox(height: 12),

              // Discount & Totals Summary
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<DiscountType>(
                              initialValue: draft.discountType,
                              decoration:
                                  const InputDecoration(labelText: 'نوع الخصم'),
                              items: [
                                for (final type in DiscountType.values)
                                  DropdownMenuItem(
                                    value: type,
                                    child: Text(type.arabicLabel),
                                  ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  _updateDraft(
                                    _withFormFields(draft)
                                        .copyWith(discountType: val),
                                  );
                                }
                              },
                            ),
                          ),
                          if (draft.discountType != DiscountType.none) ...[
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _discountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) =>
                                    _updateDraft(_withFormFields(draft)),
                                decoration: InputDecoration(
                                  labelText: draft.discountType ==
                                          DiscountType.percent
                                      ? 'النسبة %'
                                      : 'مبلغ الخصم (ج.م)',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Divider(height: 22),
                      _TotalRow(
                        label: 'المجموع الفرعي:',
                        value: InvoiceShareService.formatCurrency(draft.subtotal),
                      ),
                      if (draft.discountAmount > 0)
                        _TotalRow(
                          label: 'الخصم:',
                          value:
                              '-${InvoiceShareService.formatCurrency(draft.discountAmount)}',
                          valueColor: AppTheme.lowConfidenceColor,
                        ),
                      const SizedBox(height: 6),
                      _TotalRow(
                        label: 'الإجمالي النهائي:',
                        value: InvoiceShareService.formatCurrency(draft.total),
                        isBold: true,
                        valueColor: AppTheme.primaryColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Payment Collection Method Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'طريقة التحصيل',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<PaymentMethod>(
                        key: const Key('payment_method_dropdown'),
                        initialValue: draft.paymentMethod,
                        decoration: const InputDecoration(
                          labelText: 'اختر طريقة التحصيل',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        items: [
                          for (final method in PaymentMethod.values)
                            DropdownMenuItem(
                              value: method,
                              child: Text(method.arabicLabel),
                            ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() => _paymentError = null);
                          if (!val.requiresPaidNow) {
                            _paidAmountCtrl.clear();
                          }
                          _updateDraft(
                            _withFormFields(draft).copyWith(
                              paymentMethod: val,
                              paidAmount: val.requiresPaidNow
                                  ? _parseNumericText(_paidAmountCtrl.text)
                                  : 0,
                              clearPaymentDueDate: !val.requiresDueDate,
                            ),
                          );
                        },
                      ),
                      if (draft.paymentMethod == PaymentMethod.cash) ...[
                        const SizedBox(height: 8),
                        Text(
                          'تحصيل كامل المبلغ كاش (${InvoiceShareService.formatCurrency(draft.total)})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      if (draft.paymentMethod.requiresPaidNow) ...[
                        const SizedBox(height: 10),
                        TextField(
                          key: const Key('paid_amount_field'),
                          controller: _paidAmountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) {
                            if (_paymentError != null) {
                              setState(() => _paymentError = null);
                            }
                            _updateDraft(_withFormFields(draft));
                          },
                          decoration: InputDecoration(
                            labelText: draft.paymentMethod.paidAmountLabel,
                            hintText: 'مثال: 500',
                            prefixIcon: const Icon(Icons.attach_money),
                          ),
                        ),
                      ],
                      if (draft.paymentMethod.requiresDueDate) ...[
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          key: const Key('payment_due_date_picker'),
                          onPressed: () => _pickPaymentDueDate(draft),
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(
                            draft.paymentDueDate != null
                                ? '${draft.paymentMethod.dueDateLabel}: ${InvoiceModel.formatDateOnly(draft.paymentDueDate)}'
                                : draft.paymentMethod.dueDateLabel,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F9FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            draft.paymentMethod ==
                                    PaymentMethod.deferredNoDeposit
                                ? 'المتبقي بالكامل: ${InvoiceShareService.formatCurrency(draft.remainingAmount)}'
                                : 'المدفوع: ${InvoiceShareService.formatCurrency(draft.effectivePaidAmount)}  |  المتبقي: ${InvoiceShareService.formatCurrency(draft.remainingAmount)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                      if (_paymentError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _paymentError!,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.lowConfidenceColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppTheme.cardBorder)),
          ),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: draft.status == InvoiceStatus.approved &&
                      draft.remainingAmount > 0
                  ? Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('partial_collection_button'),
                            onPressed: () =>
                                _showPartialCollectionDialog(draft),
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('دفع جزء وباقي جزء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            key: const Key('full_collection_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.highConfidenceColor,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _collectFullPayment(draft),
                            icon: const Icon(Icons.check_circle_rounded),
                            label: Text(
                              'تم التحصيل (${InvoiceShareService.formatCurrency(draft.remainingAmount)})',
                            ),
                          ),
                        ),
                      ],
                    )
                  : Builder(
                      builder: (context) {
                        final unconfirmedItems = draft.items
                            .where((i) => i.confidence != OcrConfidence.high)
                            .toList();
                        final unconfirmedCount = unconfirmedItems.length;
                        final canApprove =
                            draft.items.isNotEmpty && unconfirmedCount == 0;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (unconfirmedCount > 0) ...[
                              InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  final hasLow = unconfirmedItems.any(
                                    (i) => i.confidence == OcrConfidence.low,
                                  );
                                  setState(
                                    () => _confidenceFilter = hasLow
                                        ? OcrConfidence.low
                                        : OcrConfidence.medium,
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.mediumConfidenceBg,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.info_outline_rounded,
                                        size: 16,
                                        color: AppTheme.mediumConfidenceColor,
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'باقي $unconfirmedCount بند يحتاج تأكيد قبل الاعتماد (اضغط للعرض)',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                AppTheme.mediumConfidenceColor,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _saveDraft(draft, InvoiceStatus.quote),
                                    icon:
                                        const Icon(Icons.bookmark_add_outlined),
                                    label: const Text('حفظ عرض سعر'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 2,
                                  child: ElevatedButton.icon(
                                    key: const Key('review_approve_button'),
                                    onPressed: canApprove
                                        ? () => _saveDraft(
                                              draft,
                                              InvoiceStatus.approved,
                                            )
                                        : null,
                                    icon:
                                        const Icon(Icons.check_circle_outline),
                                    label: Text(
                                      draft.status == InvoiceStatus.approved
                                          ? 'تحديث ومشاركة (${InvoiceShareService.formatCurrency(draft.total)})'
                                          : 'اعتماد (${InvoiceShareService.formatCurrency(draft.total)})',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.invoice,
    required this.onSelect,
    required this.onWhatsApp,
  });

  final InvoiceModel invoice;
  final VoidCallback onSelect;
  final VoidCallback onWhatsApp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                invoice.brandSummary ?? 'بدون شركة',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.primaryColor,
                ),
              ),
              Text(
                InvoiceShareService.formatCurrency(invoice.total),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppTheme.accentColor,
                ),
              ),
            ],
          ),
          Text(
            invoice.invoiceNumber,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(onPressed: onSelect, child: const Text('مراجعة')),
              TextButton(onPressed: onWhatsApp, child: const Text('مشاركة PDF')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConfidenceFilterTab extends StatelessWidget {
  const _ConfidenceFilterTab({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.bg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final Color bg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

class _ReviewItemCard extends StatefulWidget {
  const _ReviewItemCard({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onQuantityChanged,
    this.onConfirm,
    required this.onEdit,
    required this.onLinkToCatalog,
    required this.onPickBrand,
    required this.onDelete,
  });

  final InvoiceItemModel item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double> onQuantityChanged;
  final VoidCallback? onConfirm;
  final VoidCallback onEdit;
  final VoidCallback onLinkToCatalog;
  final VoidCallback? onPickBrand;
  final VoidCallback onDelete;

  @override
  State<_ReviewItemCard> createState() => _ReviewItemCardState();
}

class _ReviewItemCardState extends State<_ReviewItemCard> {
  late final TextEditingController _qtyCtrl;
  late final FocusNode _qtyFocusNode;

  static String _formatQty(double q) {
    return q == q.roundToDouble() ? q.toInt().toString() : q.toString();
  }

  static double? _parseQty(String raw) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    final normalized = raw
        .trim()
        .replaceAllMapped(
          RegExp(r'[٠-٩]'),
          (m) => eastern.indexOf(m.group(0)!).toString(),
        )
        .replaceAll('،', '.')
        .replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(text: _formatQty(widget.item.quantity));
    _qtyFocusNode = FocusNode()..addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    if (!_qtyFocusNode.hasFocus) {
      final parsed = _parseQty(_qtyCtrl.text);
      if (parsed == null || parsed <= 0) {
        _qtyCtrl.text = _formatQty(widget.item.quantity);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _ReviewItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.quantity != widget.item.quantity) {
      final currentParsed = _parseQty(_qtyCtrl.text);
      if (currentParsed != widget.item.quantity) {
        _qtyCtrl.text = _formatQty(widget.item.quantity);
      }
    }
  }

  @override
  void dispose() {
    _qtyFocusNode.removeListener(_handleFocusChange);
    _qtyFocusNode.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final (accent, bg) = switch (item.confidence) {
      OcrConfidence.high => (
          AppTheme.highConfidenceColor,
          AppTheme.highConfidenceBg,
        ),
      OcrConfidence.medium => (
          AppTheme.mediumConfidenceColor,
          AppTheme.mediumConfidenceBg,
        ),
      OcrConfidence.low => (
          AppTheme.lowConfidenceColor,
          AppTheme.lowConfidenceBg,
        ),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accent.withValues(alpha: 0.45), width: 1.3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.confidence.arabicLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: accent,
                    ),
                  ),
                ),
                if (widget.onPickBrand != null) ...[
                  const SizedBox(width: 6),
                  Flexible(
                    child: ActionChip(
                      avatar: const Icon(Icons.swap_vert, size: 15),
                      label: Text(
                        item.brandName ?? 'شركة',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onPressed: widget.onPickBrand,
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.onConfirm != null)
                  IconButton.filledTonal(
                    key: Key('confirm_item_btn_${item.id}'),
                    tooltip: 'تأكيد البند',
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.highConfidenceBg,
                      foregroundColor: AppTheme.highConfidenceColor,
                    ),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.check_rounded, size: 19),
                    onPressed: widget.onConfirm,
                  ),
                IconButton(
                  tooltip: 'تعديل السعر/الاسم',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  tooltip: 'حذف البند',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.lowConfidenceColor,
                  ),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onLinkToCatalog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 20,
                      color: Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
            ),
            if (item.rawOcrText != null && item.rawOcrText!.isNotEmpty)
              Text(
                'النص المقروء من الورقة: "${item.rawOcrText}"',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (item.notes != null && item.notes!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.notes!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: widget.onDecrement,
                  icon: const Icon(Icons.remove, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 64,
                    child: TextField(
                      key: Key('item_qty_field_${item.id}'),
                      controller: _qtyCtrl,
                      focusNode: _qtyFocusNode,
                      textAlign: TextAlign.center,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) {
                        final parsed = _parseQty(val);
                        if (parsed != null && parsed > 0) {
                          widget.onQuantityChanged(parsed);
                        }
                      },
                    ),
                  ),
                ),
                IconButton.outlined(
                  onPressed: widget.onIncrement,
                  icon: const Icon(Icons.add, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                Text(
                  item.unit,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 8),
                Text(
                  '× ${InvoiceShareService.formatCurrency(item.unitPrice)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const Spacer(),
                Text(
                  InvoiceShareService.formatCurrency(item.lineTotal),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
            if (item.confidence != OcrConfidence.high) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: widget.onLinkToCatalog,
                  icon: const Icon(Icons.link_rounded, size: 18),
                  label: const Text('ربط بصنف من الكتالوج وحفظه بالقاموس'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.isBold = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool isBold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isBold ? 16 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 18 : 14,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

class _EditInvoiceItemDialog extends StatefulWidget {
  const _EditInvoiceItemDialog({
    required this.item,
    required this.catalog,
    required this.draftBrandId,
    required this.parseNumeric,
    required this.onPickCatalogTemplate,
    required this.resolveTemplate,
    required this.onSave,
  });

  final InvoiceItemModel item;
  final CatalogState catalog;
  final String? draftBrandId;
  final double Function(String) parseNumeric;
  final Future<ItemTemplateModel?> Function(InvoiceItemModel currentItem)
      onPickCatalogTemplate;
  final ({
    ItemTemplateModel template,
    ProductVariantModel? variant,
    BrandModel? brand,
    String categoryName,
    String unit,
    double unitPrice,
  }) Function(ItemTemplateModel template, InvoiceItemModel currentItem)
      resolveTemplate;
  final ValueChanged<InvoiceItemModel> onSave;

  @override
  State<_EditInvoiceItemDialog> createState() => _EditInvoiceItemDialogState();
}

class _EditInvoiceItemDialogState extends State<_EditInvoiceItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late InvoiceItemModel _workingItem;
  bool _manualNameMode = false;

  static String _formatNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _workingItem = widget.item;
    _nameCtrl = TextEditingController(text: widget.item.itemName);
    _qtyCtrl = TextEditingController(text: _formatNum(widget.item.quantity));
    _priceCtrl = TextEditingController(text: _formatNum(widget.item.unitPrice));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCatalogPicker() async {
    final picked = await widget.onPickCatalogTemplate(_workingItem);
    if (picked == null || !mounted) return;
    final resolved = widget.resolveTemplate(picked, _workingItem);
    setState(() {
      _manualNameMode = false;
      _workingItem = InvoiceItemModel(
        id: _workingItem.id,
        sortOrder: _workingItem.sortOrder,
        rawOcrText: _workingItem.rawOcrText,
        itemTemplateId: picked.id,
        brandId: resolved.brand?.id,
        productVariantId: resolved.variant?.id,
        brandName: resolved.brand?.name,
        itemName: picked.name,
        size: picked.size,
        unit: resolved.unit,
        quantity: widget.parseNumeric(_qtyCtrl.text) > 0
            ? widget.parseNumeric(_qtyCtrl.text)
            : _workingItem.quantity,
        unitPrice: resolved.unitPrice,
        confidence: OcrConfidence.high,
        notes: null,
      );
      _nameCtrl.text = picked.name;
      _priceCtrl.text = _formatNum(resolved.unitPrice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final metaParts = <String>[
      if (_workingItem.size != null && _workingItem.size!.trim().isNotEmpty)
        _workingItem.size!.trim(),
      if (_workingItem.brandName != null &&
          _workingItem.brandName!.trim().isNotEmpty)
        _workingItem.brandName!.trim(),
      _workingItem.unit,
    ];

    return AlertDialog(
      title: const Text('تعديل البند'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_manualNameMode) ...[
              InkWell(
                key: const Key('edit_item_name_selector'),
                borderRadius: BorderRadius.circular(10),
                onTap: _openCatalogPicker,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'اسم الصنف (اضغط للاختيار من الكتالوج)',
                    suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                  child: Text(
                    _workingItem.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ] else ...[
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: 'اسم الصنف (يدوي)',
                  suffixIcon: IconButton(
                    tooltip: 'اختيار من الكتالوج',
                    icon: const Icon(Icons.list_alt_rounded),
                    onPressed: _openCatalogPicker,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    metaParts.join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() => _manualNameMode = !_manualNameMode);
                  },
                  child: Text(
                    _manualNameMode ? 'اختيار من القائمة' : 'كتابة يدوية',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('edit_item_qty_field'),
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'الكمية'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    key: const Key('edit_item_price_field'),
                    controller: _priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'سعر الوحدة'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          key: const Key('edit_item_apply_btn'),
          onPressed: () {
            final parsedQty = widget.parseNumeric(_qtyCtrl.text);
            final parsedPrice = widget.parseNumeric(_priceCtrl.text);
            final nameText = _manualNameMode
                ? (_nameCtrl.text.trim().isEmpty
                    ? _workingItem.itemName
                    : _nameCtrl.text.trim())
                : _workingItem.itemName;
            widget.onSave(
              InvoiceItemModel(
                id: _workingItem.id,
                sortOrder: _workingItem.sortOrder,
                rawOcrText: _workingItem.rawOcrText,
                itemTemplateId: _workingItem.itemTemplateId,
                brandId: _workingItem.brandId,
                productVariantId: _workingItem.productVariantId,
                brandName: _workingItem.brandName,
                itemName: nameText,
                size: _workingItem.size,
                unit: _workingItem.unit,
                quantity: parsedQty > 0 ? parsedQty : _workingItem.quantity,
                unitPrice: parsedPrice >= 0 ? parsedPrice : _workingItem.unitPrice,
                confidence: OcrConfidence.high,
                notes: null,
              ),
            );
            Navigator.pop(context);
          },
          child: const Text('تطبيق'),
        ),
      ],
    );
  }
}

class _PartialPaymentCollectionDialog extends StatefulWidget {
  const _PartialPaymentCollectionDialog({
    required this.invoice,
    required this.parseNumeric,
    required this.onConfirm,
  });

  final InvoiceModel invoice;
  final double Function(String) parseNumeric;
  final void Function(double collectedNow, DateTime? nextDueDate) onConfirm;

  @override
  State<_PartialPaymentCollectionDialog> createState() =>
      _PartialPaymentCollectionDialogState();
}

class _PartialPaymentCollectionDialogState
    extends State<_PartialPaymentCollectionDialog> {
  late final TextEditingController _amountCtrl;
  DateTime? _nextDueDate;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickNextDueDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final initial = _nextDueDate ?? tomorrow;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(today) ? today : initial,
      firstDate: today,
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _nextDueDate = picked;
      _errorText = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.invoice.total;
    final previousPaid = widget.invoice.effectivePaidAmount;
    final currentRemaining = widget.invoice.remainingAmount;
    final enteredNow = widget.parseNumeric(_amountCtrl.text);
    final newRemaining =
        (currentRemaining - enteredNow).clamp(0.0, double.infinity);

    return AlertDialog(
      key: const Key('partial_collection_dialog'),
      title: const Text('تحصيل جزء وجدولة الباقي'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'إجمالي الفاتورة: ${InvoiceShareService.formatCurrency(total)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'المدفوع سابقاً: ${InvoiceShareService.formatCurrency(previousPaid)}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                  Text(
                    'المتبقي الحالي: ${InvoiceShareService.formatCurrency(currentRemaining)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.lowConfidenceColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('collect_now_amount_field'),
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _errorText = null),
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع الآن (ج.م) *',
                hintText: 'مثال: 400',
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: newRemaining <= 0.01
                    ? AppTheme.highConfidenceBg
                    : AppTheme.mediumConfidenceBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                newRemaining <= 0.01 && enteredNow > 0
                    ? 'سيتم تسديد كامل المتبقي وإغلاق المديونية'
                    : 'المتبقي الجديد بعد السداد: ${InvoiceShareService.formatCurrency(newRemaining)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: newRemaining <= 0.01 && enteredNow > 0
                      ? AppTheme.highConfidenceColor
                      : AppTheme.mediumConfidenceColor,
                ),
              ),
            ),
            if (newRemaining > 0.01) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const Key('collect_next_due_date_picker'),
                onPressed: _pickNextDueDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(
                  _nextDueDate != null
                      ? 'موعد سداد الباقي: ${InvoiceModel.formatDisplayDate(_nextDueDate!)}'
                      : 'تحديد موعد سداد المبلغ المتبقي *',
                ),
              ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.lowConfidenceColor,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          key: const Key('confirm_partial_collection_btn'),
          onPressed: () {
            final payNow = widget.parseNumeric(_amountCtrl.text);
            if (payNow <= 0) {
              setState(
                () => _errorText = 'مطلوب إدخال المبلغ المدفوع الآن (أكبر من صفر)',
              );
              return;
            }
            if (payNow > currentRemaining + 0.01) {
              setState(
                () => _errorText = 'المبلغ المدفوع أكبر من المتبقي على العميل',
              );
              return;
            }
            final remainingAfter =
                (currentRemaining - payNow).clamp(0.0, double.infinity);
            if (remainingAfter > 0.01 && _nextDueDate == null) {
              setState(
                () => _errorText = 'مطلوب تحديد موعد سداد المبلغ المتبقي',
              );
              return;
            }
            Navigator.pop(context);
            widget.onConfirm(
              payNow.clamp(0.0, currentRemaining),
              remainingAfter > 0.01 ? _nextDueDate : null,
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ التحصيل'),
        ),
      ],
    );
  }
}
