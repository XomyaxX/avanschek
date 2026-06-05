import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/prefs_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _fioController = TextEditingController();
  final _positionController = TextEditingController();
  final _tokenController = TextEditingController();
  final _organizationController = TextEditingController();
  final _departmentController = TextEditingController();
  final _purposeController = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final fio = await PrefsService.getFio();
    final position = await PrefsService.getPosition();
    final token = await PrefsService.getToken();
    final organization = await PrefsService.getOrganization();
    final department = await PrefsService.getDepartment();
    final purpose = await PrefsService.getPurpose();
    setState(() {
      _fioController.text = fio;
      _positionController.text = position;
      _tokenController.text = token;
      _organizationController.text = organization.isNotEmpty ? organization : 'ИП Ермилов МВ';
      _departmentController.text = department.isNotEmpty ? department : 'Офис';
      _purposeController.text = purpose.isNotEmpty ? purpose : 'Хоз расходы';
      _loading = false;
    });
  }

  Future<void> _save() async {
    await PrefsService.setFio(_fioController.text.trim());
    await PrefsService.setPosition(_positionController.text.trim());
    await PrefsService.setToken(_tokenController.text.trim());
    await PrefsService.setOrganization(_organizationController.text.trim());
    await PrefsService.setDepartment(_departmentController.text.trim());
    await PrefsService.setPurpose(_purposeController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Данные сохранены')),
      );
    }
  }

  Future<void> _clear() async {
    await PrefsService.clear();
    setState(() {
      _fioController.clear();
      _positionController.clear();
      _tokenController.clear();
      _organizationController.text = 'ИП Ермилов МВ';
      _departmentController.text = 'Офис';
      _purposeController.text = 'Хоз расходы';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🗑️ Данные очищены')),
      );
    }
  }

  Future<void> _openTokenSite() async {
    final uri = Uri.parse('https://proverkacheka.com/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _fioController.dispose();
    _positionController.dispose();
    _tokenController.dispose();
    _organizationController.dispose();
    _departmentController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки профиля'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '👤 Профиль',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _fioController,
                            decoration: const InputDecoration(
                              labelText: 'ФИО подотчётного лица',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _positionController,
                            decoration: const InputDecoration(
                              labelText: 'Должность',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            '🏢 Реквизиты',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _organizationController,
                            decoration: const InputDecoration(
                              labelText: 'Организация',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _departmentController,
                            decoration: const InputDecoration(
                              labelText: 'Подразделение',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _purposeController,
                            decoration: const InputDecoration(
                              labelText: 'Назначение аванса',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            '🔑 Токен ФНС',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _tokenController,
                            decoration: InputDecoration(
                              labelText: 'Токен proverkacheka.com',
                              border: const OutlineInputBorder(),
                              helper: TextButton(
                                onPressed: _openTokenSite,
                                child: const Text(
                                  'Получить токен (~15 чеков/сутки бесплатно)',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton.icon(
                              onPressed: _save,
                              icon: const Icon(Icons.save),
                              label: const Text('Сохранить'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue.shade800,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: OutlinedButton.icon(
                              onPressed: _clear,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Очистить память'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
