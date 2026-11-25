import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/services/catalog_csv_service.dart';
import 'package:sanitary_pricing_app/services/file_bytes_reader.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';

class CatalogTreeScreen extends ConsumerStatefulWidget {
  const CatalogTreeScreen({super.key});

  @override
  ConsumerState<CatalogTreeScreen> createState() => _CatalogTreeScreenState();
}

class _CatalogTreeScreenState extends ConsumerState<CatalogTreeScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showAddItemDialog() async {
    final catalog = ref.read(catalogProvider);
    if (!catalog.isAdminMode) return;
    if (catalog.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('استورد شيت Excel أو انتظر تحميل الأقسام أولاً'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => _AddItemDialog(
        categories: catalog.categories,
        brands: catalog.brands,
        onSave: ({
          required String categoryId,
          required String name,
          required String size,
          required String unit,
          required Map<String, double> brandPrices,
        }) {
          ref.read(catalogProvider.notifier).addItemTemplate(
                categoryId: categoryId,
                name: name,
                size: size,
                unit: unit,
                brandPrices: brandPrices,
              );
        },
      ),
    );
  }

  Future<void> _showEditPriceDialog(
    ItemTemplateModel template,
    BrandModel brand,
    ProductVariantModel? currentVariant,
  ) async {
    final catalog = ref.read(catalogProvider);
    if (!catalog.isAdminMode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعديل الأسعار متاح لحساب المدير فقط'),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => _EditPriceDialog(
        template: template,
        brand: brand,
        currentPrice: currentVariant?.price,
        currentCommercialPrice: currentVariant?.commercialPrice,
        onSave: (sellingPrice, commercialPrice) {
          ref.read(catalogProvider.notifier).upsertVariantPrice(
                itemTemplateId: template.id,
                brandId: brand.id,
                price: sellingPrice,
                commercialPrice: commercialPrice,
                clearCommercialPrice: commercialPrice == null,
              );
        },
      ),
    );
  }

  Future<void> _showExcelImportExportDialog() async {
    final catalog = ref.read(catalogProvider);
    if (!catalog.isAdminMode) return;
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExcelImportExportDialog(
        catalog: catalog,
        onImported: (count) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('تم استيراد وتحديث $count سعر/صنف بنجاح'),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showManageCategoriesBrandsDialog() async {
    final catalog = ref.read(catalogProvider);
    if (!catalog.isAdminMode) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => const _ManageCategoriesBrandsDialog(),
    );
  }

  Future<void> _showUpdateProfitDialog() async {
    final catalog = ref.read(catalogProvider);
    if (!catalog.isAdminMode) return;
    final messenger = ScaffoldMessenger.of(context);

    await showDialog<void>(
      context: context,
      builder: (ctx) => _UpdateProfitDialog(
        initialBrandId: catalog.selectedBrandId,
        onApplied: (count) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'تم تحديث سعر البيع لـ $count صنف بناءً على السعر التجاري',
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final filtered = catalog.filteredTemplates;

    // Group templates by category to form the Product Tree
    final grouped = <CategoryModel, List<ItemTemplateModel>>{};
    for (final cat in catalog.categories) {
      final items = filtered.where((t) => t.categoryId == cat.id).toList();
      if (items.isNotEmpty) {
        grouped[cat] = items;
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: catalog.isAdminMode
          ? FloatingActionButton.extended(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            )
          : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (v) => ref
                            .read(catalogProvider.notifier)
                            .setSearchQuery(v),
                        decoration: InputDecoration(
                          hintText:
                              'ابحث باسم الصنف أو المقاس أو مسمى الفني (مثلاً: كوع نص)...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _searchController.clear();
                                    ref
                                        .read(catalogProvider.notifier)
                                        .setSearchQuery('');
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    if (catalog.isAdminMode) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('update_profit_button'),
                        tooltip: 'تعديل نسبة الربح',
                        onPressed: _showUpdateProfitDialog,
                        icon: const Icon(Icons.percent_rounded),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'استيراد / تصدير Excel',
                        onPressed: _showExcelImportExportDialog,
                        icon: const Icon(Icons.table_chart_outlined),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'الأقسام والشركات',
                        onPressed: _showManageCategoriesBrandsDialog,
                        icon: const Icon(Icons.category_outlined),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                // Category filter tree chips
                SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ChoiceChip(
                        label: const Text('كل الأقسام'),
                        selected: catalog.selectedCategoryId == null,
                        onSelected: (_) => ref
                            .read(catalogProvider.notifier)
                            .setSelectedCategory(null),
                      ),
                      const SizedBox(width: 8),
                      for (final cat in catalog.categories) ...[
                        ChoiceChip(
                          label: Text(cat.name),
                          selected: catalog.selectedCategoryId == cat.id,
                          onSelected: (_) => ref
                              .read(catalogProvider.notifier)
                              .setSelectedCategory(
                                catalog.selectedCategoryId == cat.id
                                    ? null
                                    : cat.id,
                              ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Brand filter chips
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      FilterChip(
                        label: const Text('كل الشركات'),
                        selected: catalog.selectedBrandId == null,
                        onSelected: (_) => ref
                            .read(catalogProvider.notifier)
                            .setSelectedBrand(null),
                      ),
                      const SizedBox(width: 8),
                      for (final brand in catalog.brands) ...[
                        FilterChip(
                          label: Text(brand.name),
                          selected: catalog.selectedBrandId == brand.id,
                          onSelected: (_) => ref
                              .read(catalogProvider.notifier)
                              .setSelectedBrand(
                                catalog.selectedBrandId == brand.id
                                    ? null
                                    : brand.id,
                              ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!catalog.isAdminMode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'وضع البائع: يمكنك البحث واستعراض الأسعار فقط. تعديل الأسعار متاح للمدير.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          Expanded(
            child: grouped.isEmpty
                ? const Center(
                    child: Text('لا توجد أصناف مطابقة للبحث الحالي'),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
                    children: [
                      for (final entry in grouped.entries)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            shape: const Border(),
                            leading: const Icon(
                              Icons.folder_open_rounded,
                              color: AppTheme.primaryColor,
                            ),
                            title: Text(
                              '${entry.key.name} (${entry.value.length})',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            children: [
                              const Divider(height: 1),
                              for (final template in entry.value)
                                _ProductTreeItemTile(
                                  template: template,
                                  catalog: catalog,
                                  onEditPrice: _showEditPriceDialog,
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProductTreeItemTile extends StatelessWidget {
  const _ProductTreeItemTile({
    required this.template,
    required this.catalog,
    required this.onEditPrice,
  });

  final ItemTemplateModel template;
  final CatalogState catalog;
  final Future<void> Function(
    ItemTemplateModel template,
    BrandModel brand,
    ProductVariantModel? currentVariant,
  ) onEditPrice;

  @override
  Widget build(BuildContext context) {
    final brandsToShow = catalog.selectedBrandId != null
        ? catalog.brands
            .where((b) => b.id == catalog.selectedBrandId)
            .toList()
        : catalog.brands;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (template.size != null && template.size!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    template.size!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                '(${template.unit})',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final brand in brandsToShow)
                Builder(
                  builder: (context) {
                    final variant = catalog.findVariant(template.id, brand.id);
                    return ActionChip(
                      avatar: Icon(
                        variant != null
                            ? Icons.sell_outlined
                            : Icons.add_circle_outline,
                        size: 16,
                        color: variant != null
                            ? AppTheme.primaryColor
                            : Colors.grey,
                      ),
                      label: Text(
                        variant != null
                            ? (variant.commercialPrice != null
                                ? '${brand.name}: بيع ${InvoiceShareService.formatCurrency(variant.price)} | تجاري ${InvoiceShareService.formatCurrency(variant.commercialPrice!)}'
                                : '${brand.name}: ${InvoiceShareService.formatCurrency(variant.price)}')
                            : '${brand.name}: غير مسعر',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: variant != null
                              ? Colors.black87
                              : Colors.grey.shade600,
                        ),
                      ),
                      onPressed: () =>
                          onEditPrice(template, brand, variant),
                    );
                  },
                ),
            ],
          ),
          const Divider(height: 18),
        ],
      ),
    );
  }
}

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.categories,
    required this.brands,
    required this.onSave,
  });

  final List<CategoryModel> categories;
  final List<BrandModel> brands;
  final void Function({
    required String categoryId,
    required String name,
    required String size,
    required String unit,
    required Map<String, double> brandPrices,
  }) onSave;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _nameCtrl = TextEditingController();
  final _sizeCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: 'قطعة');
  late String _selectedCatId;
  late final Map<String, TextEditingController> _priceControllers;

  @override
  void initState() {
    super.initState();
    _selectedCatId = widget.categories.first.id;
    _priceControllers = {
      for (final b in widget.brands) b.id: TextEditingController(),
    };
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sizeCtrl.dispose();
    _unitCtrl.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إضافة صنف جديد للشجرة'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _selectedCatId,
              decoration: const InputDecoration(labelText: 'القسم / النوع'),
              items: [
                for (final cat in widget.categories)
                  DropdownMenuItem(value: cat.id, child: Text(cat.name)),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedCatId = val);
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'اسم الصنف *',
                hintText: 'مثال: كوع لحام',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sizeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'المقاس',
                      hintText: '1/2 بوصة',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _unitCtrl,
                    decoration: const InputDecoration(labelText: 'الوحدة'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'الأسعار حسب الشركة (ج.م):',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            for (final brand in widget.brands) ...[
              TextField(
                controller: _priceControllers[brand.id],
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'سعر ${brand.name}',
                  hintText: 'اتركه فارغاً إذا لم يتوفر',
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.isEmpty) return;
            final brandPrices = <String, double>{};
            _priceControllers.forEach((brandId, ctrl) {
              final parsed = double.tryParse(ctrl.text.trim());
              if (parsed != null && parsed >= 0) {
                brandPrices[brandId] = parsed;
              }
            });
            widget.onSave(
              categoryId: _selectedCatId,
              name: name,
              size: _sizeCtrl.text,
              unit: _unitCtrl.text,
              brandPrices: brandPrices,
            );
            Navigator.pop(context);
          },
          child: const Text('حفظ الصنف'),
        ),
      ],
    );
  }
}

class _EditPriceDialog extends StatefulWidget {
  const _EditPriceDialog({
    required this.template,
    required this.brand,
    required this.currentPrice,
    required this.currentCommercialPrice,
    required this.onSave,
  });

  final ItemTemplateModel template;
  final BrandModel brand;
  final double? currentPrice;
  final double? currentCommercialPrice;
  final void Function(double sellingPrice, double? commercialPrice) onSave;

  @override
  State<_EditPriceDialog> createState() => _EditPriceDialogState();
}

class _EditPriceDialogState extends State<_EditPriceDialog> {
  late final TextEditingController _ctrl;
  late final TextEditingController _commercialCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.currentPrice != null
          ? widget.currentPrice!.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '')
          : '',
    );
    _commercialCtrl = TextEditingController(
      text: widget.currentCommercialPrice != null
          ? widget.currentCommercialPrice!
              .toStringAsFixed(2)
              .replaceFirst(RegExp(r'\.00$'), '')
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _commercialCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تعديل سعر ${widget.brand.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.template.displayLabel),
          const SizedBox(height: 12),
          TextField(
            controller: _commercialCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'السعر التجاري (ج.م) — اختياري',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'سعر البيع (ج.م) *'),
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
            final parsed = double.tryParse(_ctrl.text.trim());
            final rawComm = _commercialCtrl.text.trim();
            final parsedComm = rawComm.isEmpty ? null : double.tryParse(rawComm);
            if (rawComm.isNotEmpty && (parsedComm == null || parsedComm < 0)) {
              return;
            }
            if (parsed != null && parsed >= 0) {
              widget.onSave(parsed, parsedComm);
              Navigator.pop(context);
            }
          },
          child: const Text('تحديث السعر'),
        ),
      ],
    );
  }
}

