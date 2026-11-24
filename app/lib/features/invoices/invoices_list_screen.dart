import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';

enum _InvoiceFilter { all, quotes, approved, comparisons }

class InvoicesListScreen extends ConsumerStatefulWidget {
  const InvoicesListScreen({super.key});

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesListScreenState();
}

class _InvoicesListScreenState extends ConsumerState<InvoicesListScreen> {
  _InvoiceFilter _filter = _InvoiceFilter.all;
  String _search = '';

  void _showComparisonDialog(
    BuildContext context,
    List<InvoiceModel> groupInvoices,
  ) {
    final shop = ref.read(catalogProvider).shopSettings;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مقارنة الشركات لنفس الكشف'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final inv in groupInvoices)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              inv.brandSummary ?? 'بدون شركة',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                            Text(
                              InvoiceShareService.formatCurrency(inv.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppTheme.accentColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${inv.invoiceNumber} • ${inv.items.length} بنود',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                ref
                                    .read(activeDraftProvider.notifier)
                                    .setDraft(inv);
                                context.push('/review');
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('فتح'),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  InvoiceShareService.shareInvoicePdf(
                                    invoice: inv,
                                    shop: shop,
                                  ),
                              icon: const Icon(Icons.share, size: 16),
                              label: const Text('مشاركة PDF'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => InvoiceShareService.shareComparisonPdf(
              groupInvoices: groupInvoices,
              shop: shop,
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('مشاركة المقارنة PDF'),
          ),
          TextButton.icon(
            onPressed: () => InvoiceShareService.previewOrPrintComparisonPdf(
              groupInvoices: groupInvoices,
              shop: shop,
            ),
            icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
            label: const Text('PDF مقارنة'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoicesProvider);
    final catalog = ref.watch(catalogProvider);
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

    final filtered = invoices.where((inv) {
      if (_filter == _InvoiceFilter.quotes &&
          inv.status != InvoiceStatus.quote) {
        return false;
      }
      if (_filter == _InvoiceFilter.approved &&
          inv.status != InvoiceStatus.approved) {
        return false;
      }
      if (_filter == _InvoiceFilter.comparisons &&
          inv.comparisonGroupId == null) {
        return false;
      }

      if (_search.trim().isNotEmpty) {
        final q = _search.trim().toLowerCase();
        final matchesCustomer = inv.customerName.toLowerCase().contains(q);
        final matchesNumber = inv.invoiceNumber.toLowerCase().contains(q);
        final matchesTech = (inv.technicianName ?? '').toLowerCase().contains(
          q,
        );
        final matchesBrand =
            (inv.brandSummary ?? '').toLowerCase().contains(q) ||
            inv.distinctBrandNames.any((b) => b.toLowerCase().contains(q));
        return matchesCustomer || matchesNumber || matchesTech || matchesBrand;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            children: [
              TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'بحث برقم الفاتورة، اسم العميل، الفني أو الشركة...',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _filter == _InvoiceFilter.all,
                      onSelected: (_) =>
                          setState(() => _filter = _InvoiceFilter.all),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('عروض أسعار'),
                      selected: _filter == _InvoiceFilter.quotes,
                      onSelected: (_) =>
                          setState(() => _filter = _InvoiceFilter.quotes),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('فواتير معتمدة'),
                      selected: _filter == _InvoiceFilter.approved,
                      onSelected: (_) =>
                          setState(() => _filter = _InvoiceFilter.approved),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('مقارنات الشركات'),
                      selected: _filter == _InvoiceFilter.comparisons,
                      onSelected: (_) =>
                          setState(() => _filter = _InvoiceFilter.comparisons),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('لا توجد فواتير مطابقة حالياً'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final inv = filtered[index];
                    final groupInvoices = inv.comparisonGroupId == null
                        ? const <InvoiceModel>[]
                        : invoices
                              .where(
                                (other) =>
                                    other.comparisonGroupId ==
                                    inv.comparisonGroupId,
                              )
                              .toList();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    inv.customerName.trim().isEmpty
                                        ? 'عميل نقدي'
                                        : inv.customerName.trim(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: inv.status == InvoiceStatus.approved
                                        ? AppTheme.highConfidenceBg
                                        : AppTheme.mediumConfidenceBg,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    inv.status.arabicLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          inv.status == InvoiceStatus.approved
                                          ? AppTheme.highConfidenceColor
                                          : AppTheme.mediumConfidenceColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                Text(
                                  inv.invoiceNumber,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                                if (inv.brandSummary != null)
                                  Text(
                                    'الشركة: ${inv.brandSummary}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                // Technician name is displayed ONLY when provided
                                if (inv.hasTechnician)
                                  Text(
                                    'الفني: ${inv.technicianName!.trim()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                Text(
                                  dateFmt.format(inv.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 18),
                            Row(
                              children: [
                                Text(
                                  InvoiceShareService.formatCurrency(inv.total),
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                                const Spacer(),
                                if (groupInvoices.length > 1)
                                  TextButton.icon(
                                    onPressed: () => _showComparisonDialog(
                                      context,
                                      groupInvoices,
                                    ),
                                    icon: const Icon(
                                      Icons.compare_arrows_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('مقارنة'),
                                  ),
                                IconButton(
                                  tooltip: 'تصدير PDF / طباعة',
                                  icon: const Icon(
                                    Icons.picture_as_pdf_outlined,
                                  ),
                                  onPressed: () =>
                                      InvoiceShareService.previewOrPrintPdf(
                                        invoice: inv,
                                        shop: catalog.shopSettings,
                                      ),
                                ),
                                IconButton(
                                  tooltip: 'مشاركة PDF (واتساب / تليجرام)',
                                  icon: const Icon(Icons.share_outlined),
                                  onPressed: () =>
                                      InvoiceShareService.shareInvoicePdf(
                                        invoice: inv,
                                        shop: catalog.shopSettings,
                                      ),
                                ),
                                if (catalog.isAdminMode)
                                  IconButton(
                                    tooltip: 'حذف الفاتورة',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: AppTheme.lowConfidenceColor,
                                    ),
                                    onPressed: () => ref
                                        .read(invoicesProvider.notifier)
                                        .deleteInvoice(inv.id),
                                  ),
                                ElevatedButton(
                                  onPressed: () {
                                    ref
                                        .read(activeDraftProvider.notifier)
                                        .setDraft(inv);
                                    context.push('/review');
                                  },
                                  child: const Text('مراجعة'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
