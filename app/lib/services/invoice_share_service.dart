import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';
import 'package:url_launcher/url_launcher.dart';

class InvoiceShareService {
  const InvoiceShareService._();

  static String formatCurrency(double value) {
    final fmt = NumberFormat('#,##0.##', 'en_US');
    return '${fmt.format(value)} ج.م';
  }

  static String buildShareText(
    InvoiceModel invoice,
    ShopSettingsModel shop,
  ) {
    final dateFmt = DateFormat('yyyy/MM/dd - hh:mm a', 'en_US');
    final buf = StringBuffer()
      ..writeln('*${shop.shopName}*')
      ..writeln('${invoice.status.arabicLabel} رقم: ${invoice.invoiceNumber}')
      ..writeln('التاريخ: ${dateFmt.format(invoice.createdAt)}');

    if (invoice.customerName.trim().isNotEmpty) {
      buf.writeln('العميل: ${invoice.customerName.trim()}');
    }
    if (invoice.hasTechnician) {
      buf.writeln('الفني: ${invoice.technicianName!.trim()}');
    }
    if (invoice.brandName != null && invoice.brandName!.isNotEmpty) {
      buf.writeln('الشركة / الفئة: ${invoice.brandName}');
    }

    buf
      ..writeln('----------------------')
      ..writeln('الأصناف (${invoice.items.length}):');

    for (var i = 0; i < invoice.items.length; i++) {
      final item = invoice.items[i];
      buf.writeln(
        '${i + 1}. ${item.displayName} × ${item.quantity} ${item.unit} = ${formatCurrency(item.lineTotal)}',
      );
    }

    buf.writeln('----------------------');
    if (invoice.discountAmount > 0) {
      buf
        ..writeln('الإجمالي قبل الخصم: ${formatCurrency(invoice.subtotal)}')
        ..writeln('الخصم: -${formatCurrency(invoice.discountAmount)}');
    }
    buf
      ..writeln('*الصافي المطلوب: ${formatCurrency(invoice.total)}*')
      ..writeln('طريقة التحصيل: ${invoice.paymentMethod.arabicLabel}');
    if (invoice.paymentMethod != PaymentMethod.cash) {
      if (invoice.effectivePaidAmount > 0) {
        buf.writeln(
          'المدفوع / المقدم: ${formatCurrency(invoice.effectivePaidAmount)}',
        );
      }
      buf.writeln('المتبقي: ${formatCurrency(invoice.remainingAmount)}');
      if (invoice.paymentDueDate != null) {
        buf.writeln(
          'موعد السداد: ${InvoiceModel.formatDateOnly(invoice.paymentDueDate)}',
        );
      }
    }
    buf.writeln('للاستفسار: ${shop.phone}');

    return buf.toString();
  }

