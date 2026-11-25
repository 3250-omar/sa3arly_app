import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanitary_pricing_app/core/config/app_config.dart';
import 'package:sanitary_pricing_app/data/demo_catalog_data.dart';
import 'package:sanitary_pricing_app/data/local_cache_service.dart';
import 'package:sanitary_pricing_app/data/supabase_repository.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/auth_provider.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:sanitary_pricing_app/services/payment_reminder_service.dart';
import 'package:uuid/uuid.dart';

class InvoicesSyncState {
  const InvoicesSyncState({
    this.isSyncing = false,
    this.isOffline = false,
    this.pendingIds = const {},
  });

  final bool isSyncing;
  final bool isOffline;
  final Set<String> pendingIds;

  int get pendingCount => pendingIds.length;

  InvoicesSyncState copyWith({
    bool? isSyncing,
    bool? isOffline,
    Set<String>? pendingIds,
  }) {
    return InvoicesSyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      isOffline: isOffline ?? this.isOffline,
      pendingIds: pendingIds ?? this.pendingIds,
    );
  }
}

class InvoicesSyncNotifier extends Notifier<InvoicesSyncState> {
  @override
  InvoicesSyncState build() {
    Future.microtask(_loadPending);
    return const InvoicesSyncState();
  }

  Future<void> _loadPending() async {
    final ids = await LocalCacheService.loadPendingInvoiceIds();
    state = state.copyWith(pendingIds: ids);
  }

  void setSyncing(bool value) {
    state = state.copyWith(isSyncing: value);
  }

  void setOffline(bool value) {
    state = state.copyWith(isOffline: value);
  }

  Future<void> markPending(String id) async {
    await LocalCacheService.markInvoicePending(id);
    state = state.copyWith(pendingIds: {...state.pendingIds, id});
  }

  Future<void> clearPending(String id) async {
    await LocalCacheService.clearInvoicePending(id);
    final next = {...state.pendingIds}..remove(id);
    state = state.copyWith(pendingIds: next);
  }
}

final invoicesSyncProvider =
    NotifierProvider<InvoicesSyncNotifier, InvoicesSyncState>(
  InvoicesSyncNotifier.new,
);

class InvoicesNotifier extends Notifier<List<InvoiceModel>> {
  static const _uuid = Uuid();

  @override
  List<InvoiceModel> build() {
    final auth = ref.watch(authProvider);
    Future.microtask(() => _bootstrap(auth));
    return AppConfig.isDemoMode ? DemoCatalogData.initialInvoices() : const [];
  }

  Future<void> _bootstrap(AuthState auth) async {
    final cached = await LocalCacheService.loadInvoices();
    if (cached != null && cached.isNotEmpty) {
      state = cached;
    }

    if (!AppConfig.isDemoMode && auth.isAuthenticated) {
      await syncFromSupabase();
    }
  }

  Future<void> syncFromSupabase() async {
    if (AppConfig.isDemoMode) return;
    final syncCtrl = ref.read(invoicesSyncProvider.notifier);
    syncCtrl.setSyncing(true);
    final repo = SupabaseRepository();

    try {
      // 1. Push pending offline invoices first
      final pendingIds = await LocalCacheService.loadPendingInvoiceIds();
      for (final id in pendingIds) {
        final localInv = state.where((inv) => inv.id == id).firstOrNull;
        if (localInv != null) {
          await repo.upsertInvoice(localInv);
        }
        await syncCtrl.clearPending(id);
      }

      // 2. Pull fresh invoices from Supabase
      final remote = await repo.fetchInvoices();
      state = remote;
      await LocalCacheService.saveInvoices(remote);
      unawaited(PaymentReminderService.syncAll(remote));
      syncCtrl.setOffline(false);
    } catch (_) {
      syncCtrl.setOffline(true);
    } finally {
      syncCtrl.setSyncing(false);
    }
  }

  String generateNextInvoiceNumber({int offset = 1}) {
    final nextNum = state.length + offset;
    return 'INV-${nextNum.toString().padLeft(5, '0')}';
  }

  void saveInvoice(InvoiceModel invoice) {
    final idx = state.indexWhere((i) => i.id == invoice.id);
    if (idx >= 0) {
      final copy = [...state];
      copy[idx] = invoice;
      state = copy;
    } else {
      state = [invoice, ...state];
    }

    unawaited(LocalCacheService.saveInvoices(state));
    unawaited(PaymentReminderService.scheduleForInvoice(invoice));

    if (!AppConfig.isDemoMode) {
      unawaited(_pushInvoiceRemote(invoice));
    }
  }

