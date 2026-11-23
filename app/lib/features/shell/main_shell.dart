import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/features/catalog/catalog_tree_screen.dart';
import 'package:sanitary_pricing_app/features/dashboard/dashboard_screen.dart';
import 'package:sanitary_pricing_app/features/invoices/invoices_list_screen.dart';
import 'package:sanitary_pricing_app/features/settings/settings_screen.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';

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

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

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

  Future<void> _syncAll(WidgetRef ref) async {
    await Future.wait([
      ref.read(catalogProvider.notifier).syncFromSupabase(),
      ref.read(invoicesProvider.notifier).syncFromSupabase(),
    ]);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(shellTabIndexProvider);
    final catalog = ref.watch(catalogProvider);
    final invoiceSync = ref.watch(invoicesSyncProvider);
    final auth = ref.watch(authProvider);
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
        else if (isOffline || invoiceSync.pendingCount > 0)
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
                        ? 'وضع Offline • ${invoiceSync.pendingCount} فاتورة بانتظار المزامنة'
                        : 'غير متصل — يتم العمل من الكاش المحلي',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.mediumConfidenceColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSyncing ? null : () => _syncAll(ref),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[currentIndex]),
        actions: [
          if (!AppConfig.isDemoMode)
            IconButton(
              tooltip: 'مزامنة الآن',
              onPressed: isSyncing ? null : () => _syncAll(ref),
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
            padding: const EdgeInsets.symmetric(horizontal: 12),
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
    );
  }
}
