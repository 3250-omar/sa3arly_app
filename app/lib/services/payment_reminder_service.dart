import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class PaymentReminderService {
  PaymentReminderService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static int notificationIdFor(String invoiceId) =>
      invoiceId.hashCode & 0x7fffffff;

  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Africa/Cairo'));

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      );

      await _plugin.initialize(settings);

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();

      _initialized = true;
    } catch (_) {
      // Safe no-op in tests or unsupported platforms
    }
  }

  static Future<void> scheduleForInvoice(InvoiceModel invoice) async {
    if (kIsWeb) return;
    await initialize();
    if (!_initialized) return;

    final notifId = notificationIdFor(invoice.id);
    try {
      await _plugin.cancel(notifId);

      if (invoice.status != InvoiceStatus.approved ||
          !invoice.paymentMethod.requiresDueDate ||
          invoice.paymentDueDate == null ||
          invoice.remainingAmount <= 0) {
        return;
      }

      final due = invoice.paymentDueDate!;
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day,
        9,
        0,
      );

      // If due today and it is already past 9:00 AM, notify shortly instead of skipping.
      if (!scheduled.isAfter(now)) {
        final todayStart = DateTime(now.year, now.month, now.day);
        final dueDateOnly = DateTime(due.year, due.month, due.day);
        if (dueDateOnly.isBefore(todayStart)) {
          return;
        }
        scheduled = now.add(const Duration(minutes: 1));
      }

      final customer = invoice.customerName.trim().isEmpty
          ? 'العميل'
          : invoice.customerName.trim();
      final remainingText =
          InvoiceShareService.formatCurrency(invoice.remainingAmount);

      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'payment_reminders',
          'تذكير مواعيد التحصيل',
          channelDescription:
              'تنبيهات بمواعيد استحقاق المبالغ المتبقية على الفواتير الآجلة',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

      await _plugin.zonedSchedule(
        notifId,
        'موعد تحصيل فاتورة اليوم',
        'المفروض $customer يجيب $remainingText النهارده — فاتورة ${invoice.invoiceNumber}',
        scheduled,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Ignore scheduling failures on unsupported targets
    }
  }

  static Future<void> cancelForInvoice(String invoiceId) async {
    if (kIsWeb) return;
    if (!_initialized) return;
    try {
      await _plugin.cancel(notificationIdFor(invoiceId));
    } catch (_) {}
  }

  static Future<void> syncAll(List<InvoiceModel> invoices) async {
    if (kIsWeb) return;
    await initialize();
    if (!_initialized) return;
    for (final inv in invoices) {
      await scheduleForInvoice(inv);
    }
  }
}
