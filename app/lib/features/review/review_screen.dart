import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
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

  Future<void> _showCatalogPicker({
    required InvoiceModel draft,
    int? replaceIndex,
  }) async {
    final catalog = ref.read(catalogProvider);
    final brand =
        catalog.findBrand(draft.brandId) ?? catalog.brands.firstOrNull;
    String query = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final matches = catalog.templates.where((t) {
              if (query.trim().isEmpty) return true;
              final q = query.trim().toLowerCase();
              return t.name.toLowerCase().contains(q) ||
                  (t.size ?? '').toLowerCase().contains(q);
            }).toList();

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.72,
              maxChildSize: 0.9,
              builder: (_, scrollCtrl) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Column(
                  children: [
                    Text(
                      replaceIndex != null
                          ? 'ربط البند بصنف من الكتالوج (وحفظه بالقاموس)'
                          : 'إضافة صنف من شجرة الأسعار',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (v) => setSheetState(() => query = v),
                      decoration: const InputDecoration(
                        hintText: 'ابحث عن صنف...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        controller: scrollCtrl,
                        itemCount: matches.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, idx) {
                          final t = matches[idx];
                          final variant = (brand != null
                                  ? catalog.findVariant(t.id, brand.id)
                                  : null) ??
                              catalog.variantsForTemplate(t.id).firstOrNull;
                          final resolvedBrand = variant != null
                              ? catalog.findBrand(variant.brandId) ?? brand
                              : brand;

                          return ListTile(
                            title: Text(
                              t.displayLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              variant != null && resolvedBrand != null
                                  ? '${resolvedBrand.name} • ${InvoiceShareService.formatCurrency(variant.price)}'
                                  : 'غير مسعر لهذه الشركة',
                            ),
                            trailing: const Icon(Icons.add_circle_outline),
                            onTap: () {
                              if (replaceIndex != null) {
                                final oldItem = draft.items[replaceIndex];
                                final rawPhrase = oldItem.rawOcrText ??
                                    oldItem.itemName;
                                final cleanedAlias =
                                    ScanService.cleanAliasPhrase(rawPhrase);
                                if (cleanedAlias.isNotEmpty) {
                                  ref
                                      .read(catalogProvider.notifier)
                                      .learnAlias(cleanedAlias, t.id);
                                }

                                _updateItem(
                                  draft,
                                  replaceIndex,
                                  oldItem.copyWith(
                                    itemTemplateId: t.id,
                                    brandId: variant?.brandId,
                                    productVariantId: variant?.id,
                                    brandName: resolvedBrand?.name,
                                    itemName: t.name,
                                    size: t.size,
                                    unit: t.unit,
                                    unitPrice: variant?.price ?? 0,
                                    confidence: OcrConfidence.high,
                                    clearNotes: true,
                                  ),
                                );
                                Navigator.pop(ctx);
                                final shownAlias = cleanedAlias.isNotEmpty
                                    ? cleanedAlias
                                    : rawPhrase;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'تم ربط الصنف وحفظ "$shownAlias" في قاموس المحل',
                                    ),
                                  ),
                                );
                              } else {
                                final newItem = InvoiceItemModel(
                                  id: _uuid.v4(),
                                  sortOrder: draft.items.length,
                                  itemTemplateId: t.id,
                                  brandId: variant?.brandId,
                                  productVariantId: variant?.id,
                                  brandName: resolvedBrand?.name,
                                  itemName: t.name,
                                  size: t.size,
                                  unit: t.unit,
                                  quantity: 1,
                                  unitPrice: variant?.price ?? 0,
                                  confidence: OcrConfidence.high,
                                );
                                _updateDraft(
                                  _syncBrandSummary(
                                    _withFormFields(draft).copyWith(
                                      items: [...draft.items, newItem],
                                    ),
                                  ),
                                );
                                Navigator.pop(ctx);
                              }
                            },
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

  Future<void> _showEditItemDialog(
    InvoiceModel draft,
    int index,
    InvoiceItemModel item,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditInvoiceItemDialog(
        item: item,
        onSave: (updatedItem) => _updateItem(draft, index, updatedItem),
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

  Future<void> _showApprovedShareDialog(InvoiceModel invoice) async {
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
        title: const Text(
          'تم اعتماد الفاتورة بنجاح',
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
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
                    const SnackBar(
                      content: Text('تم اعتماد الفاتورة وحفظها بنجاح'),
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
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } else if (choice == 'discard') {
      final draftNotifier = ref.read(activeDraftProvider.notifier);
      setState(() => _hasUnsavedChanges = false);
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
      draftNotifier.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rawDraft = ref.watch(activeDraftProvider);

    if (rawDraft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('مراجعة التسعير')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('لا يوجد كشف مفتوح للمراجعة حالياً'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('العودة للرئيسية'),
              ),
            ],
          ),
        ),
      );
    }

    _syncControllersIfNeeded(rawDraft);
    final draft = _withFormFields(rawDraft);

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleUnsavedExit(draft);
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

              // Confidence Legend
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _LegendPill(
                    color: AppTheme.highConfidenceColor,
                    bg: AppTheme.highConfidenceBg,
                    text: 'مؤكد (${draft.items.where((i) => i.confidence == OcrConfidence.high).length})',
                  ),
                  _LegendPill(
                    color: AppTheme.mediumConfidenceColor,
                    bg: AppTheme.mediumConfidenceBg,
                    text: 'محتاج تأكيد (${draft.items.where((i) => i.confidence == OcrConfidence.medium).length})',
                  ),
                  _LegendPill(
                    color: AppTheme.lowConfidenceColor,
                    bg: AppTheme.lowConfidenceBg,
                    text: 'غير متطابق (${draft.items.where((i) => i.confidence == OcrConfidence.low).length})',
                  ),
                ],
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
              else
                for (var i = 0; i < draft.items.length; i++)
                  _ReviewItemCard(
                    key: ValueKey(draft.items[i].id),
                    item: draft.items[i],
                    onIncrement: () => _updateItem(
                      draft,
                      i,
                      draft.items[i].copyWith(
                        quantity: draft.items[i].quantity + 1,
                      ),
                    ),
                    onDecrement: () {
                      if (draft.items[i].quantity > 1) {
                        _updateItem(
                          draft,
                          i,
                          draft.items[i].copyWith(
                            quantity: draft.items[i].quantity - 1,
                          ),
                        );
                      }
                    },
                    onQuantityChanged: (qty) => _updateItem(
                      draft,
                      i,
                      draft.items[i].copyWith(quantity: qty),
                    ),
                    onEdit: () => _showEditItemDialog(draft, i, draft.items[i]),
                    onLinkToCatalog: () =>
                        _showCatalogPicker(draft: draft, replaceIndex: i),
                    onPickBrand: draft.items[i].itemTemplateId != null
                        ? () =>
                            _showPerItemBrandSheet(draft, i, draft.items[i])
                        : null,
                    onDelete: () => _removeItem(draft, i),
                  ),

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
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _saveDraft(draft, InvoiceStatus.quote),
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: const Text('حفظ عرض سعر'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _saveDraft(draft, InvoiceStatus.approved),
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(
                        'اعتماد (${InvoiceShareService.formatCurrency(draft.total)})',
                      ),
                    ),
                  ),
                ],
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

class _LegendPill extends StatelessWidget {
  const _LegendPill({
    required this.color,
    required this.bg,
    required this.text,
  });

  final Color color;
  final Color bg;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
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
    required this.onEdit,
    required this.onLinkToCatalog,
    required this.onPickBrand,
    required this.onDelete,
  });

  final InvoiceItemModel item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final ValueChanged<double> onQuantityChanged;
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.displayName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (widget.onPickBrand != null)
                  ActionChip(
                    avatar: const Icon(Icons.swap_vert, size: 15),
                    label: Text(
                      item.brandName ?? 'شركة',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onPickBrand,
                  ),
                IconButton(
                  tooltip: 'تعديل السعر/الاسم',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: widget.onEdit,
                ),
                IconButton(
                  tooltip: 'حذف البند',
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: AppTheme.lowConfidenceColor,
                  ),
                  onPressed: widget.onDelete,
                ),
              ],
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
    required this.onSave,
  });

  final InvoiceItemModel item;
  final ValueChanged<InvoiceItemModel> onSave;

  @override
  State<_EditInvoiceItemDialog> createState() => _EditInvoiceItemDialogState();
}

class _EditInvoiceItemDialogState extends State<_EditInvoiceItemDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.itemName);
    _qtyCtrl = TextEditingController(text: widget.item.quantity.toString());
    _priceCtrl = TextEditingController(text: widget.item.unitPrice.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تعديل البند'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(labelText: 'اسم الصنف'),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qtyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الكمية'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
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
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final qty =
                double.tryParse(_qtyCtrl.text.trim()) ?? widget.item.quantity;
            final price =
                double.tryParse(_priceCtrl.text.trim()) ?? widget.item.unitPrice;
            widget.onSave(
              widget.item.copyWith(
                itemName: _nameCtrl.text.trim().isEmpty
                    ? widget.item.itemName
                    : _nameCtrl.text.trim(),
                quantity: qty > 0 ? qty : 1,
                unitPrice: price >= 0 ? price : 0,
                confidence: OcrConfidence.high,
                clearNotes: true,
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