class _ExcelImportExportDialog extends ConsumerStatefulWidget {
  const _ExcelImportExportDialog({
    required this.catalog,
    required this.onImported,
  });

  final CatalogState catalog;
  final ValueChanged<int> onImported;

  @override
  ConsumerState<_ExcelImportExportDialog> createState() =>
      _ExcelImportExportDialogState();
}

class _ExcelImportExportDialogState
    extends ConsumerState<_ExcelImportExportDialog> {
  final _pasteCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _markupCtrl = TextEditingController();
  ImportPriceMode? _priceMode;
  var _applyCompanyDiscount = false;
  ProfitMarkupType _markupType = ProfitMarkupType.percent;
  var _parsed = const CatalogCsvParseResult(rows: [], skippedLines: 0);
  var _isImporting = false;
  String? _selectedFileName;
  String? _fileError;

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _discountCtrl.dispose();
    _markupCtrl.dispose();
    super.dispose();
  }

  double? get _validDiscountPercent {
    final val = _parseProfitMarkupValue(_discountCtrl.text);
    if (val == null || val >= 100) return null;
    return val;
  }

  bool get _isDiscountValid =>
      !_applyCompanyDiscount || _validDiscountPercent != null;

  double get _effectiveDiscountPercent =>
      _applyCompanyDiscount ? (_validDiscountPercent ?? 0) : 0;

  double? get _validMarkupValue => _parseProfitMarkupValue(_markupCtrl.text);

  Future<Uint8List?> _resolvePickedFileBytes(PlatformFile picked) async {
    if (picked.bytes != null && picked.bytes!.isNotEmpty) {
      return picked.bytes;
    }
    if (picked.path != null && picked.path!.trim().isNotEmpty) {
      final fromPath = await readFileBytesFromPath(picked.path!);
      if (fromPath != null && fromPath.isNotEmpty) {
        return fromPath;
      }
    }
    final stream = picked.readStream;
    if (stream != null) {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      final collected = builder.takeBytes();
      if (collected.isNotEmpty) {
        return collected;
      }
    }
    return null;
  }

  Future<void> _pickSpreadsheetFile() async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['xlsx', 'csv', 'tsv', 'txt'],
          withData: true,
        );
      } on PlatformException {
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: true,
        );
      }
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = await _resolvePickedFileBytes(picked);
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        setState(() => _fileError = 'تعذر قراءة محتوى الملف المختار');
        return;
      }

      final parsed = CatalogCsvService.parseUploadedFile(
        fileName: picked.name,
        bytes: bytes,
      );
      _pasteCtrl.clear();
      if (!mounted) return;
      setState(() {
        _selectedFileName = picked.name;
        _parsed = parsed;
        _fileError = parsed.rows.isEmpty
            ? 'لم يتم العثور على صفوف أسعار صالحة في الملف'
            : null;
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _fileError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _fileError =
            'تعذر قراءة ملف Excel/CSV (${e.runtimeType})، تأكد من أنه بصيغة .xlsx أو .csv سليمة',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasInput =
        _selectedFileName != null || _pasteCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: const Text('استيراد وتصدير Excel / CSV'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ارفع ملف Excel (.xlsx) أو CSV بالأسعار التجارية، أو الصق الصفوف بالترتيب:\nالقسم ، اسم الصنف ، المقاس ، الوحدة ، الشركة ، السعر التجاري',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _isImporting ? null : _pickSpreadsheetFile,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('اختيار ملف Excel / CSV'),
              ),
              if (_selectedFileName != null) ...[
                const SizedBox(height: 8),
                Chip(
                  avatar: const Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: AppTheme.primaryColor,
                  ),
                  label: Text(_selectedFileName!),
                  deleteIcon: const Icon(Icons.close, size: 18),
                  onDeleted: _isImporting
                      ? null
                      : () {
                          setState(() {
                            _selectedFileName = null;
                            _parsed = const CatalogCsvParseResult(
                              rows: [],
                              skippedLines: 0,
                            );
                          });
                        },
                ),
              ],
              if (_fileError != null) ...[
                const SizedBox(height: 6),
                Text(
                  _fileError!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lowConfidenceColor,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isImporting
                        ? null
                        : () {
                            _pasteCtrl.text = CatalogCsvService.sampleTemplate;
                            setState(() {
                              _selectedFileName = null;
                              _fileError = null;
                              _parsed = CatalogCsvService.parseImportText(
                                _pasteCtrl.text,
                              );
                            });
                          },
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text('إدراج نموذج جاهز'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isImporting
                        ? null
                        : () async {
                            final csv = CatalogCsvService.exportCatalogCsv(
                              widget.catalog,
                            );
                            await Clipboard.setData(ClipboardData(text: csv));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تم نسخ جدول الأصناف بالكامل بصيغة CSV — الصقه في Excel',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.copy_all_outlined, size: 18),
                    label: const Text('تصدير / نسخ لـ Excel'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pasteCtrl,
                maxLines: 5,
                onChanged: (val) {
                  setState(() {
                    _selectedFileName = null;
                    _fileError = null;
                    _parsed = CatalogCsvService.parseImportText(val);
                  });
                },
                decoration: const InputDecoration(
                  hintText: 'أو الصق هنا: تغذية (بولي),كوع لحام,1/2 بوصة,قطعة,الشريف,18',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 8),
              if (hasInput) ...[
                Text(
                  'صفوف صالحة للاستيراد: ${_parsed.rows.length} | صفوف متجاهلة: ${_parsed.skippedLines}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _parsed.rows.isNotEmpty
                        ? AppTheme.highConfidenceColor
                        : AppTheme.lowConfidenceColor,
                  ),
                ),
                if (_parsed.rows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _priceMode == null
                            ? AppTheme.lowConfidenceColor.withValues(alpha: 0.6)
                            : AppTheme.primaryColor.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'نوع الأسعار في الملف (إجباري):',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              key: const Key('import_price_mode_commercial'),
                              label: Text(ImportPriceMode.commercial.arabicLabel),
                              selected: _priceMode == ImportPriceMode.commercial,
                              onSelected: _isImporting
                                  ? null
                                  : (_) => setState(
                                        () => _priceMode =
                                            ImportPriceMode.commercial,
                                      ),
                            ),
                            ChoiceChip(
                              key: const Key('import_price_mode_selling'),
                              label: Text(ImportPriceMode.selling.arabicLabel),
                              selected: _priceMode == ImportPriceMode.selling,
                              onSelected: _isImporting
                                  ? null
                                  : (_) => setState(
                                        () =>
                                            _priceMode = ImportPriceMode.selling,
                                      ),
                            ),
                          ],
                        ),
                        if (_priceMode == null) ...[
                          const SizedBox(height: 6),
                          const Text(
                            'مطلوب تحديد هل الأسعار تجارية أم أسعار بيع قبل الاستيراد',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.lowConfidenceColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (_priceMode == ImportPriceMode.commercial) ...[
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.amber.withValues(alpha: 0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: !_isDiscountValid
                              ? AppTheme.lowConfidenceColor.withValues(alpha: 0.6)
                              : Colors.amber.shade700.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CheckboxListTile(
                              key: const Key('company_discount_toggle'),
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _applyCompanyDiscount,
                              onChanged: _isImporting
                                  ? null
                                  : (v) => setState(
                                        () =>
                                            _applyCompanyDiscount = v ?? false,
                                      ),
                              title: const Text(
                                'القائمة بأسعار الشركة (تطبيق خصم الشركة)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: const Text(
                                'يتم خصم نسبة الشركة أولاً لحساب السعر التجاري، ثم إضافة الربح عليه',
                                style: TextStyle(fontSize: 11),
                              ),
                            ),
                            if (_applyCompanyDiscount) ...[
                              const SizedBox(height: 6),
                              TextField(
                                key: const Key('company_discount_field'),
                                controller: _discountCtrl,
                                enabled: !_isImporting,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'نسبة خصم الشركة (%) *',
                                  hintText: 'مثال: 15',
                                ),
                              ),
                              if (_validDiscountPercent == null) ...[
                                const SizedBox(height: 6),
                                const Text(
                                  'أدخل نسبة خصم صحيحة (من 0 إلى أقل من 100%)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.lowConfidenceColor,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _validMarkupValue == null
                              ? AppTheme.lowConfidenceColor.withValues(alpha: 0.5)
                              : AppTheme.primaryColor.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'إعداد نسبة / قيمة المكسب على الأسعار التجارية (إجباري):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryColor,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              for (final type in ProfitMarkupType.values)
                                ChoiceChip(
                                  label: Text(type.arabicLabel),
                                  selected: _markupType == type,
                                  onSelected: _isImporting
                                      ? null
                                      : (_) =>
                                          setState(() => _markupType = type),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const Key('profit_markup_field'),
                            controller: _markupCtrl,
                            enabled: !_isImporting,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: _markupType == ProfitMarkupType.percent
                                  ? 'نسبة المكسب (%) *'
                                  : 'قيمة المكسب الثابتة (ج.م) *',
                              hintText: _markupType == ProfitMarkupType.percent
                                  ? 'مثال: 20'
                                  : 'مثال: 10',
                            ),
                          ),
                          if (_validMarkupValue == null) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'مطلوب إدخال قيمة المكسب لحساب سعر البيع قبل الاستيراد',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.lowConfidenceColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final r in _parsed.rows.take(3)) ...[
                      Builder(
                        builder: (_) {
                          final effectiveCommercial = _effectiveDiscountPercent >
                                  0
                              ? calculateDiscountedCommercialPrice(
                                  r.price,
                                  _effectiveDiscountPercent,
                                )
                              : r.price;
                          final prefix =
                              '• ${r.itemName}${r.size != null ? " (${r.size})" : ""} — ${r.brandName}: ';
                          final pricePart = _effectiveDiscountPercent > 0
                              ? 'قائمة ${InvoiceShareService.formatCurrency(r.price)} ← تجاري ${InvoiceShareService.formatCurrency(effectiveCommercial)}'
                              : 'تجاري ${InvoiceShareService.formatCurrency(effectiveCommercial)}';
                          final sellingPart = _validMarkupValue != null
                              ? ' | بيع ${InvoiceShareService.formatCurrency(calculateSellingPrice(effectiveCommercial, _markupType, _validMarkupValue!))}'
                              : '';
                          return Text(
                            '$prefix$pricePart$sellingPart',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade700,
                            ),
                          );
                        },
                      ),
                    ],
                  ] else if (_priceMode == ImportPriceMode.selling) ...[
                    const SizedBox(height: 8),
                    for (final r in _parsed.rows.take(3))
                      Text(
                        '• ${r.itemName}${r.size != null ? " (${r.size})" : ""} — ${r.brandName}: سعر البيع ${InvoiceShareService.formatCurrency(r.price)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
        ElevatedButton.icon(
          onPressed: _isImporting ||
                  _parsed.rows.isEmpty ||
                  _priceMode == null ||
                  (_priceMode == ImportPriceMode.commercial &&
                      (_validMarkupValue == null || !_isDiscountValid))
              ? null
              : () async {
                  final mode = _priceMode;
                  if (mode == null) return;
                  final markupValue = _validMarkupValue ?? 0;
                  if (mode == ImportPriceMode.commercial &&
                      (_validMarkupValue == null || !_isDiscountValid)) {
                    return;
                  }
                  setState(() => _isImporting = true);
                  try {
                    final count = await ref
                        .read(catalogProvider.notifier)
                        .importCatalogRows(
                          _parsed.rows,
                          priceMode: mode,
                          markupType: _markupType,
                          markupValue: markupValue,
                          companyDiscountPercent:
                              mode == ImportPriceMode.commercial
                                  ? _effectiveDiscountPercent
                                  : 0,
                        );
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    widget.onImported(count);
                  } catch (_) {
                    if (context.mounted) {
                      setState(() => _isImporting = false);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('حدث خطأ أثناء استيراد البيانات'),
                        ),
                      );
                    }
                  }
                },
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(
            _isImporting ? 'جاري الاستيراد...' : 'استيراد للكتالوج',
          ),
        ),
      ],
    );
  }
}

class _ManageCategoriesBrandsDialog extends ConsumerStatefulWidget {
  const _ManageCategoriesBrandsDialog();

  @override
  ConsumerState<_ManageCategoriesBrandsDialog> createState() =>
      _ManageCategoriesBrandsDialogState();
}

class _ManageCategoriesBrandsDialogState
    extends ConsumerState<_ManageCategoriesBrandsDialog> {
  final _catCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  BrandTier _selectedTier = BrandTier.mid;

  @override
  void dispose() {
    _catCtrl.dispose();
    _brandCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);

    return AlertDialog(
      title: const Text('إدارة الأقسام والشركات'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'الأقسام الحالية:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final cat in catalog.categories)
                    Chip(label: Text(cat.name)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _catCtrl,
                      decoration: const InputDecoration(
                        labelText: 'قسم جديد',
                        hintText: 'مثال: عدد وأدوات',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final text = _catCtrl.text.trim();
                      if (text.isEmpty) return;
                      await ref.read(catalogProvider.notifier).addCategory(text);
                      _catCtrl.clear();
                    },
                    child: const Text('إضافة'),
                  ),
                ],
              ),
              const Divider(height: 24),
              const Text(
                'الشركات / الماركات الحالية:',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final b in catalog.brands)
                    Chip(label: Text('${b.name} (${b.tier.arabicLabel})')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _brandCtrl,
                decoration: const InputDecoration(
                  labelText: 'شركة جديدة',
                  hintText: 'مثال: باننجر / جروهي',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<BrandTier>(
                      initialValue: _selectedTier,
                      decoration: const InputDecoration(labelText: 'الفئة'),
                      items: [
                        for (final t in BrandTier.values)
                          DropdownMenuItem(value: t, child: Text(t.arabicLabel)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _selectedTier = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final text = _brandCtrl.text.trim();
                      if (text.isEmpty) return;
                      await ref.read(catalogProvider.notifier).addBrand(
                            name: text,
                            tier: _selectedTier,
                          );
                      _brandCtrl.clear();
                    },
                    child: const Text('إضافة'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}

double? _parseProfitMarkupValue(String rawInput) {
  final raw = rawInput.trim();
  if (raw.isEmpty) return null;
  const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
  final normalized = raw
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (m) => arabicDigits.indexOf(m.group(0)!).toString(),
      )
      .replaceAll('،', '.')
      .replaceAll(',', '.');
  final val = double.tryParse(normalized);
  if (val == null || val < 0) return null;
  return val;
}

String _formatCompactNumber(double value) {
  final rounded = (value * 10).round() / 10.0;
  if (rounded == rounded.roundToDouble()) {
    return rounded.toInt().toString();
  }
  return rounded.toString();
}

String? _summarizeCurrentProfit(List<ProductVariantModel> variants) {
  if (variants.isEmpty) return null;

  if (variants.length == 1) {
    final c = variants.first.commercialPrice!;
    final diff = variants.first.price - c;
    if (c > 0) {
      final pct = (diff / c) * 100.0;
      return 'الربح الحالي: ${_formatCompactNumber(pct)}% (+${InvoiceShareService.formatCurrency(diff)})';
    }
    return 'الربح الحالي: مبلغ ثابت ${InvoiceShareService.formatCurrency(diff)}';
  }

  final diffs = <double>[];
  final pcts = <double>[];
  for (final v in variants) {
    final c = v.commercialPrice!;
    final diff = v.price - c;
    diffs.add(diff);
    if (c > 0) {
      pcts.add((diff / c) * 100.0);
    }
  }

  var minDiff = diffs.first;
  var maxDiff = diffs.first;
  var sumDiff = 0.0;
  for (final d in diffs) {
    if (d < minDiff) minDiff = d;
    if (d > maxDiff) maxDiff = d;
    sumDiff += d;
  }
  final avgDiff = sumDiff / diffs.length;

  var minPct = 0.0;
  var maxPct = 0.0;
  var avgPct = 0.0;
  if (pcts.isNotEmpty) {
    minPct = pcts.first;
    maxPct = pcts.first;
    var sumPct = 0.0;
    for (final p in pcts) {
      if (p < minPct) minPct = p;
      if (p > maxPct) maxPct = p;
      sumPct += p;
    }
    avgPct = sumPct / pcts.length;
  }

  if (pcts.length == variants.length && (maxPct - minPct) <= 0.6) {
    return 'الربح الحالي: نسبة مئوية ${_formatCompactNumber(avgPct)}%';
  }
  if ((maxDiff - minDiff) <= 0.05) {
    return 'الربح الحالي: مبلغ ثابت ${InvoiceShareService.formatCurrency(avgDiff)}';
  }
  if (pcts.isNotEmpty) {
    return 'الربح الحالي: متفاوت (من ${_formatCompactNumber(minPct)}% إلى ${_formatCompactNumber(maxPct)}%)';
  }
  return 'الربح الحالي: متفاوت (من ${InvoiceShareService.formatCurrency(minDiff)} إلى ${InvoiceShareService.formatCurrency(maxDiff)})';
}

class _UpdateProfitDialog extends ConsumerStatefulWidget {
  const _UpdateProfitDialog({
    required this.onApplied,
    this.initialBrandId,
  });

  final String? initialBrandId;
  final ValueChanged<int> onApplied;

  @override
  ConsumerState<_UpdateProfitDialog> createState() =>
      _UpdateProfitDialogState();
}

class _UpdateProfitDialogState extends ConsumerState<_UpdateProfitDialog> {
  final _markupCtrl = TextEditingController();
  late String? _selectedBrandId = widget.initialBrandId;
  ProfitMarkupType _markupType = ProfitMarkupType.percent;
  bool _isSaving = false;

  @override
  void dispose() {
    _markupCtrl.dispose();
    super.dispose();
  }

  double? get _validMarkupValue => _parseProfitMarkupValue(_markupCtrl.text);

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final validBrandIds = {for (final b in catalog.brands) b.id};

    final effectiveBrandId =
        _selectedBrandId != null && validBrandIds.contains(_selectedBrandId)
            ? _selectedBrandId
            : null;

    final templateById = {for (final t in catalog.templates) t.id: t};
    final brandById = {for (final b in catalog.brands) b.id: b};

    final scopedVariants = [
      for (final v in catalog.variants)
        if (effectiveBrandId == null || v.brandId == effectiveBrandId) v,
    ];
    final matchingVariants = [
      for (final v in scopedVariants)
        if (v.commercialPrice != null) v,
    ];
    final skippedWithoutCommercial =
        scopedVariants.length - matchingVariants.length;

    final currentProfitSummary = _summarizeCurrentProfit(matchingVariants);
    final markupValue = _validMarkupValue;

    return AlertDialog(
      title: const Text('تعديل نسبة / قيمة الربح'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إعادة حساب سعر البيع تلقائياً من السعر التجاري المسجل لجميع أصناف الشركة المختارة، دون التأثير على الفواتير المحفوظة مسبقاً.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: effectiveBrandId,
                decoration: const InputDecoration(labelText: 'الشركة'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('كل الشركات'),
                  ),
                  for (final b in catalog.brands)
                    DropdownMenuItem<String?>(
                      value: b.id,
                      child: Text(b.name),
                    ),
                ],
                onChanged: _isSaving
                    ? null
                    : (v) => setState(() => _selectedBrandId = v),
              ),
              if (currentProfitSummary != null) ...[
                const SizedBox(height: 10),
                Container(
                  key: const Key('current_profit_info'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 18,
                        color: AppTheme.primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentProfitSummary,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final type in ProfitMarkupType.values)
                    ChoiceChip(
                      label: Text(type.arabicLabel),
                      selected: _markupType == type,
                      onSelected: _isSaving
                          ? null
                          : (_) => setState(() => _markupType = type),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const Key('bulk_profit_markup_field'),
                controller: _markupCtrl,
                enabled: !_isSaving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _markupType == ProfitMarkupType.percent
                      ? 'نسبة الربح الجديدة (%) *'
                      : 'قيمة الربح الثابتة الجديدة (ج.م) *',
                  hintText: _markupType == ProfitMarkupType.percent
                      ? 'مثال: 25'
                      : 'مثال: 15',
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: matchingVariants.isNotEmpty
                      ? AppTheme.primaryColor.withValues(alpha: 0.06)
                      : AppTheme.lowConfidenceColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: matchingVariants.isNotEmpty
                        ? AppTheme.primaryColor.withValues(alpha: 0.25)
                        : AppTheme.lowConfidenceColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      matchingVariants.isNotEmpty
                          ? 'سيتم تحديث ${matchingVariants.length} سعر بناءً على السعر التجاري المسجل'
                          : 'لا توجد أصناف لها سعر تجاري مسجل ضمن النطاق المختار',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: matchingVariants.isNotEmpty
                            ? AppTheme.highConfidenceColor
                            : AppTheme.lowConfidenceColor,
                      ),
                    ),
                    if (skippedWithoutCommercial > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'سيتم تخطي $skippedWithoutCommercial سعر بدون سعر تجاري مسجل.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (matchingVariants.isNotEmpty && markupValue != null) ...[
                const SizedBox(height: 10),
                for (final v in matchingVariants.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '• ${templateById[v.itemTemplateId]?.displayLabel ?? "صنف"} — ${brandById[v.brandId]?.name ?? ""}: تجاري ${InvoiceShareService.formatCurrency(v.commercialPrice!)} ← بيع جديد ${InvoiceShareService.formatCurrency(calculateSellingPrice(v.commercialPrice!, _markupType, markupValue))}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton.icon(
          key: const Key('apply_profit_button'),
          onPressed:
              _isSaving || matchingVariants.isEmpty || markupValue == null
                  ? null
                  : () async {
                      setState(() => _isSaving = true);
                      try {
                        final count = await ref
                            .read(catalogProvider.notifier)
                            .applyProfitMarkup(
                              markupType: _markupType,
                              markupValue: markupValue,
                              brandId: effectiveBrandId,
                            );
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        widget.onApplied(count);
                      } catch (_) {
                        if (context.mounted) {
                          setState(() => _isSaving = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تعذر تحديث نسبة الربح، حاول مجدداً'),
                            ),
                          );
                        }
                      }
                    },
          icon: const Icon(Icons.check_circle_outline),
          label: Text(_isSaving ? 'جاري التحديث...' : 'تطبيق على الأسعار'),
        ),
      ],
    );
  }
}
