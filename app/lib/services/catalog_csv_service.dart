import 'package:sanitary_pricing_app/providers/catalog_provider.dart';

class CatalogCsvRow {
  const CatalogCsvRow({
    required this.categoryName,
    required this.itemName,
    this.size,
    required this.unit,
    required this.brandName,
    required this.price,
  });

  final String categoryName;
  final String itemName;
  final String? size;
  final String unit;
  final String brandName;
  final double price;
}

class CatalogCsvParseResult {
  const CatalogCsvParseResult({
    required this.rows,
    required this.skippedLines,
  });

  final List<CatalogCsvRow> rows;
  final int skippedLines;
}

class CatalogCsvService {
  const CatalogCsvService._();

  static const String sampleTemplate =
      'القسم,اسم الصنف,المقاس,الوحدة,الشركة,السعر\n'
      'تغذية (بولي),كوع لحام,1/2 بوصة,قطعة,الشريف,18\n'
      'تغذية (بولي),كوع لحام,1/2 بوصة,قطعة,BR,14\n'
      'صرف,جلبة صرف بسن,4 بوصة,قطعة,الشريف,65\n'
      'محابس وخلاطات,محبس بلي نحاس,3/4 بوصة,قطعة,BR,210';

  /// Parses CSV (comma-separated) or TSV (direct copy-paste from Excel).
  static CatalogCsvParseResult parseImportText(String rawText) {
    final normalized = rawText.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n');
    final lines = normalized
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final rows = <CatalogCsvRow>[];
    var skipped = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final delimiter = line.contains('\t') ? '\t' : ',';
      final cols = _splitDelimitedLine(line, delimiter);

      // Skip header row
      if (i == 0 &&
          (cols.first.contains('القسم') ||
              cols.first.toLowerCase().contains('category'))) {
        continue;
      }

      if (cols.length < 6) {
        skipped++;
        continue;
      }

      final categoryName = cols[0].trim();
      final itemName = cols[1].trim();
      final sizeText = cols[2].trim();
      final unitText = cols[3].trim();
      final brandName = cols[4].trim();
      final rawPrice = cols[5]
          .trim()
          .replaceAll(',', '')
          .replaceAll('ج.م', '')
          .trim();
      final price = double.tryParse(_toEnglishDigits(rawPrice));

      if (categoryName.isEmpty ||
          itemName.isEmpty ||
          brandName.isEmpty ||
          price == null ||
          price < 0) {
        skipped++;
        continue;
      }

      rows.add(
        CatalogCsvRow(
          categoryName: categoryName,
          itemName: itemName,
          size: sizeText.isEmpty ? null : sizeText,
          unit: unitText.isEmpty ? 'قطعة' : unitText,
          brandName: brandName,
          price: price,
        ),
      );
    }

    return CatalogCsvParseResult(rows: rows, skippedLines: skipped);
  }

  /// Generates RFC-4180 CSV with UTF-8 BOM so Microsoft Excel opens Arabic properly.
  static String exportCatalogCsv(CatalogState catalog) {
    final buf = StringBuffer('\uFEFF')
      ..writeln('القسم,اسم الصنف,المقاس,الوحدة,الشركة,السعر');

    final catById = {for (final c in catalog.categories) c.id: c};
    final brandById = {for (final b in catalog.brands) b.id: b};

    for (final template in catalog.templates) {
      final catName = catById[template.categoryId]?.name ?? 'عام';
      final variants = catalog.variantsForTemplate(template.id);

      if (variants.isEmpty) {
        buf.writeln(
          [
            _csvCell(catName),
            _csvCell(template.name),
            _csvCell(template.size ?? ''),
            _csvCell(template.unit),
            _csvCell('غير محدد'),
            '0',
          ].join(','),
        );
        continue;
      }

      for (final variant in variants) {
        final brandName = brandById[variant.brandId]?.name ?? 'غير محدد';
        buf.writeln(
          [
            _csvCell(catName),
            _csvCell(template.name),
            _csvCell(template.size ?? ''),
            _csvCell(template.unit),
            _csvCell(brandName),
            variant.price.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), ''),
          ].join(','),
        );
      }
    }

    return buf.toString();
  }

  static List<String> _splitDelimitedLine(String line, String delimiter) {
    if (delimiter == '\t') {
      return line.split('\t').map((c) => c.trim()).toList();
    }

    final cells = <String>[];
    final current = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        cells.add(current.toString().trim());
        current.clear();
      } else {
        current.write(char);
      }
    }
    cells.add(current.toString().trim());
    return cells;
  }

  static String _csvCell(String value) {
    final sanitized = value.replaceAll('\r', ' ').replaceAll('\n', ' ');
    if (sanitized.contains(',') || sanitized.contains('"')) {
      return '"${sanitized.replaceAll('"', '""')}"';
    }
    return sanitized;
  }

  static String _toEnglishDigits(String input) {
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    const easternDigits = '۰۱۲۳۴۵۶۷۸۹';
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      final idxA = arabicDigits.indexOf(ch);
      if (idxA >= 0) {
        buf.write(idxA);
        continue;
      }
      final idxE = easternDigits.indexOf(ch);
      if (idxE >= 0) {
        buf.write(idxE);
        continue;
      }
      buf.write(ch);
    }
    return buf.toString();
  }
}
