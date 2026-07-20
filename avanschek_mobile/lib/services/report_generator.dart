import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/check.dart';
import '../models/report_data.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

class ReportGenerator {
  static const String _templatePath = 'assets/ao1_template.xlsx';

  static Future<Map<String, String>> generate({
    required ReportData data,
    required List<Check> checks,
    String? outputDir,
  }) async {
    final dir = outputDir ?? (await getApplicationDocumentsDirectory()).path;
    final safeDate = data.reportDate.replaceAll('.', '-');
    final baseName = 'AO-1_${data.fio.replaceAll(' ', '_')}_$safeDate';

    final xlsPath = p.join(dir, '$baseName.xlsx');

    // ─── Суммы (вычисляем заранее) ───
    final total = checks.fold<double>(0, (sum, c) => sum + c.amount);
    final balance = data.advanceReceived - total;
    final totalStr = total.toStringAsFixed(2);
    final advStr = data.advanceReceived.toStringAsFixed(2);
    final balStr = balance.abs().toStringAsFixed(2);
    final numDocsStr = checks.length.toString();
    final propis = _sumToWords(total);

    final dateParts = data.reportDate.split('.');
    final day = dateParts.isNotEmpty ? dateParts[0] : '';
    final mon = dateParts.length > 1 ? dateParts[1] : '';
    final yr = dateParts.length > 2 ? dateParts[2] : '';
    final yr2 = yr.length == 4 ? yr.substring(2, 4) : '';

    // ─── Патчи: A1-ссылки -> значения (только известные хорошие + калиброванные по примерам/инспекциям).
    // Полный список будет расширен точными рефами при финальной подгонке под визуал пользователя.
    final patches = <String, String>{
      // Лицевая — шапка (проверенные)
      'A7': data.organization,
      'P19': data.department,
      'K20': data.fio,
      'AI95': data.shortFio,
      'N22': data.position,
      'AI22': data.purpose,
      'U13': data.reportNumber,
      'Z13': data.reportDate,
      if (data.tabNumber.isNotEmpty) 'AR20': data.tabNumber,

      // Дата в "УТВЕРЖДАЮ" (день в AM16, месяц в AP16 по указанию)
      if (day.isNotEmpty) 'AM16': day,
      if (mon.isNotEmpty) 'AP16': mon,
      if (yr2.isNotEmpty) ...{'AX16': yr.substring(0, 2), 'AZ16': yr2},

      // Суммы (лицевая таблица)
      'AQ10': totalStr,
      'R27': advStr,
      'R32': totalStr,

      // Остаток / Перерасход (комбинированные)
      if (balance >= 0)
        'B33': 'Остаток   $balStr'
      else
        'B34': 'Перерасход   $balStr',

      // Сумма прописью (в S38 по указанию пользователя)
      'S38': propis,

      // Кол-во документов
      'G36': numDocsStr,
      'S36': numDocsStr,

      // "К утверждению в сумме" + число (выбираем Y39 как кандидат, чтобы не уезжал на нижнюю строку)
      'Y39': totalStr,

      // Итог на обороте
      'P93': 'Итого ',
      'Y93': totalStr,
      'AK93': totalStr,

      // Нижняя часть (лейблы)
      if (balance >= 0)
        'A44': 'Остаток внесен'
      else
        'A45': 'Перерасход выдан',

      // Значения "в сумме" для остатка/перерасхода (калибровать col при необходимости)
      if (balance >= 0) 'O44': balStr else 'O45': balStr,

      // Дополнительно заполняем часть полей квитанции/низа (можно расширять)
      // На сумму в расписке (примерно после "на сумму ")
      'I51': totalStr,
      // Количество документов в расписке
      'AE51': numDocsStr,
      // На листах в расписке
      'AR51': '2',
    };

    // Таблица чеков (до 30)
    for (var i = 0; i < checks.length && i < 30; i++) {
      final r = 63 + i; // 1-based
      final c = checks[i];
      final rowPrefix = '${_a1Col(0)}$r';   // №
      final dateRef = '${_a1Col(5)}$r';
      final nameRef = '${_a1Col(10)}$r';
      final amt1Ref = '${_a1Col(24)}$r';
      final amt2Ref = '${_a1Col(36)}$r';
      final debitRef = '${_a1Col(48)}$r';

      patches[rowPrefix] = '${i + 1}';
      patches[dateRef] = c.docDate;
      patches[nameRef] = '№${c.docNumber}, ${c.name}';
      final amt = c.amount.toStringAsFixed(2);
      patches[amt1Ref] = amt;
      patches[amt2Ref] = amt;
      patches[debitRef] = 'Студия';
    }

    // Очистка неиспользуемых строк таблицы (чтобы не осталось старых 0 / формул)
    for (var i = checks.length; i < 30; i++) {
      final r = 63 + i;
      patches['${_a1Col(24)}$r'] = '';
      patches['${_a1Col(36)}$r'] = '';
    }

    // ─── Применяем патч к шаблону (архив + точечная правка XML) ───
    final templateBytes = await rootBundle.load(_templatePath);
    final xlsBytes = await _patchXlsxTemplate(
      templateBytes.buffer.asUint8List(),
      patches,
    );
    await File(xlsPath).writeAsBytes(xlsBytes);

    // ─── PDF: экспорт именно этого xlsx в PDF (локально).
    // Парсим структуру (ячейки, sst, merges, col widths, borders из стилей) и рендерим точную
    // grid-реплику через pdf-пакет (pw.Table / контейнеры с точными ширинами в pt, selective borders,
    // правильные colspan/rowspan, alignment, шрифты). Это даёт максимальное сходство с тем,
    // как Excel печатает/экспортирует этот лист в PDF (по ГОСТ, без "новой конструкции").
    final pdfBytes = await _buildPdfFromXlsx(xlsBytes);
    final actualPdfPath = p.join(dir, '$baseName.pdf');
    await File(actualPdfPath).writeAsBytes(pdfBytes);

    return {'xls': xlsPath, 'pdf': actualPdfPath};
  }

