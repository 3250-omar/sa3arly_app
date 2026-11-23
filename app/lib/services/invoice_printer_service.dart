import 'package:sanitary_pricing_app/models/catalog_models.dart';
import 'package:sanitary_pricing_app/models/invoice_models.dart';

/// Phase 2 extension point for direct Bluetooth thermal / Wi-Fi A4 printers.
/// Keeping this abstraction isolated lets us plug in hardware drivers later
/// without modifying invoice or review workflows.
abstract class InvoicePrinterService {
  Future<void> printInvoice(
    InvoiceModel invoice,
    ShopSettingsModel shopSettings,
  );
}
