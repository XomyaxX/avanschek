import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:open_filex/open_filex.dart';
import '../models/check.dart';
import '../models/report_data.dart';
import '../services/db_service.dart';
import '../services/prefs_service.dart';
import '../services/report_generator.dart';
import '../services/api_service.dart';
import 'qr_scan_screen.dart';
import 'settings_screen.dart';
import 'history_screen.dart';
import 'onboarding_screen.dart';
import 'profile_setup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scannerController = MobileScannerController();
  final _formKey = GlobalKey<FormState>();

  final _data = ReportData();
  final List<Check> _checks = [];

  bool _loading = false;
  String? _xlsUrl;
  String? _pdfUrl;
  Timer? _draftTimer;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _data.reportDate =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    _loadSavedProfile();
    _checkFirstLaunch();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _scannerController.dispose();
    super.dispose();
  }

  void _scheduleDraftSave() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(seconds: 2), () async {
      try {
        await DbService.saveDraft(_data, _checks);
      } catch (e) {
        debugPrint('Ошибка сохранения черновика: $e');
      }
    });
  }

  Future<void> _loadSavedProfile() async {
    final fio = await PrefsService.getFio();
    final position = await PrefsService.getPosition();
    final token = await PrefsService.getToken();
    final organization = await PrefsService.getOrganization();
    final department = await PrefsService.getDepartment();
    final purpose = await PrefsService.getPurpose();
    setState(() {
      _data.fio = fio;
      _data.position = position;
      _data.fnsToken = token;
      if (organization.isNotEmpty) _data.organization = organization;
      if (department.isNotEmpty) _data.department = department;
      if (purpose.isNotEmpty) _data.purpose = purpose;
    });
  }

  void _checkFirstLaunch() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final fio = await PrefsService.getFio();
      if (fio.isEmpty && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const ProfileSetupScreen(),
            fullscreenDialog: true,
          ),
        );
        await _loadSavedProfile();
        await _checkDraft();
        return;
      }
      final hasSeenOnboarding = await PrefsService.getHasSeenOnboarding();
      if (!hasSeenOnboarding && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const OnboardingScreen(),
            fullscreenDialog: true,
          ),
        );
      }
      await _checkDraft();
    });
  }

  Future<void> _checkDraft() async {
    final Map<String, dynamic>? draft;
    try {
      draft = await DbService.getDraft();
    } catch (e) {
      debugPrint('Ошибка чтения черновика: $e');
      return;
    }
    if (draft == null || !mounted) return;

    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Восстановить черновик?'),
        content: const Text(
            'Найден несохранённый отчёт. Хотите восстановить его или начать новый?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Начать новый'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade800,
              foregroundColor: Colors.white,
            ),
            child: const Text('Восстановить'),
          ),
        ],
      ),
    );

    if (restore == true) {
      _restoreDraft(draft);
    } else {
      try {
        await DbService.clearDraft();
      } catch (e) {
        debugPrint('Ошибка очистки черновика: $e');
      }
      setState(() {
        _checks.clear();
        _addCheck();
      });
    }
  }

  void _restoreDraft(Map<String, dynamic> draft) {
    try {
      final reportJson = draft['report_json'] as String?;
      final checksJson = draft['checks_json'] as String?;
      if (reportJson == null || checksJson == null) return;

      final reportMap = Map<String, dynamic>.from(
          (jsonDecode(reportJson) as Map).cast<String, dynamic>());
      final checksList = (jsonDecode(checksJson) as List)
          .map((e) => Map<String, dynamic>.from((e as Map).cast<String, dynamic>()))
          .toList();

      setState(() {
        _data.organization = reportMap['organization'] ?? 'ИП Ермилов МВ';
        _data.department = reportMap['department'] ?? 'Офис';
        _data.fio = reportMap['fio'] ?? '';
        _data.position = reportMap['position'] ?? '';
        _data.tabNumber = reportMap['tab_number'] ?? '';
        _data.purpose = reportMap['purpose'] ?? 'Хоз расходы';
        _data.reportNumber = reportMap['report_number'] ?? '';
        _data.reportDate = reportMap['report_date'] ?? '';
        _data.advanceReceived = (reportMap['advance_received'] as num?)?.toDouble() ?? 0.0;

        _checks.clear();
        for (final c in checksList) {
          _checks.add(Check(
            docDate: c['doc_date'] ?? '',
            docNumber: c['doc_number'] ?? '',
            name: c['name'] ?? '',
            amount: (c['amount'] as num?)?.toDouble() ?? 0.0,
          ));
        }
        if (_checks.isEmpty) _addCheck();
      });
    } catch (e) {
      debugPrint('Ошибка восстановления черновика: $e');
    }
  }

  void _addCheck() {
    setState(() {
      _checks.add(Check());
    });
    _scheduleDraftSave();
  }

  void _removeCheck(int index) {
    setState(() {
      _checks.removeAt(index);
      if (_checks.isEmpty) _addCheck();
    });
    _scheduleDraftSave();
  }

  Future<void> _scanQr(int index) async {
    if (Platform.isWindows || Platform.isLinux) {
      _showSnack('📷 Сканирование QR недоступно на десктопе');
      return;
    }
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (result != null) {
      _applyQrData(index, result);
    }
  }

  Future<void> _pickQrImage(int index) async {
    PermissionStatus status;
    if (Platform.isAndroid) {
      status = await Permission.photos.request();
      if (status.isDenied) {
        status = await Permission.storage.request();
      }
    } else {
      status = await Permission.photos.request();
    }

    if (status.isDenied || status.isPermanentlyDenied) {
      _showSnack('❌ Нужно разрешение на доступ к галерее');
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    _setCheckLoading(index, true);
    try {
      final barcode = await _scannerController.analyzeImage(picked.path);
      if (barcode != null && barcode.barcodes.isNotEmpty) {
        final raw = barcode.barcodes.first.rawValue;
        if (raw != null) {
          _applyQrData(index, raw);
          _showSnack('✅ QR распознан с фото. Введите наименование вручную.');
        } else {
          _showSnack('❌ Не удалось прочитать данные QR-кода');
        }
      } else {
        _showSnack('❌ QR-код не найден на фото');
      }
    } catch (e) {
      _showSnack('❌ Ошибка распознавания: $e');
    } finally {
      _setCheckLoading(index, false);
    }
  }

  void _applyQrData(int index, String raw) {
    final uri = Uri.tryParse('https://x/?$raw') ?? Uri.parse('https://x/');
    final params = uri.queryParameters;
    final t = params['t'];
    final s = params['s'];
    if (t != null && t.length >= 8) {
      _checks[index].docDate =
          '${t.substring(6, 8)}/${t.substring(4, 6)}';
    }
    if (s != null) {
      _checks[index].amount = double.tryParse(s) ?? 0.0;
    }
    final i = params['i'];
    if (i != null) {
      _checks[index].docNumber = 'ФД $i';
    }
    _checks[index].revision++;
    setState(() {});
    _scheduleDraftSave();
    _showSnack('✅ QR распознан. Введите наименование вручную.');
  }

  void _setCheckLoading(int index, bool loading) {
    setState(() {});
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _generate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_checks.isEmpty) {
      _showSnack('Добавьте хотя бы один чек');
      return;
    }

    setState(() {
      _loading = true;
      _xlsUrl = null;
      _pdfUrl = null;
    });

    try {
      final files = await ReportGenerator.generate(
        data: _data,
        checks: _checks,
      );
      final totalAmount = _checks.fold<double>(0, (sum, c) => sum + c.amount);

      await DbService.saveReport(
        data: _data,
        checks: _checks,
        totalAmount: totalAmount,
        xlsPath: files['xls'],
        pdfPath: files['pdf'],
      );
      await DbService.clearDraft();

      setState(() {
        _xlsUrl = files['xls'];
        _pdfUrl = files['pdf'];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Документы сгенерированы и сохранены!'),
            action: SnackBarAction(
              label: 'История',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      _showSnack('❌ Ошибка генерации: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _download(String? filePath, String fileName) async {
    if (filePath == null || filePath.isEmpty) return;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        _showSnack('❌ Файл не найден');
        return;
      }
      await Share.shareXFiles([XFile(file.path)], text: fileName);
    } catch (e) {
      _showSnack('❌ Ошибка отправки: $e');
    }
  }

  Future<void> _pickDate() async {
    final parts = _data.reportDate.split('.');
    final initialDate = parts.length == 3
        ? DateTime(
            int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]))
        : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (picked != null) {
      setState(() {
        _data.reportDate =
            '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
      });
      _scheduleDraftSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Авансовый отчёт'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case 'settings':
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  await _loadSavedProfile();
                  break;
                case 'history':
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HistoryScreen()),
                  );
                  break;
                case 'instruction':
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnboardingScreen()),
                  );
                  break;
                case 'update':
                  await _performAppUpdate();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, size: 20),
                    SizedBox(width: 12),
                    Text('Настройки'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'history',
                child: Row(
                  children: [
                    Icon(Icons.history, size: 20),
                    SizedBox(width: 12),
                    Text('История отчётов'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'instruction',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 20),
                    SizedBox(width: 12),
                    Text('Инструкция'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'update',
                child: Row(
                  children: [
                    Icon(Icons.system_update, size: 20),
                    SizedBox(width: 12),
                    Text('Обновить приложение'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Шапка профиля
                  _buildProfileHeader(),
                  const SizedBox(height: 16),

                  // Секция отчёта
                  _buildCard(
                    title: '📋 Отчёт',
                    children: [
                      InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Дата отчёта',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(_data.reportDate),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildNumberField(
                        'Получено аванса, ₽',
                        _data.advanceReceived,
                        (v) {
                          setState(() => _data.advanceReceived = v);
                          _scheduleDraftSave();
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildSummaryBar(),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Реквизиты (сворачиваемые)
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ExpansionTile(
                      title: const Text(
                        '🏢 Реквизиты',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      childrenPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      children: [
                        _buildTextField(
                          'Организация',
                          _data.organization,
                          (v) => _data.organization = v,
                        ),
                        _buildTextField(
                          'Подразделение',
                          _data.department,
                          (v) => _data.department = v,
                        ),
                        _buildTextField(
                          'Назначение аванса',
                          _data.purpose,
                          (v) => _data.purpose = v,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Чеки
                  _buildCard(
                    title: '🧾 Чеки (${_checks.length})',
                    children: [
                      for (var i = 0; i < _checks.length; i++)
                        _buildCompactCheckCard(i),
                    ],
                  ),
                  const SizedBox(height: 100),
                ],
              ),
            ),

            // Закреплённая панель генерации + FAB
            if (_xlsUrl != null || _pdfUrl != null)
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_xlsUrl != null)
                        ListTile(
                          leading:
                              const Icon(Icons.table_chart, color: Colors.green),
                          title: const Text('Скачать Excel'),
                          trailing: const Icon(Icons.download),
                          onTap: () => _download(_xlsUrl, 'avanschek.xls'),
                        ),
                      if (_pdfUrl != null)
                        ListTile(
                          leading:
                              const Icon(Icons.picture_as_pdf, color: Colors.red),
                          title: const Text('Скачать PDF'),
                          trailing: const Icon(Icons.download),
                          onTap: () => _download(_pdfUrl, 'avanschek.pdf'),
                        ),
                    ],
                  ),
                ),
              ),

            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Сгенерировать документы'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCheck,
        icon: const Icon(Icons.add),
        label: const Text('Чек'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade800, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _data.fio.isNotEmpty ? _data.fio : 'Не указано ФИО',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _data.position.isNotEmpty
                      ? _data.position
                      : 'Не указана должность',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required String title, required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    String initial,
    ValueChanged<String> onChanged, {
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initial,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        validator: required
            ? (v) => v == null || v.isEmpty ? 'Обязательное поле' : null
            : null,
        onChanged: (v) {
          onChanged(v);
          _scheduleDraftSave();
        },
      ),
    );
  }

  Widget _buildNumberField(
    String label,
    double initial,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        initialValue: initial.toString(),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        onChanged: (v) {
          onChanged(double.tryParse(v) ?? 0.0);
          setState(() {});
          _scheduleDraftSave();
        },
      ),
    );
  }

  Widget _buildSummaryBar() {
    final total = _checks.fold<double>(0, (s, c) => s + c.amount);
    final balance = _data.advanceReceived - total;
    final isOver = balance < 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isOver ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOver ? Colors.red.shade200 : Colors.green.shade200,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('По чекам: ${total.toStringAsFixed(2)} ₽',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                Text(
                  isOver
                      ? 'Перерасход: ${(-balance).toStringAsFixed(2)} ₽'
                      : 'Остаток: ${balance.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isOver ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
          Text('${_checks.length} док.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildCompactCheckCard(int index) {
    final check = _checks[index];
    return Container(
      key: ValueKey('check_card_${index}_${check.revision}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${check.amount.toStringAsFixed(2)} ₽',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _removeCheck(index),
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Удалить',
              ),
            ],
          ),
          if (check.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                check.name,
                style: const TextStyle(fontSize: 15),
              ),
            ),
          if (check.docDate.isNotEmpty || check.docNumber.isNotEmpty)
            Text(
              '${check.docDate}  •  ${check.docNumber}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 12),
          // Поля редактирования (компактные)
          _buildTextField(
            'Наименование',
            check.name,
            (v) => check.name = v,
            required: true,
          ),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _buildTextField(
                  'Дата (ДД/ММ)',
                  check.docDate,
                  (v) => check.docDate = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _buildTextField(
                  'Номер документа',
                  check.docNumber,
                  (v) => check.docNumber = v,
                ),
              ),
            ],
          ),
          _buildNumberField(
            'Сумма, ₽',
            check.amount,
            (v) => check.amount = v,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _scanQr(index),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Сканер'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _pickQrImage(index),
                  icon: const Icon(Icons.photo_library, size: 18),
                  label: const Text('Фото'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // === Реализация обновления приложения (кнопка в меню) ===
  Future<void> _performAppUpdate() async {
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Обновления поддерживаются только на Android')),
      );
      return;
    }

    final api = ApiService();

    // Захватываем navigator и messenger как можно раньше (до await и showDialog)
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    // Показываем индикатор
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final current = await PackageInfo.fromPlatform();
      final update = await api.checkForUpdate();

      navigator.pop(); // убрать индикатор

      if (update == null ||
          (update.version == current.version && update.buildNumber == current.buildNumber)) {
        final msg = update == null
            ? 'Не удалось проверить обновления (сервер по API_BASE_URL в assets/.env недоступен или не возвращает данные). Текущая версия: ${current.version} (${current.buildNumber})'
            : '✅ У вас уже последняя версия (${current.version}+${current.buildNumber})';
        messenger.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
        return;
      }

      if (!mounted) return;

      // Диалог подтверждения
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Текущая: ${current.version} (${current.buildNumber})'),
              Text('Новая: ${update.version} (${update.buildNumber})'),
              if (update.changelog != null && update.changelog!.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Что нового:', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(update.changelog!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade800),
              child: const Text('Скачать и установить'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      if (!mounted) return;

      // Прогресс диалог с живым обновлением (bar + текст)
      final progressNotifier = ValueNotifier<double>(0.0);
      final statusNotifier = ValueNotifier<String>('Подготовка...');

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Обновление приложения'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (context, prog, child) => LinearProgressIndicator(value: prog),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: statusNotifier,
                  builder: (context, status, child) => Text(status),
                ),
              ],
            ),
          );
        },
      );

      File? apkFile;
      try {
        apkFile = await api.downloadApkWithProgress(
          update.apkUrl,
          'avanschek_update.apk',
          (p) {
            progressNotifier.value = p.clamp(0.0, 1.0);
            statusNotifier.value = p < 1.0
                ? 'Скачивание... ${(p * 100).toInt()}%'
                : 'Скачивание завершено. Подготовка к установке...';
          },
        );

        // Закрыть прогресс (используем захваченный navigator)
        navigator.pop();

        // Разрешение на установку (используем захваченные navigator/messenger)
        var installStatus = await Permission.requestInstallPackages.status;
        if (installStatus.isDenied || installStatus.isRestricted) {
          installStatus = await Permission.requestInstallPackages.request();
        }

        if (installStatus.isGranted) {
          // Используем open_filex — он лучше справляется с открытием .apk и запуском установщика на Android
          final result = await OpenFilex.open(apkFile.path);
          if (result.type == ResultType.done) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Открыт установщик APK. Следуйте инструкциям на экране.')),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(content: Text('Не удалось открыть APK для установки: ${result.message} (${result.type})')),
            );
          }
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('Нужно разрешение на установку приложений из неизвестных источников')),
          );
          await openAppSettings();
        }
      } catch (e) {
        navigator.pop(); // закрыть прогресс если открыт
        messenger.showSnackBar(
          SnackBar(content: Text('Ошибка при скачивании/установке: $e')),
        );
      }
    } catch (e) {
      try { navigator.pop(); } catch (_) {}
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка проверки обновлений: $e')),
      );
    }
  }
}