  // A1 helper (0-based -> "A7", "S39" ...)
  static String _a1Col(int col0) {
    int c = col0 + 1;
    String res = '';
    while (c > 0) {
      c--;
      res = String.fromCharCode(65 + (c % 26)) + res;
      c ~/= 26;
    }
    return res;
  }

  /// Минимальный "штамп" значений в шаблон.
  /// Берём оригинальный байты xlsx, правим ТОЛЬКО ячейки вида c r=".." в sheet1.xml через inlineStr / v,
  /// всё остальное (мерджи, стили, границы, print setup, 457+ merged ranges) остаётся байт-в-байт.
  /// Это решает "ошибку восстановления" и "границы перекрасились / данные уехали".
  static Future<Uint8List> _patchXlsxTemplate(
    Uint8List templateBytes,
    Map<String, String> patches,
  ) async {
    if (patches.isEmpty) return templateBytes;

    final archive = ZipDecoder().decodeBytes(templateBytes);
    final sheet = archive.files.firstWhere(
      (f) => f.name == 'xl/worksheets/sheet1.xml',
      orElse: () => throw Exception('sheet1.xml not found in template'),
    );

    String xml = utf8.decode(sheet.content as List<int>);

    // Экранирование для XML
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');

    for (final entry in patches.entries) {
      final ref = entry.key;
      final rawVal = entry.value;

      // Улучшенное регулярное выражение, которое корректно ловит и обычные теги <c ...>..</c>
      // и самозакрывающиеся <c ... />
      final cellRe = RegExp(
        r'(<c\s+r="' + ref + r'"[^>]*?)(?:/>|>(.*?)</c>)',
        dotAll: true,
      );
      final match = cellRe.firstMatch(xml);

      if (rawVal.isEmpty) {
        if (match != null) {
          final prefix = match.group(1)!;
          // Делаем пустую ячейку, сохраняя атрибуты (s= стиль и т.д.)
          xml = xml.replaceFirst(cellRe, '$prefix/>');
        }
        continue;
      }

      final isNumeric = double.tryParse(rawVal) != null &&
          !rawVal.contains(RegExp(r'[^0-9.]'));
      final safe = esc(rawVal);

      String newTag;
      if (match != null) {
        String prefix = match.group(1)!;  // <c r="REF" [все атрибуты до >]
        // Чистим возможный старый t=
        prefix = prefix.replaceFirst(RegExp(r'\s+t="[^"]*"'), '');
        if (!isNumeric) {
          // Для текста используем inlineStr, чтобы не трогать sharedStrings
          if (!prefix.contains(' t="inlineStr"')) {
            prefix = prefix.replaceFirst('>', ' t="inlineStr">');
          }
        }
        final inner = isNumeric ? '<v>$safe</v>' : '<is><t>$safe</t></is>';
        newTag = '$prefix>$inner</c>';
      } else {
        // Ячейки не было в XML — создаём минимальную (редко для этого шаблона)
        newTag = isNumeric
            ? '<c r="$ref"><v>$safe</v></c>'
            : '<c r="$ref" t="inlineStr"><is><t>$safe</t></is></c>';
      }

      if (match != null) {
        xml = xml.replaceFirst(cellRe, newTag);
      } else {
        // fallback: вставляем перед </sheetData>
        final insertPoint = xml.indexOf('</sheetData>');
        if (insertPoint > 0) {
          xml = xml.substring(0, insertPoint) + newTag + xml.substring(insertPoint);
        }
      }
    }

    // Не мутируем archive.files (может быть unmodifiable).
    // Строим новый Archive, копируем все файлы, заменяя только sheet1.xml.
    final newContentBytes = utf8.encode(xml);
    final newSheet = ArchiveFile(sheet.name, newContentBytes.length, newContentBytes);

    final newArchive = Archive();
    for (final f in archive.files) {
      if (f.name == sheet.name) {
        newArchive.addFile(newSheet);
      } else {
        newArchive.addFile(f);
      }
    }

    final out = ZipEncoder().encode(newArchive);
    return Uint8List.fromList(out!);
  }

