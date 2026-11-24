import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/core/theme/app_theme.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/providers/staff_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _addressCtrl;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(catalogProvider).shopSettings;
    _nameCtrl = TextEditingController(text: settings.shopName);
    _phoneCtrl = TextEditingController(text: settings.phone);
    _addressCtrl = TextEditingController(text: settings.address);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ShopSettingsModel>(
      catalogProvider.select((s) => s.shopSettings),
      (prev, next) {
        if (!_isDirty) {
          _nameCtrl.text = next.shopName;
          _phoneCtrl.text = next.phone;
          _addressCtrl.text = next.address;
        }
      },
    );

    final catalog = ref.watch(catalogProvider);
    final invoiceSync = ref.watch(invoicesSyncProvider);
    final auth = ref.watch(authProvider);
    final isDemo = AppConfig.isDemoMode;
    final syncFmt = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Connection & Sync Status
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDemo
                        ? AppTheme.mediumConfidenceBg
                        : (catalog.isOffline
                            ? AppTheme.lowConfidenceBg
                            : AppTheme.highConfidenceBg),
                    child: Icon(
                      isDemo
                          ? Icons.science_outlined
                          : (catalog.isOffline
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_done_outlined),
                      color: isDemo
                          ? AppTheme.mediumConfidenceColor
                          : (catalog.isOffline
                              ? AppTheme.lowConfidenceColor
                              : AppTheme.highConfidenceColor),
                    ),
                  ),
                  title: Text(
                    isDemo
                        ? 'وضع التجربة (Demo Mode)'
                        : (catalog.isOffline
                            ? 'وضع Offline (مزامنة متوقفة مؤقتاً)'
                            : 'متصل بمشروع Supabase بنجاح'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    isDemo
                        ? 'لتفعيل الحفظ السحابي والذكاء الاصطناعي الحقيقي، نفّذ دليل supabase/SETUP.md ومرر SUPABASE_URL و SUPABASE_ANON_KEY عبر --dart-define.'
                        : [
                            if (catalog.lastSyncedAt != null)
                              'آخر مزامنة: ${syncFmt.format(catalog.lastSyncedAt!)}',
                            if (invoiceSync.pendingCount > 0)
                              'فواتير في طابور المزامنة: ${invoiceSync.pendingCount}',
                          ].join(' • '),
                  ),
                ),
                if (!isDemo) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        onPressed: catalog.isSyncing || invoiceSync.isSyncing
                            ? null
                            : () async {
                                _isDirty = false;
                                await Future.wait([
                                  ref
                                      .read(catalogProvider.notifier)
                                      .syncFromSupabase(),
                                  ref
                                      .read(invoicesProvider.notifier)
                                      .syncFromSupabase(),
                                ]);
                              },
                        icon: const Icon(Icons.sync_rounded),
                        label: Text(
                          catalog.isSyncing || invoiceSync.isSyncing
                              ? 'جاري المزامنة...'
                              : 'مزامنة الآن',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () =>
                            ref.read(authProvider.notifier).signOut(),
                        icon: const Icon(Icons.logout_rounded),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Role / RBAC Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDemo ? 'معاينة الصلاحيات (RBAC)' : 'صلاحيات الحساب الحالي',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isDemo
                      ? 'جرّب التبديل بين حساب المدير (يضيف ويعدل الأسعار ويحذف الفواتير) وحساب البائع/الموظف.'
                      : 'المستخدم: ${auth.fullName} • الصلاحية: ${auth.isAdmin ? "مدير المحل (Admin)" : "بائع / موظف (Staff)"}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                if (isDemo) ...[
                  const SizedBox(height: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.admin_panel_settings_outlined),
                        label: Text('المدير (Admin)'),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.badge_outlined),
                        label: Text('موظف / بائع (Staff)'),
                      ),
                    ],
                    selected: {catalog.isAdminMode},
                    onSelectionChanged: (set) {
                      ref
                          .read(catalogProvider.notifier)
                          .setAdminMode(set.first);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Shop Info (used in PDF & WhatsApp)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'بيانات المحل (تظهر في الفاتورة والـ PDF)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameCtrl,
                  enabled: catalog.isAdminMode,
                  onChanged: (_) => _isDirty = true,
                  decoration: const InputDecoration(labelText: 'اسم المحل'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phoneCtrl,
                  enabled: catalog.isAdminMode,
                  onChanged: (_) => _isDirty = true,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _addressCtrl,
                  enabled: catalog.isAdminMode,
                  onChanged: (_) => _isDirty = true,
                  decoration: const InputDecoration(labelText: 'العنوان'),
                ),
                const SizedBox(height: 12),
                if (catalog.isAdminMode)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        _isDirty = false;
                        ref.read(catalogProvider.notifier).updateShopSettings(
                              catalog.shopSettings.copyWith(
                                shopName: _nameCtrl.text.trim(),
                                phone: _phoneCtrl.text.trim(),
                                address: _addressCtrl.text.trim(),
                              ),
                            );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('تم حفظ بيانات المحل')),
                        );
                      },
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ البيانات'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Learned Technician Dictionary (Aliases)
        Card(
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: const Key('technician_dictionary_expansion'),
            initiallyExpanded: false,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: const Icon(
              Icons.menu_book_outlined,
              color: AppTheme.primaryColor,
            ),
            title: Text(
              'قاموس مسميات الفنيين (${catalog.aliases.length})',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
            subtitle: Text(
              'المسميات الدارجة التي يتعلمها التطبيق تلقائياً (اضغط للعرض أو التعديل)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            children: [
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final alias in catalog.aliases)
                      Builder(
                        builder: (context) {
                          final t = catalog.findTemplate(alias.itemTemplateId);
                          return Chip(
                            label: Text(
                              '${alias.aliasText} ← ${t?.displayLabel ?? ""}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            onDeleted: catalog.isAdminMode
                                ? () => ref
                                    .read(catalogProvider.notifier)
                                    .deleteAlias(alias.id)
                                : null,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (catalog.isAdminMode) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'إدارة الموظفين والصلاحيات',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'يمكنك تغيير صلاحية الموظف أو إيقاف حسابه مؤقتاً (يتم إضافة الموظفين الجدد من لوحة تحكم Supabase Auth).',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 10),
                  for (final member in ref.watch(staffProvider))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Icon(
                          member.isAdmin
                              ? Icons.admin_panel_settings_outlined
                              : Icons.person_outline,
                        ),
                      ),
                      title: Text(
                        member.fullName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        member.isActive ? 'حساب نشط' : 'حساب معطّل',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ActionChip(
                            label: Text(
                              member.role == 'admin' ? 'مدير' : 'موظف',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onPressed: () {
                              final err = ref
                                  .read(staffProvider.notifier)
                                  .toggleRole(member.id);
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                            },
                          ),
                          Switch(
                            value: member.isActive,
                            onChanged: (_) {
                              final err = ref
                                  .read(staffProvider.notifier)
                                  .toggleActive(member.id);
                              if (err != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(err)),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Phase 2 printer readiness
        const Card(
          child: ListTile(
            leading: Icon(Icons.print_outlined, color: AppTheme.primaryColor),
            title: Text('الطباعة المباشرة (المرحلة القادمة)'),
            subtitle: Text(
              'خدمة InvoicePrinterService مجهزة في الكود لربط طابعات الريسيت الحرارية Bluetooth أو طابعات Wi-Fi لاحقاً، وحالياً يتوفر التصدير كـ PDF للطباعة.',
            ),
          ),
        ),
      ],
    );
  }
}
