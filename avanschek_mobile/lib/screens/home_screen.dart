import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import '../models/check.dart';
import '../models/report_data.dart';
import '../services/api_service.dart';
import '../services/prefs_service.dart';
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
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();

  final _data = ReportData();
  final List<Check> _checks = [];

  bool _loading = false;
  String? _xlsUrl;
  String? _pdfUrl;
  bool _requisitesExpanded = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _data.reportDate =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    _loadSavedProfile();
    _addCheck();
    _checkFirstLaunch();
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
    });
  }

  void _addCheck() {
    setState(() {
      _checks.add(Check());
    });
  }

  void _removeCheck(int index) {
    setState(() {
      _checks.removeAt(index);
      if (_checks.isEmpty) _addCheck();
    });
  }

  Future<void> _scanQr(int index) async {
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
      final response = await _api.parseQrImage(File(picked.path));
      if (response['success'] == true) {
        final parsed = response['parsed'];
        _checks[index].docDate = parsed['doc_date'] ?? '';
        _checks[index].amount = (parsed['amount'] as num?)?.toDouble() ?? 0.0;
        _checks[index].docNumber = parsed['doc_number'] ?? '';

        if (_data.fnsToken.isNotEmpty && response['raw'] != null) {
          try {
            final fns = await _api.fetchReceipt(
              response['raw'] as String,
              _data.fnsToken,
            );
            if (fns['success'] == true) {
              final items = (fns['items'] as List?)
                      ?.map((i) => i['name'] as String?)
                      .where((n) => n != null && n.isNotEmpty)
                      .toList() ??
                  [];
              if (items.isNotEmpty) {
                _checks[index].name = items.join(', ');
              }
              final shop = fns['shop'] as String? ?? '';
              if (shop.isNotEmpty) {
                _checks[index].docNumber =
                    '${_checks[index].docNumber}, $shop'.trim();
              }
              if (fns['total'] != null) {
                _checks[index].amount = (fns['total'] as num).toDouble();
              }
              if (fns['doc_date'] != null) {
                _checks[index].docDate = fns['doc_date'] as String;
              }
              _showSnack('✅ Данные из ФНС загружены: ${items.length} товаров');
            } else {
              _showSnack('⚠️ QR распознан, но данные ФНС недоступны');
            }
          } catch (e) {
            _showSnack('⚠️ QR распознан, но данные ФНС недоступны');
          }
        } else {
          _showSnack('✅ QR распознан. Введите наименование вручную.');
        }
        _checks[index].revision++;
        setState(() {});
      } else {
        _showSnack('❌ Не удалось распознать QR-код на фото');
      }
    } catch (e) {
      _showSnack('❌ Ошибка: $e');
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
      final result = await _api.generateReport(_data, _checks);
      setState(() {
        _xlsUrl = result['xls'];
        _pdfUrl = result['pdf'];
      });
      _showSnack('✅ Документы сгенерированы!');
    } catch (e) {
      _showSnack('❌ Ошибка: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _download(String? urlPath, String fileName) async {
    if (urlPath == null) return;
    try {
      final file = await _api.downloadFile(urlPath, fileName);
      await Share.shareXFiles([XFile(file.path)], text: fileName);
    } catch (e) {
      _showSnack('❌ Ошибка скачивания: $e');
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
                  // Заглушка: обновление приложения
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
                        (v) => _data.advanceReceived = v,
                      ),
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
        onChanged: onChanged,
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
        onChanged: (v) => onChanged(double.tryParse(v) ?? 0.0),
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
}