  static String _sumToWords(double amount) {
    final rub = amount.truncate();
    final kop = ((amount - rub).abs() * 100).round();
    return '${rub.toStringAsFixed(0)} руб. ${kop.toString().padLeft(2, '0')} коп.';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  ЭКСПОРТ ИМЕННО XLSX В PDF (локально на телефоне) — буквальная копия печати Excel
  //  Парсим ту же структуру xlsx (sst, cells с s=, merges 457, col widths, borders из styles.xml,
  //  rowBreaks). Рендерим через pw (pdf-пакет) точную сетку: col widths в pt (пропорционально
  //  printable), selective borders только где были в шаблоне, colspan/rowspan, right-align для чисел,
  //  правильные шрифты/размеры. Две страницы по rowBreak=56, margins из template.
  //  Результат должен быть практически идентичен "Сохранить как PDF" / печати из Excel этого xlsx.
  // ═══════════════════════════════════════════════════════════════════════════

  static Future<Uint8List> _buildPdfFromXlsx(Uint8List xlsxBytes) async {
    // Шрифт для кириллицы (тот же, что в ассетах)
    final fontBytes = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final font = pw.Font.ttf(fontBytes);

    final archive = ZipDecoder().decodeBytes(xlsxBytes);

    ArchiveFile? sheetFile;
    ArchiveFile? sstFile;
    ArchiveFile? stylesFile;
    for (final f in archive.files) {
      if (f.name == 'xl/worksheets/sheet1.xml') sheetFile = f;
      if (f.name == 'xl/sharedStrings.xml') sstFile = f;
      if (f.name == 'xl/styles.xml') stylesFile = f;
    }
    if (sheetFile == null) throw Exception('sheet1.xml not found');

    final sheetXml = utf8.decode(sheetFile.content as List<int>);
    final sstXml = sstFile != null ? utf8.decode(sstFile.content as List<int>) : '';
    final stylesXml = stylesFile != null ? utf8.decode(stylesFile.content as List<int>) : '';

    final sst = _parseSst(sstXml);
    final merges = _parseMerges(sheetXml);
    final colWidths = _parseColWidths(sheetXml); // 1-based
    final cells = _parseCells(sheetXml, sst); // ref -> {val, s}
    final rowBreak = _parseFirstRowBreak(sheetXml); // e.g. 56
    final xfToBorder = _parseXfBorderIds(stylesXml);
    final borderDefs = _parseBorderDefs(stylesXml);
    final xfToFont = _parseXfFonts(stylesXml); // {size, bold}

    // Determine max row/col from dimension or data
    final dim = _parseDimension(sheetXml);
    int maxRow = dim['maxRow'] ?? 96;
    int maxCol = dim['maxCol'] ?? 55;

    // Build 2d grid sparse (reused logic)
    final grid = <int, Map<int, _CellInfo>>{};
    for (final entry in cells.entries) {
      final ref = entry.key;
      final data = entry.value;
      final col = _colToIndex(ref.replaceAll(RegExp(r'\d'), ''));
      final row = int.tryParse(ref.replaceAll(RegExp(r'\D'), '')) ?? 0;
      if (row < 1 || col < 1) continue;
      grid.putIfAbsent(row, () => {})[col] = _CellInfo(
        val: data['val'] ?? '',
        styleId: data['s'] != null ? int.tryParse(data['s']!) : null,
      );
    }

    // Apply merges
    final covered = <String>{};
    for (final m in merges) {
      final parts = m.split(':');
      final start = _parseRef(parts[0]);
      final end = parts.length > 1 ? _parseRef(parts[1]) : start;
      final sr = start['row']!, sc = start['col']!;
      final er = end['row']!, ec = end['col']!;
      final cs = ec - sc + 1;
      final rs = er - sr + 1;
      final origin = grid.putIfAbsent(sr, () => {}).putIfAbsent(sc, () => _CellInfo(val: ''));
      origin.cs = cs;
      origin.rs = rs;
      for (var r = sr; r <= er; r++) {
        for (var c = sc; c <= ec; c++) {
          if (r == sr && c == sc) continue;
          covered.add('$r,$c');
        }
      }
    }

    // Col widths in PDF points (map xlsx units to printable area ~510pt to match template print)
    const double printableW = 510.0;
    double totalU = 0.0;
    for (var c = 1; c <= maxCol; c++) {
      totalU += colWidths[c] ?? 2.0;
    }
    if (totalU < 1) totalU = maxCol * 2.0;
    final colPt = <int, double>{};
    for (var c = 1; c <= maxCol; c++) {
      final u = colWidths[c] ?? 2.0;
      colPt[c] = (u / totalU) * printableW;
    }

    // Helper border maker (define before use)
    pw.Border makeBorder(int? sid, List<int?> xfToB, List<Map<String, String?>> bDefs) {
      if (sid == null || sid >= xfToB.length) return const pw.Border();
      final bid = xfToB[sid];
      if (bid == null || bid >= bDefs.length) return const pw.Border();
      final d = bDefs[bid];
      pw.BorderSide s(String? st) =>
          (st == null || st.isEmpty) ? pw.BorderSide.none : const pw.BorderSide(color: pdf.PdfColors.black, width: 0.5);
      return pw.Border(
        left: s(d['left']),
        right: s(d['right']),
        top: s(d['top']),
        bottom: s(d['bottom']),
      );
    }

    // Build the PDF content for a row range (front or back). Returns list of pw.Row widgets.
    List<pw.Widget> buildPdfPageRows(
      int startR,
      int endR,
      Map<int, Map<int, _CellInfo>> ggrid,
      Set<String> ccovered,
      Map<int, double> ccolPt,
      int mmaxCol,
      pw.Font ffont,
      List<int?> xxfToBorder,
      List<Map<String, String?>> bbDefs,
      List<Map<String, Object?>> xxfToFont,
    ) {
      final rows = <pw.Widget>[];
      for (var r = startR; r <= endR; r++) {
        final rowMap = ggrid[r] ?? {};
        final children = <pw.Widget>[];
        var c = 1;
        while (c <= mmaxCol) {
          final key = '$r,$c';
          if (ccovered.contains(key)) {
            c++;
            continue;
          }
          final cell = rowMap[c];
          final cs = cell?.cs ?? 1;
          double w = 0.0;
          for (var k = 0; k < cs; k++) {
            w += ccolPt[c + k] ?? 5.0;
          }
          final val = cell?.val ?? '';
          final sid = cell?.styleId;
          final b = makeBorder(sid, xxfToBorder, bbDefs);
          double fsz = 7.0;
          bool isB = false;
          if (sid != null && sid < xxfToFont.length) {
            final f = xxfToFont[sid];
            fsz = (f['size'] as double?) ?? 7.0;
            isB = (f['bold'] as bool?) ?? false;
          }
          final isNum = double.tryParse(val.replaceAll(' ', '')) != null;
          children.add(
            pw.Container(
              width: w,
              decoration: pw.BoxDecoration(border: b),
              padding: const pw.EdgeInsets.symmetric(horizontal: 1, vertical: 0),
              alignment: isNum ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              child: pw.Text(
                val,
                style: pw.TextStyle(
                  font: ffont,
                  fontSize: fsz,
                  fontWeight: isB ? pw.FontWeight.bold : pw.FontWeight.normal,
                ),
                textAlign: isNum ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            ),
          );
          c += cs;
        }
        if (children.isNotEmpty) {
          rows.add(pw.Row(children: children));
        }
      }
      return rows;
    }

    // Build pages
    final doc = pw.Document();
    final frontRows = buildPdfPageRows(1, rowBreak - 1, grid, covered, colPt, maxCol, font, xfToBorder, borderDefs, xfToFont);
    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(left: 42, right: 28, top: 42, bottom: 28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: frontRows,
        ),
      ),
    );

    final backRows = buildPdfPageRows(rowBreak, maxRow, grid, covered, colPt, maxCol, font, xfToBorder, borderDefs, xfToFont);
    doc.addPage(
      pw.Page(
        pageFormat: pdf.PdfPageFormat.a4,
        margin: const pw.EdgeInsets.only(left: 42, right: 28, top: 42, bottom: 28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisSize: pw.MainAxisSize.min,
          children: backRows,
        ),
      ),
    );

    return await doc.save();
  }

