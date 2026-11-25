import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/features/shell/main_shell.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';
import 'package:sanitary_pricing_app/services/scan_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isAnalyzing = false;
  String _analyzeStatus = 'جاري تجهيز الصورة...';

  Future<void> _showScanSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'تسعير ورقة جديدة بالذكاء الاصطناعي',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'اختر طريقة إدخال كشف الفني (يدعم حتى 5 صفحات لنفس الفاتورة)',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE0F2FE),
                    child: Icon(Icons.auto_awesome, color: AppTheme.primaryColor),
                  ),
                  title: const Text(
                    'تجربة كشف تجريبي جاهز (AI Demo)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'محاكاة فورية لورقة سباكة بخط اليد بألوان الثقة',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    ref.read(activeDraftProvider.notifier).startDemoScan();
                    context.push('/review');
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFDCFCE7),
                    child: Icon(Icons.camera_alt_outlined,
                        color: AppTheme.highConfidenceColor),
                  ),
                  title: const Text('تصوير بالكاميرا'),
                  subtitle: const Text('التقاط صورة مباشرة للورقة'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final img = await ScanService.pickImageFromCamera();
                    if (img != null) {
                      await _runScan([img]);
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFEDD5),
                    child: Icon(Icons.photo_library_outlined,
                        color: AppTheme.accentColor),
                  ),
                  title: const Text('رفع من المعرض / الملفات'),
                  subtitle: const Text('اختيار صورة أو أكثر لكشف الفني'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final imgs = await ScanService.pickImagesFromGallery();
                    if (imgs.isNotEmpty) {
                      await _runScan(imgs);
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runScan(List<Uint8List> images) async {
    setState(() {
      _isAnalyzing = true;
      _analyzeStatus = 'جاري رفع الصورة وقراءة البنود...';
    });
    try {
      final catalog = ref.read(catalogProvider);
      final count = ref.read(invoicesProvider).length;
      final draft = await ScanService.analyzePaperImages(
        images: images,
        catalog: catalog,
        nextInvoiceSeq: count + 1,
      );
      if (!mounted) return;
      ref.read(activeDraftProvider.notifier).setDraft(draft);
      context.push('/review');
    } on AppException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحليل الصورة حالياً، تأكد من الاتصال وحاول مجدداً'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAnalyzing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final invoices = ref.watch(invoicesProvider);

    final quotesCount =
        invoices.where((i) => i.status == InvoiceStatus.quote).length;
    final approvedInvoices =
        invoices.where((i) => i.status == InvoiceStatus.approved).toList();
    final approvedTotal =
        approvedInvoices.fold(0.0, (sum, inv) => sum + inv.total);
    final dueTodayInvoices =
        invoices.where((i) => i.isPaymentDueOrOverdue).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (dueTodayInvoices.isNotEmpty) ...[
          Card(
            key: const Key('due_payments_banner'),
            color: AppTheme.mediumConfidenceBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.notifications_active_outlined,
                        color: AppTheme.mediumConfidenceColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'تنبيهات تحصيل اليوم (${dueTodayInvoices.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppTheme.mediumConfidenceColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final dueInv in dueTodayInvoices)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'المفروض ${dueInv.customerName.trim().isEmpty ? "العميل" : dueInv.customerName.trim()} يجيب ${InvoiceShareService.formatCurrency(dueInv.remainingAmount)} النهارده',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${dueInv.invoiceNumber} • ${dueInv.paymentMethod.arabicLabel} • الموعد: ${InvoiceModel.formatDateOnly(dueInv.paymentDueDate)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        ref.read(activeDraftProvider.notifier).setDraft(dueInv);
                        context.push('/review');
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        // Hero AI Scan Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryColor, AppTheme.primaryLight],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                catalog.shopSettings.shopName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'صوّر ورقة الفني وسعّرها في ثواني',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'استخراج البنود بالذكاء الاصطناعي • ربط تلقائي بأسعار المحل • تبديل أو مقارنة الشركات بضغطة واحدة',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _isAnalyzing ? null : _showScanSheet,
                    icon: _isAnalyzing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.document_scanner_rounded),
                    label: Text(
                      _isAnalyzing
                          ? _analyzeStatus
                          : 'تسعير ورقة جديدة (AI)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      ref.read(activeDraftProvider.notifier).startBlankInvoice();
                      context.push('/review');
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('فاتورة يدوية'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => context.push('/reports'),
                    icon: const Icon(Icons.bar_chart_rounded),
                    label: const Text('التقارير'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick Stats
        LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 520;
            final cards = [
              _StatCard(
                icon: Icons.account_tree_rounded,
                label: 'الأصناف المسجلة',
                value: '${catalog.templates.length} صنف',
                color: AppTheme.primaryColor,
                onTap: () =>
                    ref.read(shellTabIndexProvider.notifier).setIndex(1),
              ),
              _StatCard(
                icon: Icons.request_quote_rounded,
                label: 'عروض أسعار',
                value: '$quotesCount عرض',
                color: AppTheme.accentColor,
                onTap: () =>
                    ref.read(shellTabIndexProvider.notifier).setIndex(2),
              ),
              _StatCard(
                icon: Icons.verified_rounded,
                label: 'مبيعات معتمدة',
                value: InvoiceShareService.formatCurrency(approvedTotal),
                color: AppTheme.highConfidenceColor,
                onTap: () =>
                    ref.read(shellTabIndexProvider.notifier).setIndex(2),
              ),
            ];

            if (isCompact) {
              return Column(
                children: [
                  for (var i = 0; i < cards.length; i++) ...[
                    cards[i],
                    if (i < cards.length - 1) const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  Expanded(child: cards[i]),
                  if (i < cards.length - 1) const SizedBox(width: 10),
                ],
              ],
            );
          },
        ),

        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'آخر الكشوفات والفواتير',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(shellTabIndexProvider.notifier).setIndex(2),
              child: const Text('عرض الكل'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final inv in invoices.take(5))
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: CircleAvatar(
                backgroundColor: inv.status == InvoiceStatus.approved
                    ? AppTheme.highConfidenceBg
                    : AppTheme.mediumConfidenceBg,
                child: Icon(
                  inv.status == InvoiceStatus.approved
                      ? Icons.check_circle_outline
                      : Icons.description_outlined,
                  color: inv.status == InvoiceStatus.approved
                      ? AppTheme.highConfidenceColor
                      : AppTheme.mediumConfidenceColor,
                ),
              ),
              title: Row(
                children: [
                  Text(
                    inv.customerName.isEmpty ? 'عميل نقدي' : inv.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 8),
                  if (inv.comparisonGroupId != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F2FE),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'مقارنة',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primaryColor,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                [
                  inv.invoiceNumber,
                  if (inv.brandSummary != null) inv.brandSummary!,
                  if (inv.hasTechnician) 'فني: ${inv.technicianName}',
                  '${inv.items.length} بنود',
                ].join(' • '),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    InvoiceShareService.formatCurrency(inv.total),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  Text(
                    inv.status.arabicLabel,
                    style: TextStyle(
                      fontSize: 11,
                      color: inv.status == InvoiceStatus.approved
                          ? AppTheme.highConfidenceColor
                          : AppTheme.mediumConfidenceColor,
                    ),
                  ),
                ],
              ),
              onTap: () {
                ref.read(activeDraftProvider.notifier).setDraft(inv);
                context.push('/review');
              },
            ),
          ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