  /// Normalizes Egyptian local phone numbers (e.g. `010...`, Arabic digits)
  /// into international `wa.me` format (`2010...`). Returns null if invalid.
  static String? normalizeEgyptianWhatsAppPhone(String? rawPhone) {
    if (rawPhone == null) return null;
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    final western = rawPhone.replaceAllMapped(
      RegExp(r'[٠-٩]'),
      (m) => arabicDigits.indexOf(m.group(0)!).toString(),
    );
    var digits = western.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return null;
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.length < 8) return null;
    if (digits.length == 11 && digits.startsWith('0')) {
      return '20${digits.substring(1)}';
    }
    if (digits.length == 10 && digits.startsWith('1')) {
      return '20$digits';
    }
    return digits;
  }

  static Uri buildWhatsAppUri({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) {
    final text = buildShareText(invoice, shop);
    final phone = normalizeEgyptianWhatsAppPhone(invoice.customerPhone);
    return phone != null
        ? Uri.https('wa.me', '/$phone', {'text': text})
        : Uri.https('wa.me', '/', {'text': text});
  }

  static Future<bool> openWhatsApp({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) async {
    final uri = buildWhatsAppUri(invoice: invoice, shop: shop);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openTelegram({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) async {
    return shareInvoicePdf(invoice: invoice, shop: shop);
  }

  static String _sanitizePdfBaseName(String raw) {
    return raw
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String buildInvoicePdfFilename(InvoiceModel invoice) {
    final safeCustomer = _sanitizePdfBaseName(invoice.customerName);
    final base =
        safeCustomer.isNotEmpty ? safeCustomer : invoice.invoiceNumber;
    return '$base.pdf';
  }

  static String buildComparisonPdfFilename(List<InvoiceModel> groupInvoices) {
    if (groupInvoices.isEmpty) return 'comparison.pdf';
    final safeCustomer = _sanitizePdfBaseName(groupInvoices.first.customerName);
    if (safeCustomer.isNotEmpty) {
      return 'مقارنة - $safeCustomer.pdf';
    }
    return 'comparison-${groupInvoices.first.invoiceNumber}.pdf';
  }

  static Future<bool> shareInvoicePdf({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) async {
    final bytes = await buildInvoicePdfBytes(invoice: invoice, shop: shop);
    return Printing.sharePdf(
      bytes: bytes,
      filename: buildInvoicePdfFilename(invoice),
    );
  }

  static Future<Uint8List> buildInvoicePdfBytes({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) async {
    final regularFont = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();

    final doc = pw.Document();
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm', 'en_US');
    final brandLabel = invoice.brandSummary;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: regularFont,
          bold: boldFont,
        ),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F4C5C'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      shop.shopName,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${shop.address} | ${shop.phone}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      invoice.status.arabicLabel,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      invoice.invoiceNumber,
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (invoice.customerName.trim().isNotEmpty)
                pw.Text('العميل: ${invoice.customerName.trim()}'),
              if ((invoice.customerPhone ?? '').trim().isNotEmpty)
                pw.Text('الهاتف: ${invoice.customerPhone!.trim()}'),
              // Technician name appears ONLY when provided
              if (invoice.hasTechnician)
                pw.Text('الفني: ${invoice.technicianName!.trim()}'),
              if (brandLabel != null) pw.Text('الشركة: $brandLabel'),
              pw.Text('التاريخ: ${dateFmt.format(invoice.createdAt)}'),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.TableHelper.fromTextArray(
            headers: [
              'الإجمالي',
              'سعر الوحدة',
              'الكمية',
              'الشركة',
              'الصنف والمقاس',
              '#',
            ],
            data: [
              for (var i = 0; i < invoice.items.length; i++)
                [
                  formatCurrency(invoice.items[i].lineTotal),
                  formatCurrency(invoice.items[i].unitPrice),
                  '${invoice.items[i].quantity} ${invoice.items[i].unit}',
                  invoice.items[i].brandName ?? '-',
                  invoice.items[i].displayName,
                  '${i + 1}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F4C5C'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Container(
              width: 220,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('المجموع الفرعي:'),
                      pw.Text(formatCurrency(invoice.subtotal)),
                    ],
                  ),
                  if (invoice.discountAmount > 0) ...[
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('الخصم:'),
                        pw.Text('-${formatCurrency(invoice.discountAmount)}'),
                      ],
                    ),
                  ],
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الإجمالي النهائي:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(
                        formatCurrency(invoice.total),
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0F4C5C'),
                        ),
                      ),
                    ],
                  ),
                  pw.Divider(),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('طريقة التحصيل:'),
                      pw.Text(
                        invoice.paymentMethod.arabicLabel,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                  if (invoice.paymentMethod != PaymentMethod.cash) ...[
                    if (invoice.effectivePaidAmount > 0) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('المدفوع / المقدم:'),
                          pw.Text(formatCurrency(invoice.effectivePaidAmount)),
                        ],
                      ),
                    ],
                    pw.SizedBox(height: 4),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('المتبقي:'),
                        pw.Text(
                          formatCurrency(invoice.remainingAmount),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                    if (invoice.paymentDueDate != null) ...[
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text('موعد السداد:'),
                          pw.Text(
                            InvoiceModel.formatDateOnly(
                                  invoice.paymentDueDate,
                                ) ??
                                '',
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<void> previewOrPrintPdf({
    required InvoiceModel invoice,
    required ShopSettingsModel shop,
  }) async {
    final bytes = await buildInvoicePdfBytes(invoice: invoice, shop: shop);
    await Printing.layoutPdf(
      name: buildInvoicePdfFilename(invoice),
      onLayout: (format) async => bytes,
    );
  }

  static String buildComparisonShareText(
    List<InvoiceModel> groupInvoices,
    ShopSettingsModel shop,
  ) {
    if (groupInvoices.isEmpty) return '';
    final sorted = [...groupInvoices]
      ..sort((a, b) => a.total.compareTo(b.total));
    final first = sorted.first;

    final buf = StringBuffer()
      ..writeln('*${shop.shopName}*')
      ..writeln('مقارنة عروض أسعار لنفس الكشف');

    if (first.customerName.trim().isNotEmpty) {
      buf.writeln('العميل: ${first.customerName.trim()}');
    }
    if (first.hasTechnician) {
      buf.writeln('الفني: ${first.technicianName!.trim()}');
    }
    buf.writeln('----------------------');

    for (var i = 0; i < sorted.length; i++) {
      final inv = sorted[i];
      buf.writeln(
        '${i + 1}. شركة *${inv.brandName ?? "غير محددة"}* (${inv.invoiceNumber}): *${formatCurrency(inv.total)}*',
      );
    }

    if (sorted.length > 1) {
      final diff = sorted.last.total - sorted.first.total;
      buf.writeln('----------------------');
      if (diff == 0) {
        buf.writeln('الإجمالي متساوٍ بين الاختيارات.');
      } else {
        buf.writeln(
          'الفرق: ${formatCurrency(diff)} (${sorted.first.brandName ?? "الأولى"} أوفر)',
        );
      }
    }

    if (shop.phone.trim().isNotEmpty) {
      buf.writeln('للاستفسار: ${shop.phone.trim()}');
    }
    return buf.toString();
  }

  static Future<bool> openComparisonWhatsApp({
    required List<InvoiceModel> groupInvoices,
    required ShopSettingsModel shop,
  }) async {
    return shareComparisonPdf(groupInvoices: groupInvoices, shop: shop);
  }

  static Future<bool> shareComparisonPdf({
    required List<InvoiceModel> groupInvoices,
    required ShopSettingsModel shop,
  }) async {
    if (groupInvoices.isEmpty) return false;
    final sorted = [...groupInvoices]
      ..sort((a, b) => a.total.compareTo(b.total));
    final bytes = await buildComparisonPdfBytes(
      groupInvoices: sorted,
      shop: shop,
    );
    return Printing.sharePdf(
      bytes: bytes,
      filename: buildComparisonPdfFilename(sorted),
    );
  }

  static Future<Uint8List> buildComparisonPdfBytes({
    required List<InvoiceModel> groupInvoices,
    required ShopSettingsModel shop,
  }) async {
    final sorted = [...groupInvoices]
      ..sort((a, b) => a.total.compareTo(b.total));
    final first = sorted.first;

    final regularFont = await PdfGoogleFonts.cairoRegular();
    final boldFont = await PdfGoogleFonts.cairoBold();
    final doc = pw.Document();
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm', 'en_US');

    final maxItems = sorted.fold<int>(
      0,
      (m, inv) => inv.items.length > m ? inv.items.length : m,
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
        build: (context) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F4C5C'),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      shop.shopName,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '${shop.address} | ${shop.phone}',
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'مقارنة أسعار الشركات',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (first.customerName.trim().isNotEmpty)
                pw.Text('العميل: ${first.customerName.trim()}'),
              if ((first.customerPhone ?? '').trim().isNotEmpty)
                pw.Text('الهاتف: ${first.customerPhone!.trim()}'),
              if (first.hasTechnician)
                pw.Text('الفني: ${first.technicianName!.trim()}'),
              pw.Text('التاريخ: ${dateFmt.format(first.createdAt)}'),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: [
              for (final inv in sorted.reversed)
                inv.brandSummary ?? inv.invoiceNumber,
              'الكمية',
              'الصنف والمقاس',
              '#',
            ],
            data: [
              for (var i = 0; i < maxItems; i++)
                [
                  for (final inv in sorted.reversed)
                    i < inv.items.length
                        ? formatCurrency(inv.items[i].lineTotal)
                        : '-',
                  i < first.items.length
                      ? '${first.items[i].quantity} ${first.items[i].unit}'
                      : '-',
                  i < first.items.length ? first.items[i].displayName : '-',
                  '${i + 1}',
                ],
            ],
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10,
            ),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#0F4C5C'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerRight,
            border: pw.TableBorder.all(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                for (final inv in sorted)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'إجمالي ${inv.brandSummary ?? inv.invoiceNumber}:',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          formatCurrency(inv.total),
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColor.fromHex('#0F4C5C'),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (sorted.length > 1) ...[
                  pw.Divider(),
                  pw.Text(
                    sorted.last.total == sorted.first.total
                        ? 'الإجمالي متساوٍ بين الشركتين'
                        : 'الفرق: ${formatCurrency(sorted.last.total - sorted.first.total)} (${sorted.first.brandSummary ?? "الأولى"} أوفر)',
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#15803D'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return doc.save();
  }

  static Future<void> previewOrPrintComparisonPdf({
    required List<InvoiceModel> groupInvoices,
    required ShopSettingsModel shop,
  }) async {
    if (groupInvoices.isEmpty) return;
    final sorted = [...groupInvoices]
      ..sort((a, b) => a.total.compareTo(b.total));
    final bytes = await buildComparisonPdfBytes(
      groupInvoices: sorted,
      shop: shop,
    );
    await Printing.layoutPdf(
      name: buildComparisonPdfFilename(sorted),
      onLayout: (format) async => bytes,
    );
  }
}