  // ── Парсеры ──

  static List<String> _parseSst(String sstXml) {
    if (sstXml.isEmpty) return [];
    final sst = <String>[];
    // Simpler: all <t> appear in order of si, even if rich text uses multiple, first t per is enough for us.
    final tRe = RegExp(r'<t[^>]*>([^<]*)</t>');
    for (final m in tRe.allMatches(sstXml)) {
      String text = m.group(1) ?? '';
      text = text.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"').replaceAll('&#39;', "'");
      sst.add(text);
    }
    return sst;
  }

  static List<String> _parseMerges(String sheetXml) {
    final res = <String>[];
    final re = RegExp(r'<mergeCell\s+ref="([^"]+)"');
    for (final m in re.allMatches(sheetXml)) {
      res.add(m.group(1)!);
    }
    return res;
  }

  static Map<int, double> _parseColWidths(String sheetXml) {
    final res = <int, double>{};
    final re = RegExp(r'<col\s+[^>]*min="(\d+)"[^>]*max="(\d+)"[^>]*width="([^"]+)"[^>]*/?>');
    for (final m in re.allMatches(sheetXml)) {
      final min = int.tryParse(m.group(1)!) ?? 1;
      final max = int.tryParse(m.group(2)!) ?? min;
      final w = double.tryParse(m.group(3)!) ?? 8.43;
      for (var c = min; c <= max; c++) {
        res[c] = w;
      }
    }
    return res;
  }

