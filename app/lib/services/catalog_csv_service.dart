import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sanitary_pricing_app/providers/catalog_provider.dart';
import 'package:xml/xml.dart';

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

  static const int maxImportFileBytes = 10 * 1024 * 1024;

  static const String sampleTemplate =
      'القسم,اسم الصنف,المقاس,الوحدة,الشركة,السعر\n'
      'تغذية (بولي),كوع لحام,1/2 بوصة,قطعة,الشريف,18\n'
      'تغذية (بولي),كوع لحام,1/2 بوصة,قطعة,BR,14\n'
      'صرف,جلبة صرف بسن,4 بوصة,قطعة,الشريف,65\n'
      'محابس وخلاطات,محبس بلي نحاس,3/4 بوصة,قطعة,BR,210';

  /// Parses CSV (comma or semicolon-separated) or TSV (direct copy-paste from Excel).
  static CatalogCsvParseResult parseImportText(String rawText) {
    final normalized = rawText.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n');
    final lines = normalized
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final tabular = <List<String>>[];
    for (final line in lines) {
      final delimiter = _detectLineDelimiter(line);
      tabular.add(_splitDelimitedLine(line, delimiter));
    }
    return _parseTabularRows(tabular);
  }

  /// Parses an `.xlsx` workbook directly from its OOXML ZIP/XML entries.
  /// Ignores `styles.xml` to avoid styling crashes and reads cached `<v>` values
  /// on formula cells.
  static CatalogCsvParseResult parseExcelBytes(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0xD0 &&
        bytes[1] == 0xCF &&
        bytes[2] == 0x11 &&
        bytes[3] == 0xE0) {
      throw const FormatException(
        'ملف .xls القديم غير مدعوم — افتحه في Excel واحفظه بصيغة .xlsx أو .csv',
      );
    }
    if (bytes.length < 2 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      throw const FormatException(
        'الملف المختار ليس ملف Excel (.xlsx) صالح',
      );
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException(
        'تعذر فك ضغط ملف Excel (.xlsx)، تأكد أنه غير تالف أو محمي بكلمة مرور',
      );
    }

    final fileByPath = <String, ArchiveFile>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final norm = entry.name.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '').toLowerCase();
      fileByPath[norm] = entry;
    }

    final sharedStrings = _readSharedStrings(fileByPath['xl/sharedstrings.xml']);
    final sheets = _resolveWorksheetInfos(fileByPath);
    if (sheets.isEmpty) {
      return const CatalogCsvParseResult(rows: [], skippedLines: 0);
    }

    final parsedSheets = <String, _ParsedSheetData>{};
    final cellsBySheet = <String, Map<String, _RawSheetCell>>{};
    for (final info in sheets) {
      final file = fileByPath[info.path];
      if (file == null) continue;
      final sheetData = _readWorksheetData(file, sharedStrings);
      parsedSheets[info.name] = sheetData;
      cellsBySheet[info.name] = sheetData.cellsByRef;
    }

    final evaluator = _SheetFormulaEvaluator(cellsBySheet);

    CatalogCsvParseResult? firstNonEmptyResult;
    for (final info in sheets) {
      final sheetData = parsedSheets[info.name];
      if (sheetData == null || sheetData.grid.isEmpty) continue;

      for (final slot in sheetData.formulaSlots) {
        final computed = evaluator.evalCell(info.name, slot.cellRef);
        if (computed != null) {
          final formatted = (computed * 10000).round() / 10000.0;
          sheetData.grid[slot.rowIdx][slot.colIdx] = formatted.toString();
        }
      }

      final tabular = sheetData.grid
          .where((r) => r.any((c) => c.trim().isNotEmpty))
          .toList();
      if (tabular.isEmpty) continue;

      final parsed = _parseTabularRows(tabular);
      if (parsed.rows.isNotEmpty) {
        return parsed;
      }
      firstNonEmptyResult ??= parsed;
    }

    return firstNonEmptyResult ??
        const CatalogCsvParseResult(rows: [], skippedLines: 0);
  }

  /// Parses an uploaded `.xlsx`, `.csv`, `.tsv`, or `.txt` catalog file.
  static CatalogCsvParseResult parseUploadedFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (bytes.isEmpty || bytes.length > maxImportFileBytes) {
      throw const FormatException(
        'حجم الملف غير صالح (الحد الأقصى 10 ميجابايت)',
      );
    }
    final lower = fileName.toLowerCase().trim();
    if (lower.endsWith('.xls')) {
      throw const FormatException(
        'ملف .xls القديم غير مدعوم — افتحه في Excel واحفظه بصيغة .xlsx أو .csv',
      );
    }
    if (lower.endsWith('.xlsx')) {
      return parseExcelBytes(bytes);
    }
    if (lower.endsWith('.csv') ||
        lower.endsWith('.tsv') ||
        lower.endsWith('.txt')) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return parseImportText(text);
    }
    if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4B) {
      return parseExcelBytes(bytes);
    }
    throw const FormatException(
      'صيغة الملف غير مدعومة، اختر ملف Excel (.xlsx) أو CSV',
    );
  }

  static String _detectLineDelimiter(String line) {
    if (line.contains('\t')) return '\t';
    if (line.contains(';') && !line.contains(',')) return ';';
    if (line.contains(';')) {
      final semis = ';'.allMatches(line).length;
      final commas = ','.allMatches(line).length;
      if (semis > commas) return ';';
    }
    return ',';
  }

  static CatalogCsvParseResult _parseTabularRows(List<List<String>> rawRows) {
    final nonEmpty = rawRows
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList();
    if (nonEmpty.isEmpty) {
      return const CatalogCsvParseResult(rows: [], skippedLines: 0);
    }

    var headerRowIdx = -1;
    _HeaderColMap? colMap;
    final scanLimit = nonEmpty.length < 6 ? nonEmpty.length : 6;
    for (var i = 0; i < scanLimit; i++) {
      final candidate = _detectHeaderColumns(nonEmpty[i]);
      if (candidate != null) {
        headerRowIdx = i;
        colMap = candidate;
        break;
      }
    }

    final startIdx = headerRowIdx >= 0 ? headerRowIdx + 1 : 0;
    final rows = <CatalogCsvRow>[];
    var skipped = 0;

    for (var i = startIdx; i < nonEmpty.length; i++) {
      final cols = nonEmpty[i];
      final parsed = colMap != null
          ? _parseMappedColumns(cols, colMap)
          : _parseRowColumns(cols);
      if (parsed == null) {
        skipped++;
      } else {
        rows.add(parsed);
      }
    }

    return CatalogCsvParseResult(rows: rows, skippedLines: skipped);
  }

  static _HeaderColMap? _detectHeaderColumns(List<String> cols) {
    int? catIdx;
    int? itemIdx;
    int? sizeIdx;
    int? unitIdx;
    int? brandIdx;
    int? priceIdx;
    var hasCommercialPrice = false;
    var matchedFields = 0;

    for (var i = 0; i < cols.length; i++) {
      final h = cols[i]
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
          .replaceAll(RegExp(r'\s+'), ' ');
      if (h.isEmpty) continue;

      if (catIdx == null &&
          (h.contains('قسم') ||
              h.contains('فئة') ||
              h.contains('فئه') ||
              h.contains('category'))) {
        catIdx = i;
        matchedFields++;
      } else if (itemIdx == null &&
          (h.contains('صنف') ||
              h.contains('منتج') ||
              h.contains('بيان') ||
              h.contains('بند') ||
              h.contains('item') ||
              h.contains('product') ||
              h == 'name' ||
              h == 'الاسم')) {
        itemIdx = i;
        matchedFields++;
      } else if (sizeIdx == null &&
          (h.contains('مقاس') || h.contains('قطر') || h.contains('size'))) {
        sizeIdx = i;
        matchedFields++;
      } else if (unitIdx == null &&
          (h.contains('وحدة') || h.contains('وحده') || h.contains('unit'))) {
        unitIdx = i;
        matchedFields++;
      } else if (brandIdx == null &&
          (h.contains('شركة') ||
              h.contains('شركه') ||
              h.contains('ماركة') ||
              h.contains('ماركه') ||
              h.contains('brand') ||
              h.contains('company'))) {
        brandIdx = i;
        matchedFields++;
      } else if (h.contains('تجاري') ||
          h.contains('جملة') ||
          h.contains('جمله') ||
          h.contains('تكلفة') ||
          h.contains('تكلفه') ||
          h.contains('commercial') ||
          h.contains('cost')) {
        priceIdx = i;
        hasCommercialPrice = true;
        matchedFields++;
      } else if (!hasCommercialPrice &&
          priceIdx == null &&
          (h.contains('سعر') || h.contains('price'))) {
        priceIdx = i;
        matchedFields++;
      }
    }

    if (matchedFields >= 2 && itemIdx != null && priceIdx != null) {
      return _HeaderColMap(
        categoryIdx: catIdx,
        itemIdx: itemIdx,
        sizeIdx: sizeIdx,
        unitIdx: unitIdx,
        brandIdx: brandIdx,
        priceIdx: priceIdx,
      );
    }
    return null;
  }

  static CatalogCsvRow? _parseMappedColumns(
    List<String> cols,
    _HeaderColMap map,
  ) {
    String cellAt(int? idx) =>
        (idx != null && idx >= 0 && idx < cols.length) ? cols[idx].trim() : '';

    final categoryName = cellAt(map.categoryIdx);
    final itemName = cellAt(map.itemIdx);
    final sizeText = cellAt(map.sizeIdx);
    final unitText = cellAt(map.unitIdx);
    final brandName = cellAt(map.brandIdx);
    final price = _parsePriceText(cellAt(map.priceIdx));

    if (itemName.isEmpty || price == null || price < 0) {
      return null;
    }

    final normalizedSize =
        (sizeText.isEmpty || sizeText == 'غير مذكور' || sizeText == '-')
            ? null
            : sizeText;

    return CatalogCsvRow(
      categoryName: categoryName.isEmpty ? 'عام' : categoryName,
      itemName: itemName,
      size: normalizedSize,
      unit: unitText.isEmpty ? 'قطعة' : unitText,
      brandName: brandName.isEmpty ? 'عام' : brandName,
      price: price,
    );
  }

  static double? _parsePriceText(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(',', '')
        .replaceAll('ج.م', '')
        .replaceAll('جنيه', '')
        .trim();
    return double.tryParse(_toEnglishDigits(cleaned));
  }

  static CatalogCsvRow? _parseRowColumns(List<String> cols) {
    if (cols.length < 6) return null;

    final categoryName = cols[0].trim();
    final itemName = cols[1].trim();
    final sizeText = cols[2].trim();
    final unitText = cols[3].trim();
    final brandName = cols[4].trim();
    final price = _parsePriceText(cols[5]);

    if (categoryName.isEmpty ||
        itemName.isEmpty ||
        brandName.isEmpty ||
        price == null ||
        price < 0) {
      return null;
    }

    final normalizedSize =
        (sizeText.isEmpty || sizeText == 'غير مذكور' || sizeText == '-')
            ? null
            : sizeText;

    return CatalogCsvRow(
      categoryName: categoryName,
      itemName: itemName,
      size: normalizedSize,
      unit: unitText.isEmpty ? 'قطعة' : unitText,
      brandName: brandName,
      price: price,
    );
  }

  static String _decodeArchiveXml(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) {
      return utf8.decode(content, allowMalformed: true);
    }
    if (content is List<int>) {
      return utf8.decode(content, allowMalformed: true);
    }
    return '';
  }

  static List<String> _readSharedStrings(ArchiveFile? file) {
    if (file == null) return const [];
    try {
      final doc = XmlDocument.parse(_decodeArchiveXml(file));
      final strings = <String>[];
      for (final si in doc.findAllElements('si', namespace: '*')) {
        strings.add(_extractXmlTextRuns(si));
      }
      return strings;
    } catch (_) {
      return const [];
    }
  }

  static String _extractXmlTextRuns(XmlElement parent) {
    final buf = StringBuffer();
    for (final child in parent.children.whereType<XmlElement>()) {
      if (child.name.local == 't') {
        buf.write(child.innerText);
      } else if (child.name.local == 'r') {
        for (final rChild in child.children.whereType<XmlElement>()) {
          if (rChild.name.local == 't') {
            buf.write(rChild.innerText);
          }
        }
      }
    }
    return buf.toString();
  }

  static List<_SheetInfo> _resolveWorksheetInfos(
    Map<String, ArchiveFile> fileByPath,
  ) {
    final resolved = <_SheetInfo>[];
    final wbFile = fileByPath['xl/workbook.xml'];
    final relsFile = fileByPath['xl/_rels/workbook.xml.rels'];

    if (wbFile != null && relsFile != null) {
      try {
        final relMap = <String, String>{};
        final relDoc = XmlDocument.parse(_decodeArchiveXml(relsFile));
        for (final rel
            in relDoc.findAllElements('Relationship', namespace: '*')) {
          final id = rel.getAttribute('Id');
          final target = rel.getAttribute('Target');
          if (id == null || target == null) continue;
          var norm = target
              .replaceAll('\\', '/')
              .replaceFirst(RegExp(r'^/+'), '')
              .toLowerCase();
          if (!norm.startsWith('xl/')) {
            norm = 'xl/$norm';
          }
          relMap[id] = norm;
        }

        final wbDoc = XmlDocument.parse(_decodeArchiveXml(wbFile));
        for (final sheet in wbDoc.findAllElements('sheet', namespace: '*')) {
          String? rid;
          for (final attr in sheet.attributes) {
            if (attr.name.local == 'id') {
              rid = attr.value;
              break;
            }
          }
          if (rid != null) {
            final target = relMap[rid];
            if (target != null && fileByPath.containsKey(target)) {
              final sheetName =
                  sheet.getAttribute('name')?.trim() ?? 'Sheet${resolved.length + 1}';
              resolved.add(_SheetInfo(name: sheetName, path: target));
            }
          }
        }
      } catch (_) {
        resolved.clear();
      }
    }

    if (resolved.isNotEmpty) return resolved;

    final fallback = fileByPath.keys
        .where((p) => p.startsWith('xl/worksheets/') && p.endsWith('.xml'))
        .toList()
      ..sort((a, b) {
        final na = int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(a)?.group(1) ?? '') ?? 0;
        final nb = int.tryParse(RegExp(r'(\d+)\.xml$').firstMatch(b)?.group(1) ?? '') ?? 0;
        return na != nb ? na.compareTo(nb) : a.compareTo(b);
      });
    return [
      for (var i = 0; i < fallback.length; i++)
        _SheetInfo(name: 'Sheet${i + 1}', path: fallback[i]),
    ];
  }

  static _ParsedSheetData _readWorksheetData(
    ArchiveFile file,
    List<String> sharedStrings,
  ) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(_decodeArchiveXml(file));
    } catch (_) {
      return const _ParsedSheetData(
        grid: [],
        cellsByRef: {},
        formulaSlots: [],
      );
    }

    final grid = <List<String>>[];
    final cellsByRef = <String, _RawSheetCell>{};
    final formulaSlots = <_FormulaSlot>[];
    var fallbackRowNum = 1;

    for (final rowElem in doc.findAllElements('row', namespace: '*')) {
      final rowCells = <String>[];
      final rowAttr = rowElem.getAttribute('r');
      final rowNum = int.tryParse(rowAttr ?? '') ?? fallbackRowNum;
      fallbackRowNum = rowNum + 1;
      final rowIdx = grid.length;
      var fallbackCol = 0;

      for (final c in rowElem.children.whereType<XmlElement>()) {
        if (c.name.local != 'c') continue;
        final rawRef = c.getAttribute('r')?.trim();
        final colIdx = rawRef != null ? _colIndexFromRef(rawRef) : fallbackCol;
        fallbackCol = colIdx + 1;
        final cellRef = (rawRef != null && rawRef.isNotEmpty)
            ? rawRef.toUpperCase()
            : '${_colLettersFromIndex(colIdx)}$rowNum';

        while (rowCells.length <= colIdx) {
          rowCells.add('');
        }
        final cell = _readSheetCell(c, sharedStrings);
        cellsByRef[cellRef] = cell;
        rowCells[colIdx] = cell.value;

        if (cell.value.isEmpty && cell.formula != null) {
          formulaSlots.add(
            _FormulaSlot(rowIdx: rowIdx, colIdx: colIdx, cellRef: cellRef),
          );
        }
      }

      grid.add(rowCells);
    }

    return _ParsedSheetData(
      grid: grid,
      cellsByRef: cellsByRef,
      formulaSlots: formulaSlots,
    );
  }

  static int _colIndexFromRef(String ref) {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(ref);
    if (match == null) return 0;
    final letters = match.group(0)!.toUpperCase();
    var idx = 0;
    for (var i = 0; i < letters.length; i++) {
      idx = idx * 26 + (letters.codeUnitAt(i) - 64);
    }
    return idx - 1;
  }

  static String _colLettersFromIndex(int idx) {
    var n = idx + 1;
    final buf = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      buf.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }

  static _RawSheetCell _readSheetCell(XmlElement c, List<String> sharedStrings) {
    final type = c.getAttribute('t');
    if (type == 'e') return const _RawSheetCell(value: '');

    if (type == 'inlineStr') {
      for (final child in c.children.whereType<XmlElement>()) {
        if (child.name.local == 'is') {
          return _RawSheetCell(value: _extractXmlTextRuns(child).trim());
        }
      }
      return const _RawSheetCell(value: '');
    }

    var rawV = '';
    String? formula;
    for (final child in c.children.whereType<XmlElement>()) {
      if (child.name.local == 'v') {
        rawV = child.innerText.trim();
      } else if (child.name.local == 'f') {
        final f = child.innerText.trim();
        if (f.isNotEmpty) formula = f;
      }
    }

    if (rawV.isEmpty) {
      return _RawSheetCell(value: '', formula: formula);
    }

    if (type == 's') {
      final idx = int.tryParse(rawV);
      if (idx != null && idx >= 0 && idx < sharedStrings.length) {
        return _RawSheetCell(value: sharedStrings[idx].trim(), formula: formula);
      }
      return _RawSheetCell(value: '', formula: formula);
    }
    if (type == 'b') {
      return _RawSheetCell(
        value: rawV == '1' ? 'TRUE' : 'FALSE',
        formula: formula,
      );
    }
    return _RawSheetCell(value: rawV, formula: formula);
  }

  /// Generates RFC-4180 CSV with UTF-8 BOM so Microsoft Excel opens Arabic properly.
  static String exportCatalogCsv(CatalogState catalog) {
    final buf = StringBuffer('\uFEFF')
      ..writeln('القسم,اسم الصنف,المقاس,الوحدة,الشركة,السعر التجاري,سعر البيع');

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
            '',
            '0',
          ].join(','),
        );
        continue;
      }

      for (final variant in variants) {
        final brandName = brandById[variant.brandId]?.name ?? 'غير محدد';
        final commercialStr = variant.commercialPrice != null
            ? variant.commercialPrice!
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'\.00$'), '')
            : '';
        buf.writeln(
          [
            _csvCell(catName),
            _csvCell(template.name),
            _csvCell(template.size ?? ''),
            _csvCell(template.unit),
            _csvCell(brandName),
            commercialStr,
            variant.price.toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), ''),
          ].join(','),
        );
      }
    }

    return buf.toString();
  }

  static List<String> _splitDelimitedLine(String line, String delimiter) {
    if (delimiter == '\t' || delimiter == ';') {
      return line.split(delimiter).map((c) => c.trim()).toList();
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

class _HeaderColMap {
  const _HeaderColMap({
    this.categoryIdx,
    required this.itemIdx,
    this.sizeIdx,
    this.unitIdx,
    this.brandIdx,
    required this.priceIdx,
  });

  final int? categoryIdx;
  final int itemIdx;
  final int? sizeIdx;
  final int? unitIdx;
  final int? brandIdx;
  final int priceIdx;
}

class _SheetInfo {
  const _SheetInfo({required this.name, required this.path});
  final String name;
  final String path;
}

class _RawSheetCell {
  const _RawSheetCell({required this.value, this.formula});
  final String value;
  final String? formula;
}

class _FormulaSlot {
  const _FormulaSlot({
    required this.rowIdx,
    required this.colIdx,
    required this.cellRef,
  });
  final int rowIdx;
  final int colIdx;
  final String cellRef;
}

class _ParsedSheetData {
  const _ParsedSheetData({
    required this.grid,
    required this.cellsByRef,
    required this.formulaSlots,
  });
  final List<List<String>> grid;
  final Map<String, _RawSheetCell> cellsByRef;
  final List<_FormulaSlot> formulaSlots;
}

class _SheetFormulaEvaluator {
  _SheetFormulaEvaluator(this.sheetsByName);

  final Map<String, Map<String, _RawSheetCell>> sheetsByName;
  final Map<String, double?> _cache = {};
  final Set<String> _visiting = {};

  Map<String, _RawSheetCell>? _findSheetCells(String sheetName) {
    final direct = sheetsByName[sheetName];
    if (direct != null) return direct;
    final lower = sheetName.toLowerCase();
    for (final entry in sheetsByName.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  double? evalCell(String sheetName, String cellRef) {
    final cleanRef = cellRef.replaceAll(r'$', '').toUpperCase();
    final key = '$sheetName!$cleanRef';
    if (_cache.containsKey(key)) return _cache[key];
    if (_visiting.contains(key)) return null;

    final cells = _findSheetCells(sheetName);
    final cell = cells?[cleanRef];
    if (cell == null) {
      _cache[key] = null;
      return null;
    }

    if (cell.value.isNotEmpty) {
      final numVal = CatalogCsvService._parsePriceText(cell.value);
      _cache[key] = numVal;
      return numVal;
    }

    final formula = cell.formula;
    if (formula == null || formula.isEmpty) {
      _cache[key] = null;
      return null;
    }

    _visiting.add(key);
    final result = _evalExpression(formula, sheetName);
    _visiting.remove(key);
    _cache[key] = result;
    return result;
  }

  double? _evalExpression(String formula, String currentSheet) {
    final expr = formula.trim().startsWith('=')
        ? formula.trim().substring(1)
        : formula.trim();
    if (expr.isEmpty) return null;
    final parser = _FormulaParser(expr, currentSheet, this);
    final value = parser.parseExpression();
    parser.skipWhitespace();
    if (!parser.isAtEnd || value == null || !value.isFinite) return null;
    return value;
  }
}

class _FormulaParser {
  _FormulaParser(this.input, this.currentSheet, this.evaluator);

  final String input;
  final String currentSheet;
  final _SheetFormulaEvaluator evaluator;
  int pos = 0;

  bool get isAtEnd => pos >= input.length;

  void skipWhitespace() {
    while (pos < input.length && input[pos].trim().isEmpty) {
      pos++;
    }
  }

  double? parseExpression() {
    final first = parseTerm();
    if (first == null) return null;
    var left = first;
    while (true) {
      skipWhitespace();
      if (pos >= input.length) break;
      final op = input[pos];
      if (op != '+' && op != '-') break;
      pos++;
      final right = parseTerm();
      if (right == null) return null;
      left = op == '+' ? left + right : left - right;
    }
    return left;
  }

  double? parseTerm() {
    final first = parseFactor();
    if (first == null) return null;
    var left = first;
    while (true) {
      skipWhitespace();
      if (pos >= input.length) break;
      final op = input[pos];
      if (op != '*' && op != '/') break;
      pos++;
      final right = parseFactor();
      if (right == null) return null;
      if (op == '/') {
        if (right == 0) return null;
        left = left / right;
      } else {
        left = left * right;
      }
    }
    return left;
  }

  double? parseFactor() {
    skipWhitespace();
    if (pos >= input.length) return null;

    if (input[pos] == '+' || input[pos] == '-') {
      final sign = input[pos] == '-' ? -1.0 : 1.0;
      pos++;
      final inner = parseFactor();
      return inner != null ? sign * inner : null;
    }

    if (input[pos] == '(') {
      pos++;
      final inner = parseExpression();
      skipWhitespace();
      if (pos < input.length && input[pos] == ')') {
        pos++;
      }
      return _applyPercentSuffix(inner);
    }

    // Quoted sheet reference: 'Sheet Name'!$A$1
    if (input[pos] == "'") {
      final ref = _parseQuotedSheetRef();
      return _applyPercentSuffix(ref);
    }

    // Number literal
    if (RegExp(r'[0-9.]').hasMatch(input[pos])) {
      final start = pos;
      while (pos < input.length && RegExp(r'[0-9.]').hasMatch(input[pos])) {
        pos++;
      }
      final numVal = double.tryParse(input.substring(start, pos));
      return _applyPercentSuffix(numVal);
    }

    // Identifier: function call (ROUND/ROUNDUP/ROUNDDOWN) or cell/sheet ref
    final identStart = pos;
    while (pos < input.length &&
        !RegExp(r'[\s+\-*/(),!%]').hasMatch(input[pos])) {
      pos++;
    }
    final ident = input.substring(identStart, pos);
    if (ident.isEmpty) return null;

    skipWhitespace();
    if (pos < input.length && input[pos] == '!') {
      pos++;
      final cellRef = _readCellToken();
      if (cellRef == null) return null;
      return _applyPercentSuffix(evaluator.evalCell(ident, cellRef));
    }

    if (pos < input.length && input[pos] == '(') {
      return _applyPercentSuffix(_parseFunctionCall(ident.toUpperCase()));
    }

    final cleanCell = ident.replaceAll(r'$', '');
    if (RegExp(r'^[A-Za-z]+\d+$').hasMatch(cleanCell)) {
      return _applyPercentSuffix(evaluator.evalCell(currentSheet, cleanCell));
    }

    return null;
  }

  double? _applyPercentSuffix(double? value) {
    if (value == null) return null;
    skipWhitespace();
    if (pos < input.length && input[pos] == '%') {
      pos++;
      return value / 100.0;
    }
    return value;
  }

  double? _parseQuotedSheetRef() {
    pos++; // skip opening quote
    final buf = StringBuffer();
    while (pos < input.length) {
      if (input[pos] == "'") {
        if (pos + 1 < input.length && input[pos + 1] == "'") {
          buf.write("'");
          pos += 2;
        } else {
          pos++;
          break;
        }
      } else {
        buf.write(input[pos]);
        pos++;
      }
    }
    skipWhitespace();
    if (pos >= input.length || input[pos] != '!') return null;
    pos++;
    final cellRef = _readCellToken();
    if (cellRef == null) return null;
    return evaluator.evalCell(buf.toString(), cellRef);
  }

  String? _readCellToken() {
    skipWhitespace();
    final start = pos;
    while (pos < input.length && RegExp(r'[A-Za-z0-9$]').hasMatch(input[pos])) {
      pos++;
    }
    final token = input.substring(start, pos).replaceAll(r'$', '');
    return RegExp(r'^[A-Za-z]+\d+$').hasMatch(token) ? token : null;
  }

  double? _parseFunctionCall(String fnName) {
    pos++; // skip '('
    final args = <double?>[];
    skipWhitespace();
    if (pos < input.length && input[pos] != ')') {
      while (true) {
        args.add(parseExpression());
        skipWhitespace();
        if (pos < input.length && (input[pos] == ',' || input[pos] == ';')) {
          pos++;
          continue;
        }
        break;
      }
    }
    if (pos < input.length && input[pos] == ')') {
      pos++;
    }

    if (args.isEmpty || args.first == null) return null;
    final val = args.first!;
    final digits = args.length > 1 && args[1] != null ? args[1]!.round() : 0;
    final factor = math.pow(10, digits).toDouble();
    if (factor == 0) return val;

    return switch (fnName) {
      'ROUND' => (val * factor).round() / factor,
      'ROUNDUP' => (val >= 0 ? (val * factor).ceil() : (val * factor).floor()) /
          factor,
      'ROUNDDOWN' =>
        (val >= 0 ? (val * factor).floor() : (val * factor).ceil()) / factor,
      _ => null,
    };
  }
}
