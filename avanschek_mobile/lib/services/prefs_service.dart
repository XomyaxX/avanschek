import 'package:shared_preferences/shared_preferences.dart';

class PrefsService {
  static const String _keyFio = 'user_fio';
  static const String _keyPosition = 'user_position';
  static const String _keyToken = 'fns_token';
  static const String _keyOrganization = 'user_organization';
  static const String _keyDepartment = 'user_department';
  static const String _keyPurpose = 'user_purpose';
  static const String _keyHasSeenOnboarding = 'has_seen_onboarding';

  static Future<bool> getHasSeenOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasSeenOnboarding) ?? false;
  }

  static Future<void> setHasSeenOnboarding(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasSeenOnboarding, value);
  }

  static Future<String> getFio() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyFio) ?? '';
  }

  static Future<void> setFio(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyFio, value);
  }

  static Future<String> getPosition() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPosition) ?? '';
  }

  static Future<void> setPosition(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPosition, value);
  }

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) ?? '';
  }

  static Future<void> setToken(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, value);
  }

  static Future<String> getOrganization() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyOrganization) ?? '';
  }

  static Future<void> setOrganization(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyOrganization, value);
  }

  static Future<String> getDepartment() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyDepartment) ?? '';
  }

  static Future<void> setDepartment(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyDepartment, value);
  }

  static Future<String> getPurpose() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyPurpose) ?? '';
  }

  static Future<void> setPurpose(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPurpose, value);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFio);
    await prefs.remove(_keyPosition);
    await prefs.remove(_keyToken);
    await prefs.remove(_keyOrganization);
    await prefs.remove(_keyDepartment);
    await prefs.remove(_keyPurpose);
    await prefs.remove(_keyHasSeenOnboarding);
  }
}