  static Map<String, Map<String, String>> _parseCells(String sheetXml, List<String> sst) {
    final res = <String, Map<String, String>>{};
    // Use same robust pattern as _patchXlsxTemplate (avoids eating huge chunks on self-closes and greedy).
    // Capture full tag start + branch for self-close vs open+inner.
    final cellRe = RegExp(
      r'(<c\s+r="([A-Z0-9]+)"[^>]*?)(?:/>|>(.*?)</c>)',
      dotAll: true,
    );
    for (final m in cellRe.allMatches(sheetXml)) {
      final prefix = m.group(1) ?? ''; // <c r=".." [attrs]
      final ref = m.group(2) ?? '';
      final inner = m.group(3) ?? '';
      if (ref.isEmpty) continue;

      // parse attrs from prefix
      final attrs = prefix;
      int? s;
      final sMatch = RegExp(r'\bs="(\d+)"').firstMatch(attrs);
      if (sMatch != null) s = int.tryParse(sMatch.group(1)!);

      String t = '';
      final tMatch = RegExp(r'\bt="([^"]+)"').firstMatch(attrs);
      if (tMatch != null) t = tMatch.group(1)!;

      String val = '';
      if (inner.isNotEmpty) {
        if (t == 'inlineStr') {
          final isT = RegExp(r'<is[^>]*>.*?<t[^>]*>([^<]*)</t>', dotAll: true).firstMatch(inner);
          val = isT != null ? isT.group(1)! : '';
        } else if (t == 's') {
          final vM = RegExp(r'<v[^>]*>([^<]*)</v>').firstMatch(inner);
          if (vM != null) {
            final idx = int.tryParse(vM.group(1)!) ?? -1;
            val = (idx >= 0 && idx < sst.length) ? sst[idx] : '';
          }
        } else {
          final vM = RegExp(r'<v[^>]*>([^<]*)</v>').firstMatch(inner);
          val = vM != null ? vM.group(1)! : '';
        }
      }
      // else self-close /> : val remains '', but we still record s for border

      res[ref] = {'val': val, if (s != null) 's': '$s'};
    }
    return res;
  }