  Future<void> _pushInvoiceRemote(InvoiceModel invoice) async {
    final syncCtrl = ref.read(invoicesSyncProvider.notifier);
    try {
      await SupabaseRepository().upsertInvoice(invoice);
      await syncCtrl.clearPending(invoice.id);
      syncCtrl.setOffline(false);
    } catch (_) {
      await syncCtrl.markPending(invoice.id);
      syncCtrl.setOffline(true);
    }
  }

  void approveInvoice(String id) {
    final target = state.where((i) => i.id == id).firstOrNull;
    if (target == null) return;
    saveInvoice(target.copyWith(status: InvoiceStatus.approved));
  }

  void deleteInvoice(String id) {
    state = state.where((inv) => inv.id != id).toList();
    unawaited(LocalCacheService.saveInvoices(state));
    unawaited(PaymentReminderService.cancelForInvoice(id));
    unawaited(ref.read(invoicesSyncProvider.notifier).clearPending(id));

    if (!AppConfig.isDemoMode) {
      unawaited(SupabaseRepository().deleteInvoice(id).catchError((_) {}));
    }
  }

  /// Switches every matched item in [draft] to [targetBrand] prices.
  /// Items missing from [targetBrand] keep their previous price and are flagged amber.
  InvoiceModel applyBrandSwitch(InvoiceModel draft, BrandModel targetBrand) {
    final catalog = ref.read(catalogProvider);
    final updatedItems = <InvoiceItemModel>[];

    for (final item in draft.items) {
      if (item.itemTemplateId == null) {
        updatedItems.add(item);
        continue;
      }

      final variant = catalog.findVariant(item.itemTemplateId!, targetBrand.id);
      if (variant != null) {
        updatedItems.add(
          item.copyWith(
            brandId: targetBrand.id,
            brandName: targetBrand.name,
            productVariantId: variant.id,
            unitPrice: variant.price,
            confidence: item.confidence == OcrConfidence.low
                ? OcrConfidence.medium
                : item.confidence,
            clearNotes: true,
          ),
        );
      } else {
        updatedItems.add(
          item.copyWith(
            confidence: OcrConfidence.medium,
            notes: 'غير متوفر في ${targetBrand.name} — احتفظنا بالسعر السابق',
          ),
        );
      }
    }

    return draft.copyWith(
      brandId: targetBrand.id,
      brandName: targetBrand.name,
      items: updatedItems,
    );
  }

  /// Saves both the original quote and a cloned quote in [secondBrand],
  /// linked via a shared [comparisonGroupId].
  ({InvoiceModel first, InvoiceModel second}) saveComparisonPair(
    InvoiceModel original,
    BrandModel secondBrand,
  ) {
    final groupId = original.comparisonGroupId ?? _uuid.v4();
    final first = original.copyWith(
      comparisonGroupId: groupId,
      status: InvoiceStatus.quote,
    );

    final firstExists = state.any((i) => i.id == first.id);
    final secondOffset = firstExists ? 1 : 2;
    final switched = applyBrandSwitch(first, secondBrand);
    final second = switched.copyWith(
      id: _uuid.v4(),
      invoiceNumber: generateNextInvoiceNumber(offset: secondOffset),
      comparisonGroupId: groupId,
      status: InvoiceStatus.quote,
      createdAt: DateTime.now(),
    );

    saveInvoice(first);
    saveInvoice(second);
    return (first: first, second: second);
  }
}

final invoicesProvider = NotifierProvider<InvoicesNotifier, List<InvoiceModel>>(
  InvoicesNotifier.new,
);

class ActiveDraftNotifier extends Notifier<InvoiceModel?> {
  static const _uuid = Uuid();

  @override
  InvoiceModel? build() => null;

  void setDraft(InvoiceModel draft) {
    state = draft;
  }

  void startDemoScan() {
    final existingCount = ref.read(invoicesProvider).length;
    state = DemoCatalogData.createDemoScannedDraft(existingCount + 1);
  }

  void startBlankInvoice() {
    final nextNum =
        ref.read(invoicesProvider.notifier).generateNextInvoiceNumber();

    state = InvoiceModel(
      id: _uuid.v4(),
      invoiceNumber: nextNum,
      status: InvoiceStatus.quote,
      createdAt: DateTime.now(),
    );
  }

  void clear() {
    state = null;
  }
}

final activeDraftProvider =
    NotifierProvider<ActiveDraftNotifier, InvoiceModel?>(
  ActiveDraftNotifier.new,
);
