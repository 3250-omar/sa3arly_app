import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sanitary_pricing_app/data/local_cache_service.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:sanitary_pricing_app/services/invoice_share_service.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class PaymentReminderService {
  PaymentReminderService._();

  static const String _channelId = 'payment_reminders_v2';
  static const String _channelName = 'تذكير مواعيد التحصيل';
  static const String _channelDescription =
      'تنبيهات بمواعيد استحقاق المبالغ المتبقية على الفواتير الآجلة';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  static Stream<String> get onNotificationTap => _tapController.stream;
  static String? _pendingLaunchPayload;

  static String? consumeLaunchPayload() {
    final p = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return p;
  }

  static int dueNotificationIdFor(String invoiceId) =>
      ('due:$invoiceId').hashCode & 0x7fffffff;

  static int overdueNotificationIdFor(String invoiceId) =>
      ('overdue:$invoiceId').hashCode & 0x7fffffff;

  static String _notificationKeyFor(InvoiceModel invoice, [DateTime? now]) {
    final datePart = InvoiceModel.formatDateOnly(invoice.paymentDueDate) ?? '';
    final prefix = invoice.isPaymentOverdue(now) ? 'overdue' : 'due_today';
    return '$prefix:${invoice.id}:$datePart';
  }

  static NotificationDetails _buildDetails(String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

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

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _tapController.add(payload);
          }
        },
      );

      final launchDetails = await _plugin.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty) {
          _pendingLaunchPayload = payload;
        }
      }

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();

      _initialized = true;
    } catch (_) {
      // Safe no-op in tests or unsupported platforms
    }
  }

  static Future<void> scheduleForInvoice(InvoiceModel invoice) async {
    if (kIsWeb) return;
    await initialize();
    if (!_initialized) return;

    final dueId = dueNotificationIdFor(invoice.id);
    final overdueId = overdueNotificationIdFor(invoice.id);
    try {
      await _plugin.cancel(dueId);
      await _plugin.cancel(overdueId);

      if (invoice.status != InvoiceStatus.approved ||
          !invoice.paymentMethod.requiresDueDate ||
          invoice.paymentDueDate == null ||
          invoice.remainingAmount <= 0) {
        return;
      }

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact =
          await androidPlugin?.canScheduleExactNotifications() ?? false;
      final scheduleMode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

      final due = invoice.paymentDueDate!;
      final now = tz.TZDateTime.now(tz.local);
      final nowLocal = DateTime.now();
      final formattedAmount =
          InvoiceShareService.formatCurrency(invoice.remainingAmount);

      if (invoice.isPaymentOverdue(nowLocal)) {
        final notifKey = _notificationKeyFor(invoice, nowLocal);
        final delivered =
            await LocalCacheService.loadDeliveredDeviceNotificationKeys();
        if (!delivered.contains(notifKey)) {
          final title = invoice.paymentReminderTitle(nowLocal);
          final body = invoice.paymentReminderBody(formattedAmount, nowLocal);
          await _plugin.show(
            overdueId,
            title,
            body,
            _buildDetails(body),
            payload: '$notifKey|${invoice.id}',
          );
          await LocalCacheService.markDeviceNotificationDelivered(notifKey);
        }
        return;
      }

      if (invoice.isPaymentDueToday(nowLocal)) {
        final notifKey = _notificationKeyFor(invoice, nowLocal);
        final dueNineAm = tz.TZDateTime(
          tz.local,
          due.year,
          due.month,
          due.day,
          9,
          0,
        );
        final dueTitle = invoice.paymentReminderTitle(nowLocal);
        final dueBody = invoice.paymentReminderBody(formattedAmount, nowLocal);
        final duePayload = '$notifKey|${invoice.id}';

        if (dueNineAm.isAfter(now)) {
          await _plugin.zonedSchedule(
            dueId,
            dueTitle,
            dueBody,
            dueNineAm,
            _buildDetails(dueBody),
            androidScheduleMode: scheduleMode,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: duePayload,
          );
        } else {
          final delivered =
              await LocalCacheService.loadDeliveredDeviceNotificationKeys();
          if (!delivered.contains(notifKey)) {
            await _plugin.show(
              dueId,
              dueTitle,
              dueBody,
              _buildDetails(dueBody),
              payload: duePayload,
            );
            await LocalCacheService.markDeviceNotificationDelivered(notifKey);
          }
        }

        // Also schedule the next-day overdue reminder in case the day finishes unpaid.
        final nextDay = DateTime(due.year, due.month, due.day, 9, 0)
            .add(const Duration(days: 1));
        final overdueAt = tz.TZDateTime(
          tz.local,
          nextDay.year,
          nextDay.month,
          nextDay.day,
          9,
          0,
        );
        final overdueTitle = invoice.paymentReminderTitle(nextDay);
        final overdueBody = invoice.paymentReminderBody(formattedAmount, nextDay);
        final overdueKey = _notificationKeyFor(invoice, nextDay);
        await _plugin.zonedSchedule(
          overdueId,
          overdueTitle,
          overdueBody,
          overdueAt,
          _buildDetails(overdueBody),
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '$overdueKey|${invoice.id}',
        );
        return;
      }

      // Future due date: schedule both due-day and next-day overdue notifications.
      final dueRef = DateTime(due.year, due.month, due.day, 9, 0);
      final dueAt = tz.TZDateTime(
        tz.local,
        due.year,
        due.month,
        due.day,
        9,
        0,
      );
      if (dueAt.isAfter(now)) {
        final dueTitle = invoice.paymentReminderTitle(dueRef);
        final dueBody = invoice.paymentReminderBody(formattedAmount, dueRef);
        final dueKey = _notificationKeyFor(invoice, dueRef);
        await _plugin.zonedSchedule(
          dueId,
          dueTitle,
          dueBody,
          dueAt,
          _buildDetails(dueBody),
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '$dueKey|${invoice.id}',
        );
      }

      final nextDay = dueRef.add(const Duration(days: 1));
      final overdueAt = tz.TZDateTime(
        tz.local,
        nextDay.year,
        nextDay.month,
        nextDay.day,
        9,
        0,
      );
      if (overdueAt.isAfter(now)) {
        final overdueTitle = invoice.paymentReminderTitle(nextDay);
        final overdueBody = invoice.paymentReminderBody(formattedAmount, nextDay);
        final overdueKey = _notificationKeyFor(invoice, nextDay);
        await _plugin.zonedSchedule(
          overdueId,
          overdueTitle,
          overdueBody,
          overdueAt,
          _buildDetails(overdueBody),
          androidScheduleMode: scheduleMode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: '$overdueKey|${invoice.id}',
        );
      }
    } catch (_) {
      // Ignore scheduling failures on unsupported targets
    }
  }

  static Future<void> cancelForInvoice(String invoiceId) async {
    if (kIsWeb || !_initialized) return;
    try {
      await _plugin.cancel(dueNotificationIdFor(invoiceId));
      await _plugin.cancel(overdueNotificationIdFor(invoiceId));
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
