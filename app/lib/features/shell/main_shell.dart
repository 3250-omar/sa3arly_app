import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/features/catalog/catalog_tree_screen.dart';
import 'package:sanitary_pricing_app/features/dashboard/dashboard_screen.dart';
import 'package:sanitary_pricing_app/features/invoices/invoices_list_screen.dart';
import 'package:sanitary_pricing_app/features/settings/settings_screen.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/providers/notifications_provider.dart';
import 'package:sanitary_pricing_app/services/payment_reminder_service.dart';

final shellTabIndexProvider = NotifierProvider<ShellTabNotifier, int>(
  ShellTabNotifier.new,
);

class ShellTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) {
    state = index;
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  StreamSubscription<String>? _notifSub;
  DateTime? _lastHomeBackPressAt;

  void _handleSystemBack(int currentIndex) {
    if (currentIndex != 0) {
      ref.read(shellTabIndexProvider.notifier).setIndex(0);
      return;
    }

    final now = DateTime.now();
    if (_lastHomeBackPressAt == null ||
        now.difference(_lastHomeBackPressAt!) > const Duration(seconds: 2)) {
      _lastHomeBackPressAt = now;
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('اضغط رجوع مرة أخرى للخروج من التطبيق'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    SystemNavigator.pop();
  }

  static const List<Widget> _pages = [
    DashboardScreen(),
    CatalogTreeScreen(),
    InvoicesListScreen(),
    SettingsScreen(),
  ];

  static const List<String> _titles = [
    'الرئيسية',
    'شجرة الأصناف والأسعار',
    'الفواتير وعروض الأسعار',
    'الإعدادات والصلاحيات',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notifSub = PaymentReminderService.onNotificationTap.listen(
      _handleNotificationPayload,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchPayload = PaymentReminderService.consumeLaunchPayload();
      if (launchPayload != null) {
        _handleNotificationPayload(launchPayload);
      }
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !AppConfig.isDemoMode) {
      final catalog = ref.read(catalogProvider);
      final invoiceSync = ref.read(invoicesSyncProvider);
      if (catalog.isOffline ||
          invoiceSync.isOffline ||
          invoiceSync.pendingCount > 0) {
        unawaited(_syncAll());
      }
    }
  }

  void _handleNotificationPayload(String payload) {
    if (!mounted || payload.trim().isEmpty) return;
    final parts = payload.split('|');
    String? notifId;
    late final String invoiceId;
    if (parts.length >= 2) {
      notifId = parts[0];
      invoiceId = parts[1];
    } else {
      invoiceId = parts[0];
    }

    if (notifId != null && notifId.isNotEmpty) {
      ref.read(notificationsProvider.notifier).markAsRead(notifId);
    } else {
      ref
          .read(notificationsProvider.notifier)
          .markInvoiceNotificationsRead(invoiceId);
    }

    final invoices = ref.read(invoicesProvider);
    final match = invoices.where((inv) => inv.id == invoiceId).firstOrNull;
    if (match != null) {
      ref.read(activeDraftProvider.notifier).setDraft(match);
      context.push('/review');
    }
  }

  Future<void> _syncAll() async {
    await Future.wait([
      ref.read(catalogProvider.notifier).syncFromSupabase(),
      ref.read(invoicesProvider.notifier).syncFromSupabase(),
    ]);
  }

  Future<void> _openNotificationsPopover(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final notifications = dialogRef.watch(notificationsProvider);
          final unreadCount = dialogRef.watch(unreadNotificationsCountProvider);

          return Align(
            alignment: AlignmentDirectional.topEnd,
            child: Padding(
              padding: const EdgeInsets.only(
                top: kToolbarHeight + 10,
                left: 12,
                right: 12,
              ),
              child: Material(
                key: const Key('notifications_popover'),
                elevation: 10,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(ctx).colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 360,
                    maxHeight: 440,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.06),
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_rounded,
                              size: 20,
                              color: AppTheme.primaryColor,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'الإشعارات',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (unreadCount > 0)
                              TextButton(
                                key: const Key('mark_all_notifications_read'),
                                onPressed: () => dialogRef
                                    .read(notificationsProvider.notifier)
                                    .markAllAsRead(),
                                child: const Text(
                                  'تحديد الكل كمقروء',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (notifications.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 32,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.notifications_none_rounded,
                                size: 36,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'لا توجد إشعارات حالياً',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            itemCount: notifications.length,
                            separatorBuilder: (_, _) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (ctx, idx) {
                              final item = notifications[idx];
                              final accent = item.isOverdue
                                  ? Colors.red.shade700
                                  : AppTheme.mediumConfidenceColor;
                              return InkWell(
                                key: Key('notification_item_${item.invoiceId}'),
                                onTap: () {
                                  Navigator.of(ctx).pop();
                                  ref
                                      .read(notificationsProvider.notifier)
                                      .markAsRead(item.id);
                                  final inv = ref
                                      .read(invoicesProvider)
                                      .where((i) => i.id == item.invoiceId)
                                      .firstOrNull;
                                  if (inv != null && mounted) {
                                    ref
                                        .read(activeDraftProvider.notifier)
                                        .setDraft(inv);
                                    context.push('/review');
                                  }
                                },
                                child: Container(
                                  color: item.isRead
                                      ? null
                                      : accent.withValues(alpha: 0.06),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Icon(
                                          item.isOverdue
                                              ? Icons.warning_amber_rounded
                                              : Icons.payments_outlined,
                                          size: 20,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    item.title,
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: item.isRead
                                                          ? FontWeight.w600
                                                          : FontWeight.w800,
                                                      color: item.isOverdue
                                                          ? Colors.red.shade800
                                                          : null,
                                                    ),
                                                  ),
                                                ),
                                                if (!item.isRead)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: BoxDecoration(
                                                      color: accent,
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              item.body,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade800,
                                                fontWeight: item.isRead
                                                    ? FontWeight.w400
                                                    : FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'الموعد: ${InvoiceModel.formatDisplayDate(item.dueDate)}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
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
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = ref.watch(shellTabIndexProvider);
    final catalog = ref.watch(catalogProvider);
    final invoiceSync = ref.watch(invoicesSyncProvider);
    final auth = ref.watch(authProvider);
    final unreadCount = ref.watch(unreadNotificationsCountProvider);
    final isAdmin = catalog.isAdminMode;
    final isSyncing = catalog.isSyncing || invoiceSync.isSyncing;
    final isOffline = catalog.isOffline || invoiceSync.isOffline;
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 760;

    final bodyContent = Column(
      children: [
        if (AppConfig.isDemoMode)
          Container(
            width: double.infinity,
            color: AppTheme.accentColor.withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.science_outlined,
                  size: 16,
                  color: AppTheme.accentColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'وضع التجربة المباشر (Demo) • الصلاحية الحالية: ${isAdmin ? "مدير المحل" : "بائع / موظف"}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accentColor,
                    ),
                  ),
                ),
              ],
            ),
          )
        else if (isOffline)
          Container(
            width: double.infinity,
            color: AppTheme.mediumConfidenceBg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 16,
                  color: AppTheme.mediumConfidenceColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    invoiceSync.pendingCount > 0
                        ? 'غير متصل — ${invoiceSync.pendingCount} فاتورة بانتظار المزامنة'
                        : 'غير متصل — يتم العمل من الكاش المحلي',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mediumConfidenceColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSyncing ? null : _syncAll,
                  child: const Text('مزامنة'),
                ),
              ],
            ),
          )
        else if (invoiceSync.pendingCount > 0)
          Container(
            width: double.infinity,
            color: AppTheme.mediumConfidenceBg,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.sync_problem_rounded,
                  size: 16,
                  color: AppTheme.mediumConfidenceColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${invoiceSync.pendingCount} فاتورة بانتظار المزامنة',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mediumConfidenceColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSyncing ? null : _syncAll,
                  child: const Text('مزامنة'),
                ),
              ],
            ),
          ),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: IndexedStack(
                index: currentIndex,
                children: _pages,
              ),
            ),
          ),
        ),
      ],
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleSystemBack(currentIndex);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_titles[currentIndex]),
        actions: [
          IconButton(
            key: const Key('header_notifications_button'),
            tooltip: 'الإشعارات',
            onPressed: () => _openNotificationsPopover(context),
            icon: Badge.count(
              key: const Key('notifications_badge'),
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              backgroundColor: Colors.red.shade600,
              child: Icon(
                unreadCount > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_outlined,
              ),
            ),
          ),
          if (!AppConfig.isDemoMode)
            IconButton(
              tooltip: 'مزامنة الآن',
              onPressed: isSyncing ? null : _syncAll,
              icon: isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Chip(
              avatar: Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person_outline,
                size: 16,
                color: AppTheme.primaryColor,
              ),
              label: Text(
                AppConfig.isDemoMode
                    ? (isAdmin ? 'المدير' : 'موظف')
                    : '${auth.fullName} (${isAdmin ? "مدير" : "موظف"})',
                style: const TextStyle(
                  fontSize: 12,
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
      body: useRail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: currentIndex,
                  onDestinationSelected: (idx) =>
                      ref.read(shellTabIndexProvider.notifier).setIndex(idx),
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: Text('الرئيسية'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.account_tree_outlined),
                      selectedIcon: Icon(Icons.account_tree_rounded),
                      label: Text('الأصناف'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.receipt_long_outlined),
                      selectedIcon: Icon(Icons.receipt_long_rounded),
                      label: Text('الفواتير'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('الإعدادات'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: bodyContent),
              ],
            )
          : bodyContent,
      bottomNavigationBar: useRail
          ? null
          : NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (idx) =>
                  ref.read(shellTabIndexProvider.notifier).setIndex(idx),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'الرئيسية',
                ),
                NavigationDestination(
                  icon: Icon(Icons.account_tree_outlined),
                  selectedIcon: Icon(Icons.account_tree_rounded),
                  label: 'الأصناف',
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long_rounded),
                  label: 'الفواتير',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'الإعدادات',
                ),
              ],
            ),
      ),
    );
  }
}
