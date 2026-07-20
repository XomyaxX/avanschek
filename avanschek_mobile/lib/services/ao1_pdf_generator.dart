import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/check.dart';
import '../models/report_data.dart';

// DEPRECATED: Previously used for manual reconstruction of AO-1 form in PDF.
// Now PDF is generated via local xlsx -> HTML grid replica (with exact cells/merges/borders) + flutter_html_to_pdf_plus.
// This file kept only for reference / possible fallback. Not called from ReportGenerator anymore.

class Ao1PdfGenerator {
  static pw.Font? _font;

  static Future<void> generate({
    required ReportData data,
    required List<Check> checks,
    required String path,
    required pw.Font font,
  }) async {
    _font = font;
    final pdf = pw.Document();
    final total = checks.fold<double>(0, (sum, c) => sum + c.amount);
    final balance = data.advanceReceived - total;
    final theme = pw.ThemeData.withFont(base: font, bold: font);

    // ─── Лицевая сторона ───
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        theme: theme,
        build: (context) => _facePage(data, total, balance),
      ),
    );

    // ─── Оборотная сторона ───
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        theme: theme,
        build: (context) => _backPage(checks, total),
      ),
    );

    await File(path).writeAsBytes(await pdf.save());
  }

  // ═══════════════════════════════════════════════════════
  //  ЛИЦЕВАЯ СТОРОНА
  // ═══════════════════════════════════════════════════════
  static pw.Widget _facePage(ReportData data, double total, double balance) {
    return pw.Stack(
      children: [
        // ── Заголовок (правый верхний угол) ──
        _txt('Унифицированная форма № АО-1', x: 320, y: 16, size: 8, align: pw.TextAlign.right),
        _txt('Утверждена Постановлением Госкомстата России', x: 320, y: 26, size: 8, align: pw.TextAlign.right),
        _txt('от 01.08.2001 № 55', x: 320, y: 36, size: 8, align: pw.TextAlign.right),

        // ── Блок организации (верхний левый) ──
        _box(x: 28, y: 52, w: 260, h: 40),
        _txt(data.organization, x: 32, y: 56, size: 10, bold: true),
        _txt('(наименование организации)', x: 32, y: 80, size: 7, italic: true),

        _txt('Код', x: 300, y: 52, size: 8),
        _box(x: 320, y: 52, w: 60, h: 14),
        _txt('Форма по ОКУД', x: 300, y: 70, size: 8),
        _box(x: 380, y: 70, w: 50, h: 14),
        _txt('0302001', x: 382, y: 72, size: 9),
        _txt('по ОКПО', x: 300, y: 88, size: 8),
        _box(x: 340, y: 88, w: 90, h: 14),

        // ── УТВЕРЖДАЮ ──
        _txt('УТВЕРЖДАЮ', x: 320, y: 110, size: 10, bold: true),
        _txt('Отчет в сумме', x: 320, y: 124, size: 9),
        _box(x: 400, y: 122, w: 120, h: 14),
        _txt(total.toStringAsFixed(2), x: 402, y: 124, size: 9, bold: true),
        _txt('руб.', x: 400, y: 140, size: 8),
        _txt('коп.', x: 460, y: 140, size: 8),

        _txt('Руководитель', x: 320, y: 156, size: 8),
        _box(x: 400, y: 154, w: 120, h: 14),
        _txt('(должность)', x: 400, y: 170, size: 7, italic: true),
        _txt('(подпись)', x: 320, y: 186, size: 7, italic: true),
        _txt('(расшифровка подписи)', x: 420, y: 186, size: 7, italic: true),

        _txt('«', x: 380, y: 202, size: 10),
        _box(x: 390, y: 200, w: 24, h: 14),
        _txt(data.reportDate.split('.')[0], x: 392, y: 202, size: 9),
        _txt('»', x: 418, y: 202, size: 10),
        _box(x: 426, y: 200, w: 60, h: 14),
        _txt(data.reportDate.split('.')[1], x: 428, y: 202, size: 9),
        _box(x: 490, y: 200, w: 24, h: 14),
        _txt('20', x: 492, y: 202, size: 9),
        _box(x: 516, y: 200, w: 24, h: 14),
        _txt(data.reportDate.split('.')[2].substring(2), x: 518, y: 202, size: 9),
        _txt('г.', x: 544, y: 202, size: 9),

        // ── Номер / Дата / АВАНСОВЫЙ ОТЧЕТ ──
        _txt('Номер', x: 140, y: 154, size: 8),
        _box(x: 140, y: 166, w: 60, h: 14),
        _txt(data.reportNumber, x: 142, y: 168, size: 9),
        _txt('Дата', x: 210, y: 154, size: 8),
        _box(x: 210, y: 166, w: 60, h: 14),
        _txt(data.reportDate, x: 212, y: 168, size: 9),

        _txt('АВАНСОВЫЙ ОТЧЁТ', x: 80, y: 190, size: 14, bold: true),
        _txt('№ ${data.reportNumber.isNotEmpty ? data.reportNumber : 'б/н'} от ${data.reportDate}', x: 80, y: 210, size: 10),

        // ── Персональные данные ──
        _box(x: 28, y: 232, w: 535, h: 80),
        // Структурное подразделение
        _txt('Структурное подразделение', x: 32, y: 236, size: 8),
        _txt(data.department, x: 180, y: 236, size: 10, bold: true),
        _hLine(28, 252, 535),
        // Подотчетное лицо
        _txt('Подотчетное лицо', x: 32, y: 256, size: 8),
        _txt(data.fio, x: 140, y: 256, size: 10, bold: true),
        _txt('Табельный номер', x: 340, y: 256, size: 8),
        _txt(data.tabNumber, x: 430, y: 256, size: 10),
        _txt('(фамилия, инициалы)', x: 140, y: 272, size: 7, italic: true),
        _hLine(28, 280, 535),
        // Должность / Назначение
        _txt('Профессия (должность)', x: 32, y: 284, size: 8),
        _txt(data.position, x: 160, y: 284, size: 10, bold: true),
        _txt('Назначение аванса', x: 300, y: 284, size: 8),
        _txt(data.purpose, x: 400, y: 284, size: 10, bold: true),

        // ── Таблица сумм ──
        _box(x: 28, y: 320, w: 535, h: 250),
        _hLine(28, 340, 535),
        _hLine(28, 360, 535),
        _hLine(28, 380, 535),
        _hLine(28, 400, 535),
        _hLine(28, 420, 535),
        _hLine(28, 440, 535),
        _hLine(28, 460, 535),
        _hLine(28, 480, 535),
        _hLine(28, 500, 535),
        _hLine(28, 520, 535),
        _hLine(28, 540, 535),

        // Вертикальные линии таблицы сумм
        _vLine(28, 320, 250),
        _vLine(260, 320, 250),   // конец "Наименование показателя"
        _vLine(340, 320, 250),   // конец "Сумма, руб.коп."
        _vLine(410, 320, 250),   // конец дебет
        _vLine(480, 320, 250),   // конец кредит
        _vLine(563, 320, 250),   // правая граница

        _txt('Наименование показателя', x: 32, y: 324, size: 8, bold: true),
        _txt('Сумма, руб.коп.', x: 270, y: 324, size: 8, bold: true),
        _txt('Бухгалтерская запись', x: 360, y: 324, size: 8, bold: true),
        _txt('дебет', x: 350, y: 340, size: 8),
        _txt('кредит', x: 420, y: 340, size: 8),

        _txt(' Предыдущий аванс', x: 32, y: 356, size: 9),
        _txt('  остаток', x: 32, y: 372, size: 9),
        _txt('  перерасход', x: 32, y: 388, size: 9),
        _txt(' Получен аванс 1. из кассы', x: 32, y: 404, size: 9),
        _txt(data.advanceReceived.toStringAsFixed(2), x: 270, y: 404, size: 9, align: pw.TextAlign.right),
        _txt(' 1а. в валюте (справочно)', x: 32, y: 420, size: 9),
        _txt(' 2.', x: 32, y: 436, size: 9),
        _txt(' Итого получено', x: 32, y: 452, size: 9, bold: true),
        _txt(data.advanceReceived.toStringAsFixed(2), x: 270, y: 452, size: 9, align: pw.TextAlign.right, bold: true),
        _txt(' Израсходовано', x: 32, y: 468, size: 9, bold: true),
        _txt(total.toStringAsFixed(2), x: 270, y: 468, size: 9, align: pw.TextAlign.right, bold: true),
        _txt('Остаток', x: 32, y: 484, size: 9),
        _txt(balance >= 0 ? balance.toStringAsFixed(2) : '', x: 270, y: 484, size: 9, align: pw.TextAlign.right),
        _txt('Перерасход', x: 32, y: 500, size: 9),
        _txt(balance < 0 ? (-balance).toStringAsFixed(2) : '', x: 270, y: 500, size: 9, align: pw.TextAlign.right),

        // ── Приложение ──
        _txt('Приложение', x: 32, y: 520, size: 9),
        _box(x: 100, y: 518, w: 40, h: 14),
        _txt('-', x: 118, y: 520, size: 9),
        _txt('документов на', x: 148, y: 520, size: 9),
        _box(x: 230, y: 518, w: 40, h: 14),
        _txt('-', x: 248, y: 520, size: 9),
        _txt('листах', x: 278, y: 520, size: 9),

        // ── Отчет проверен ──
        _txt('Отчет проверен. К утверждению в сумме', x: 32, y: 544, size: 9),
        _box(x: 240, y: 542, w: 80, h: 14),
        _txt(total.toStringAsFixed(2), x: 242, y: 544, size: 9),
        _txt('руб.', x: 326, y: 544, size: 8),
        _txt('коп.', x: 380, y: 544, size: 8),
        _txt('(', x: 420, y: 544, size: 9),
        _box(x: 430, y: 542, w: 80, h: 14),
        _txt('руб.', x: 430, y: 558, size: 7, italic: true),
        _txt('коп.)', x: 510, y: 558, size: 7, italic: true),

        // ── Сумма прописью ──
        _box(x: 100, y: 562, w: 460, h: 14),
        _txt(_sumToWords(total), x: 102, y: 564, size: 9, bold: true),
        _txt('(сумма прописью)', x: 102, y: 578, size: 7, italic: true),

        // ── Подписи ──
        _txt('Главный бухгалтер', x: 32, y: 594, size: 9),
        _txt('(подпись)', x: 140, y: 610, size: 7, italic: true),
        _txt('(расшифровка подписи)', x: 280, y: 610, size: 7, italic: true),
        _hLine(130, 606, 100),
        _hLine(280, 606, 200),

        _txt('Бухгалтер', x: 32, y: 626, size: 9),
        _txt('(подпись)', x: 140, y: 642, size: 7, italic: true),
        _txt('(расшифровка подписи)', x: 280, y: 642, size: 7, italic: true),
        _hLine(130, 638, 100),
        _hLine(280, 638, 200),

        // ── Остаток / Перерасход выдан ──
        if (balance >= 0) ...[
          _txt('Остаток внесен', x: 32, y: 662, size: 9),
          _txt('в сумме', x: 120, y: 662, size: 9),
          _box(x: 180, y: 660, w: 80, h: 14),
          _txt(balance.toStringAsFixed(2), x: 182, y: 662, size: 9),
          _txt('руб.', x: 266, y: 662, size: 8),
          _txt('коп. по кассовому ордеру №', x: 300, y: 662, size: 8),
          _box(x: 450, y: 660, w: 60, h: 14),
        ] else ...[
          _txt('Перерасход выдан', x: 32, y: 662, size: 9),
          _txt('в сумме', x: 150, y: 662, size: 9),
          _box(x: 210, y: 660, w: 80, h: 14),
          _txt((-balance).toStringAsFixed(2), x: 212, y: 662, size: 9),
        ],

        _txt('Бухгалтер (кассир)', x: 80, y: 690, size: 9),
        _txt('(подпись)', x: 140, y: 706, size: 7, italic: true),
        _txt('(расшифровка подписи)', x: 280, y: 706, size: 7, italic: true),
        _hLine(130, 702, 100),
        _hLine(280, 702, 200),

        // ── Линия отреза ──
        _hLine(28, 726, 535, width: 1.5),
        _txt('л и н и я   о т р е з а', x: 200, y: 730, size: 8),

        // ── Расписка ──
        _txt('Расписка. Принят к проверке от', x: 32, y: 750, size: 9),
        _txt('авансовый отчет №', x: 220, y: 750, size: 9),
        _box(x: 330, y: 748, w: 60, h: 14),
        _txt(data.reportNumber, x: 332, y: 750, size: 9),
        _txt('от «', x: 400, y: 750, size: 9),
        _box(x: 426, y: 748, w: 24, h: 14),
        _txt(data.reportDate.split('.')[0], x: 428, y: 750, size: 9),
        _txt('»', x: 454, y: 750, size: 9),
        _box(x: 462, y: 748, w: 60, h: 14),
        _txt(data.reportDate.split('.')[1], x: 464, y: 750, size: 9),
        _box(x: 526, y: 748, w: 24, h: 14),
        _txt('20', x: 528, y: 750, size: 9),
        _box(x: 550, y: 748, w: 24, h: 14),
        _txt(data.reportDate.split('.')[2].substring(2), x: 552, y: 750, size: 9),
        _txt('г.', x: 578, y: 750, size: 9),

        _txt('На сумму', x: 32, y: 770, size: 9),
        _box(x: 90, y: 768, w: 80, h: 14),
        _txt(total.toStringAsFixed(2), x: 92, y: 770, size: 9),
        _txt('руб.', x: 176, y: 770, size: 8),
        _txt('коп., количество документов', x: 210, y: 770, size: 8),
        _box(x: 380, y: 768, w: 40, h: 14),
        _txt('-', x: 398, y: 770, size: 9),
        _txt('на', x: 428, y: 770, size: 8),
        _box(x: 450, y: 768, w: 40, h: 14),
        _txt('-', x: 468, y: 770, size: 9),
        _txt('листах', x: 496, y: 770, size: 8),

        _txt('(прописью)', x: 90, y: 784, size: 7, italic: true),

        _txt('Бухгалтер', x: 80, y: 800, size: 9),
        _txt('(подпись)', x: 140, y: 816, size: 7, italic: true),
        _txt('(расшифровка подписи)', x: 280, y: 816, size: 7, italic: true),
        _hLine(130, 812, 100),
        _hLine(280, 812, 200),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //  ОБОРОТНАЯ СТОРОНА
  // ═══════════════════════════════════════════════════════
  static pw.Widget _backPage(List<Check> checks, double total) {
    final rows = <pw.TableRow>[
      // Заголовок таблицы
      pw.TableRow(
        children: [
          _cell('№ п/п', size: 8, bold: true, align: pw.TextAlign.center),
          _cell('Документ, подтверждающий производственные расходы', size: 8, bold: true, align: pw.TextAlign.center),
          _cell('Номенклатура', size: 8, bold: true, align: pw.TextAlign.center),
          _cell('Сумма расхода', size: 8, bold: true, align: pw.TextAlign.center),
          _cell('Дебет счета, субсчета', size: 8, bold: true, align: pw.TextAlign.center),
        ],
      ),
      // Подзаголовки
      pw.TableRow(
        children: [
          _cell('', size: 7),
          _cell('дата\nномер', size: 7, align: pw.TextAlign.center),
          _cell('', size: 7),
          _cell('по отчету\nпринята к учету', size: 7, align: pw.TextAlign.center),
          _cell('', size: 7),
        ],
      ),
    ];

    for (var i = 0; i < 30; i++) {
      if (i < checks.length) {
        final c = checks[i];
        rows.add(
          pw.TableRow(
            children: [
              _cell('${i + 1}', size: 9, align: pw.TextAlign.center),
              _cell('${c.docDate}\n№${c.docNumber}', size: 9, align: pw.TextAlign.center),
              _cell(c.name, size: 9),
              _cell('${c.amount.toStringAsFixed(2)}\n${c.amount.toStringAsFixed(2)}', size: 9, align: pw.TextAlign.right),
              _cell('Студия', size: 9, align: pw.TextAlign.center),
            ],
          ),
        );
      } else {
        rows.add(
          pw.TableRow(
            children: [
              _cell('${i + 1}', size: 9, align: pw.TextAlign.center),
              _cell('', size: 9),
              _cell('', size: 9),
              _cell('', size: 9),
              _cell('', size: 9),
            ],
          ),
        );
      }
    }

    // Итоговая строка
    rows.add(
      pw.TableRow(
        children: [
          _cell('', size: 9),
          _cell('', size: 9),
          _cell('Итого', size: 9, bold: true),
          _cell(total.toStringAsFixed(2), size: 9, bold: true, align: pw.TextAlign.right),
          _cell('', size: 9),
        ],
      ),
    );

    return pw.Padding(
      padding: const pw.EdgeInsets.all(28),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Center(
            child: pw.Text(
              'Оборотная сторона формы № АО-1',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: _font),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FixedColumnWidth(120),
              2: const pw.FlexColumnWidth(),
              3: const pw.FixedColumnWidth(100),
              4: const pw.FixedColumnWidth(100),
            },
            children: rows,
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Container()),
              pw.Text(
                'Подотчетное лицо _______________',
                style: pw.TextStyle(fontSize: 9, font: _font),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Container()),
              pw.Text(
                '(подпись)',
                style: pw.TextStyle(fontSize: 7, font: _font, fontStyle: pw.FontStyle.italic),
              ),
              pw.SizedBox(width: 60),
              pw.Text(
                '(расшифровка подписи)',
                style: pw.TextStyle(fontSize: 7, font: _font, fontStyle: pw.FontStyle.italic),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HELPERS
  // ═══════════════════════════════════════════════════════
  static pw.Widget _txt(
    String text, {
    required double x,
    required double y,
    double size = 9,
    bool bold = false,
    bool italic = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Positioned(
      left: x,
      top: y,
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: _font,
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    );
  }

  static pw.Widget _box({
    required double x,
    required double y,
    required double w,
    required double h,
  }) {
    return pw.Positioned(
      left: x,
      top: y,
      child: pw.Container(
        width: w,
        height: h,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.5),
        ),
      ),
    );
  }

  static pw.Widget _hLine(double x, double y, double w, {double width = 0.5}) {
    return pw.Positioned(
      left: x,
      top: y,
      child: pw.Container(width: w, height: width, color: PdfColors.black),
    );
  }

  static pw.Widget _vLine(double x, double y, double h, {double width = 0.5}) {
    return pw.Positioned(
      left: x,
      top: y,
      child: pw.Container(width: width, height: h, color: PdfColors.black),
    );
  }

  static pw.Widget _cell(
    String text, {
    double size = 9,
    bool bold = false,
    bool italic = false,
    pw.TextAlign align = pw.TextAlign.left,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(2),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: _font,
          fontSize: size,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
        ),
      ),
    );
  }

  static String _sumToWords(double amount) {
    final rub = amount.truncate();
    final kop = ((amount - rub).abs() * 100).round();
    return '${rub.toStringAsFixed(0)} руб. ${kop.toString().padLeft(2, '0')} коп.';
  }
}