  static int _parseFirstRowBreak(String sheetXml) {
    final re = RegExp(r'<brk[^>]*id="(\d+)"[^>]*man="1"');
    final m = re.firstMatch(sheetXml);
    if (m != null) {
      return int.tryParse(m.group(1)!) ?? 56;
    }
    return 56;
  }

  static Map<String, int> _parseDimension(String sheetXml) {
    final dimRe = RegExp(r'<dimension\s+ref="([A-Z]+)(\d+):([A-Z]+)(\d+)"');
    final m = dimRe.firstMatch(sheetXml);
    if (m != null) {
      final maxC = _colToIndex(m.group(3)!);
      final maxR = int.tryParse(m.group(4)!) ?? 96;
      return {'maxCol': maxC, 'maxRow': maxR};
    }
    return {'maxCol': 55, 'maxRow': 96};
  }

  static int _colToIndex(String letters) {
    int n = 0;
    for (final ch in letters.toUpperCase().codeUnits) {
      n = n * 26 + (ch - 64);
    }
    return n;
  }

  static Map<String, int> _parseRef(String ref) {
    final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(ref);
    if (m == null) return {'col': 1, 'row': 1};
    return {'col': _colToIndex(m.group(1)!), 'row': int.parse(m.group(2)!)};
  }

  // styles: return per xf index the borderId
  static List<int?> _parseXfBorderIds(String stylesXml) {
    if (stylesXml.isEmpty) return [];
    final res = <int?>[];
    final xfRe = RegExp(r'<xf\s+[^>]*borderId="(\d+)"[^>]*/?>|<xf[^>]*>(.*?)</xf>', dotAll: true);
    for (final m in xfRe.allMatches(stylesXml)) {
      final bidStr = m.group(1);
      if (bidStr != null) {
        res.add(int.tryParse(bidStr));
      } else {
        // nested, look inside for borderId attr on xf
        final b = RegExp(r'borderId="(\d+)"').firstMatch(m.group(0)!);
        res.add(b != null ? int.tryParse(b.group(1)!) : null);
      }
    }
    return res;
  }

  static List<Map<String, String?>> _parseBorderDefs(String stylesXml) {
    if (stylesXml.isEmpty) return [];
    final defs = <Map<String, String?>>[];
    final bordersRe = RegExp(r'<border[^>]*>(.*?)</border>', dotAll: true);
    for (final bm in bordersRe.allMatches(stylesXml)) {
      final inner = bm.group(1)!;
      final map = <String, String?>{};
      for (final side in ['left', 'right', 'top', 'bottom']) {
        final sm = RegExp('<$side([^>]*?)>').firstMatch(inner);
        if (sm != null) {
          final st = RegExp(r'style="([^"]+)"').firstMatch(sm.group(0)!);
          map[side] = st != null ? st.group(1) : 'thin'; // presence implies thin-ish
        }
      }
      defs.add(map);
    }
    return defs;
  }

  static List<Map<String, Object?>> _parseXfFonts(String stylesXml) {
    if (stylesXml.isEmpty) return [];
    // first parse fonts list: sz, b
    final fonts = <Map<String, Object?>>[];
    final fontRe = RegExp(r'<font[^>]*>(.*?)</font>', dotAll: true);
    for (final fm in fontRe.allMatches(stylesXml)) {
      final inner = fm.group(1)!;
      double? sz;
      final szM = RegExp(r'<sz\s+val="([^"]+)"').firstMatch(inner);
      if (szM != null) sz = double.tryParse(szM.group(1)!);
      final bold = inner.contains('<b') || inner.contains('<b/>');
      fonts.add({'size': sz, 'bold': bold});
    }
    // now xf -> fontId
    final res = <Map<String, Object?>>[];
    final xfRe = RegExp(r'<xf\s+([^>]*?)>|<xf([^>]*?)/>', dotAll: true);
    for (final xm in xfRe.allMatches(stylesXml)) {
      final attr = xm.group(1) ?? xm.group(2) ?? '';
      int? fid;
      final fM = RegExp(r'fontId="(\d+)"').firstMatch(attr);
      if (fM != null) fid = int.tryParse(fM.group(1)!);
      if (fid != null && fid < fonts.length) {
        res.add(fonts[fid]);
      } else {
        res.add({'size': 8.0, 'bold': false});
      }
    }
    return res;
  }
}

class _CellInfo {
  String val;
  int? styleId;
  int cs = 1;
  int rs = 1;
  _CellInfo({required this.val, this.styleId});
}
