import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/features/shell/main_shell.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';

enum _ReportPeriod { today, week, month, all }

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _ReportPeriod _period = _ReportPeriod.all;

  List<InvoiceModel> _filterByPeriod(List<InvoiceModel> all) {
    final now = DateTime.now();
    return all.where((inv) {
      switch (_period) {
        case _ReportPeriod.today:
          return inv.createdAt.year == now.year &&
              inv.createdAt.month == now.month &&
              inv.createdAt.day == now.day;
        case _ReportPeriod.week:
          return now.difference(inv.createdAt).inDays < 7;
        case _ReportPeriod.month:
          return inv.createdAt.year == now.year &&
              inv.createdAt.month == now.month;
        case _ReportPeriod.all:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allInvoices = ref.watch(invoicesProvider);
    final invoices = _filterByPeriod(allInvoices);

    final approved =
        invoices.where((i) => i.status == InvoiceStatus.approved).toList();
    final quotes =
        invoices.where((i) => i.status == InvoiceStatus.quote).toList();

    final approvedTotal =
        approved.fold(0.0, (sum, inv) => sum + inv.total);
    final quotesTotal = quotes.fold(0.0, (sum, inv) => sum + inv.total);
    final conversionRate = invoices.isEmpty
        ? 0.0
        : (approved.length / invoices.length) * 100.0;

    // Staff performance aggregation
    final staffStats = <String, ({int count, double approvedSum})>{};
    for (final inv in invoices) {
      final name = inv.createdByName.trim().isEmpty
          ? 'غير معروف'
          : inv.createdByName.trim();
      final prev = staffStats[name] ?? (count: 0, approvedSum: 0.0);
      staffStats[name] = (
        count: prev.count + 1,
        approvedSum: prev.approvedSum +
            (inv.status == InvoiceStatus.approved ? inv.total : 0.0),
      );
    }

    // Top requested items aggregation (from approved invoices, or all if none)
    final sourceForItems = approved.isNotEmpty ? approved : invoices;
    final itemStats = <String, ({double qty, double revenue, String unit})>{};
    for (final inv in sourceForItems) {
      for (final item in inv.items) {
        final key = item.displayName;
        final prev =
            itemStats[key] ?? (qty: 0.0, revenue: 0.0, unit: item.unit);
        itemStats[key] = (
          qty: prev.qty + item.quantity,
          revenue: prev.revenue + item.lineTotal,
          unit: prev.unit,
        );
      }
    }
    final topItems = itemStats.entries.toList()
      ..sort((a, b) => b.value.qty.compareTo(a.value.qty));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ref.read(shellTabIndexProvider.notifier).setIndex(0);
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      },
      child: Scaffold(
      appBar: AppBar(title: const Text('تقارير المبيعات والأداء')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    ChoiceChip(
                      label: const Text('اليوم'),
                      selected: _period == _ReportPeriod.today,
                      onSelected: (_) =>
                          setState(() => _period = _ReportPeriod.today),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('آخر 7 أيام'),
                      selected: _period == _ReportPeriod.week,
                      onSelected: (_) =>
                          setState(() => _period = _ReportPeriod.week),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('هذا الشهر'),
                      selected: _period == _ReportPeriod.month,
                      onSelected: (_) =>
                          setState(() => _period = _ReportPeriod.month),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('الكل'),
                      selected: _period == _ReportPeriod.all,
                      onSelected: (_) =>
                          setState(() => _period = _ReportPeriod.all),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // KPI Grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final crossCount = constraints.maxWidth > 620 ? 4 : 2;
                  return GridView.count(
                    crossAxisCount: crossCount,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.55,
                    children: [
                      _KpiCard(
                        title: 'مبيعات معتمدة (${approved.length})',
                        value: InvoiceShareService.formatCurrency(approvedTotal),
                        color: AppTheme.highConfidenceColor,
                        icon: Icons.verified_outlined,
                      ),
                      _KpiCard(
                        title: 'عروض أسعار معلقة (${quotes.length})',
                        value: InvoiceShareService.formatCurrency(quotesTotal),
                        color: AppTheme.accentColor,
                        icon: Icons.request_quote_outlined,
                      ),
                      _KpiCard(
                        title: 'نسبة التحويل لفواتير',
                        value: '${conversionRate.toStringAsFixed(0)}%',
                        color: AppTheme.primaryColor,
                        icon: Icons.trending_up_rounded,
                      ),
                      _KpiCard(
                        title: 'إجمالي الكشوفات',
                        value: '${invoices.length}',
                        color: Colors.indigo,
                        icon: Icons.receipt_long_outlined,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),

              // Staff Performance
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'أداء الموظفين',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (staffStats.isEmpty)
                        const Text('لا توجد بيانات في هذه الفترة')
                      else
                        for (final entry in staffStats.entries)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(Icons.person_outline, size: 18),
                            ),
                            title: Text(
                              entry.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text('${entry.value.count} كشف / فاتورة'),
                            trailing: Text(
                              InvoiceShareService.formatCurrency(
                                entry.value.approvedSum,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.primaryColor,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Top Requested Items
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'الأصناف الأكثر طلباً',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (topItems.isEmpty)
                        const Text('لا توجد أصناف مباعة في هذه الفترة')
                      else
                        for (final entry in topItems.take(10))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              entry.key,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'الكمية: ${entry.value.qty} ${entry.value.unit}',
                            ),
                            trailing: Text(
                              InvoiceShareService.formatCurrency(
                                entry.value.revenue,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.highConfidenceColor,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
