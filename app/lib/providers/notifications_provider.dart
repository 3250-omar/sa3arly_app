import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sanitary_pricing_app/data/local_cache_service.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/providers/invoice_provider.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';

class AppNotificationItem {
  const AppNotificationItem({
    required this.id,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.title,
    required this.body,
    required this.dueDate,
    required this.remainingAmount,
    required this.isOverdue,
    required this.isRead,
  });

  final String id;
  final String invoiceId;
  final String invoiceNumber;
  final String customerName;
  final String title;
  final String body;
  final DateTime dueDate;
  final double remainingAmount;
  final bool isOverdue;
  final bool isRead;
}

class NotificationsNotifier extends Notifier<List<AppNotificationItem>> {
  final Set<String> _readIds = {};
  bool _loadedReadIds = false;
  bool _disposed = false;

  static String notificationKeyForInvoice(
    InvoiceModel inv, [
    DateTime? now,
  ]) {
    final datePart = InvoiceModel.formatDateOnly(inv.paymentDueDate) ?? '';
    final prefix = inv.isPaymentOverdue(now) ? 'overdue' : 'due_today';
    return '$prefix:${inv.id}:$datePart';
  }

  @override
  List<AppNotificationItem> build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final invoices = ref.watch(invoicesProvider);
    if (!_loadedReadIds) {
      Future.microtask(_loadPersistedReadIds);
    }
    return _buildItems(invoices);
  }

  Future<void> _loadPersistedReadIds() async {
    final persisted = await LocalCacheService.loadReadNotificationIds();
    if (_disposed) return;
    _loadedReadIds = true;
    _readIds.addAll(persisted);
    state = _buildItems(ref.read(invoicesProvider));
  }

  List<AppNotificationItem> _buildItems(List<InvoiceModel> invoices) {
    final items = <AppNotificationItem>[];
    final now = DateTime.now();

    for (final inv in invoices) {
      if (!inv.isPaymentDueOrOverdue || inv.paymentDueDate == null) continue;
      final isOverdue = inv.isPaymentOverdue(now);
      final id = notificationKeyForInvoice(inv, now);
      final formattedRemaining =
          InvoiceShareService.formatCurrency(inv.remainingAmount);

      items.add(
        AppNotificationItem(
          id: id,
          invoiceId: inv.id,
          invoiceNumber: inv.invoiceNumber,
          customerName: inv.customerName.trim().isEmpty
              ? 'العميل'
              : inv.customerName.trim(),
          title: inv.paymentReminderTitle(now),
          body: inv.paymentReminderBody(formattedRemaining, now),
          dueDate: inv.paymentDueDate!,
          remainingAmount: inv.remainingAmount,
          isOverdue: isOverdue,
          isRead: _readIds.contains(id),
        ),
      );
    }

    items.sort((a, b) {
      if (a.isRead != b.isRead) {
        return a.isRead ? 1 : -1;
      }
      if (a.isOverdue != b.isOverdue) {
        return a.isOverdue ? -1 : 1;
      }
      return b.dueDate.compareTo(a.dueDate);
    });

    return items;
  }

  void markAsRead(String notificationId) {
    _readIds.add(notificationId);
    unawaited(LocalCacheService.markNotificationRead(notificationId));
    state = _buildItems(ref.read(invoicesProvider));
  }

  void markAllAsRead() {
    final ids = [for (final item in state) item.id];
    if (ids.isEmpty) return;
    _readIds.addAll(ids);
    unawaited(LocalCacheService.markAllNotificationsRead(ids));
    state = _buildItems(ref.read(invoicesProvider));
  }

  void markInvoiceNotificationsRead(String invoiceId) {
    final matching = state.where((n) => n.invoiceId == invoiceId).toList();
    if (matching.isEmpty) return;
    final ids = [for (final m in matching) m.id];
    _readIds.addAll(ids);
    unawaited(LocalCacheService.markAllNotificationsRead(ids));
    state = _buildItems(ref.read(invoicesProvider));
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, List<AppNotificationItem>>(
  NotificationsNotifier.new,
);

final unreadNotificationsCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((n) => !n.isRead).length;
});
