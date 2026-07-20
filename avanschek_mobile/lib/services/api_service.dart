import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/report_data.dart';
import '../models/check.dart';

class ApiService {
  late String baseUrl;

  ApiService({String? baseUrl}) {
    this.baseUrl = baseUrl ?? dotenv.env['API_BASE_URL'] ?? 'http://192.168.1.132:5000';
  }

  static const _timeout = Duration(seconds: 15);

  String _formatError(Object error) {
    if (error is SocketException) {
      return 'Нет подключения к серверу. Проверьте IP-адрес и что сервер запущен.';
    }
    if (error is TimeoutException) {
      return 'Сервер не отвечает. Попробуйте позже.';
    }
    if (error is FormatException) {
      return 'Некорректный ответ сервера.';
    }
    if (error is http.ClientException) {
      return 'Ошибка подключения к серверу.';
    }
    return 'Ошибка сети: $error';
  }

  Future<Map<String, dynamic>> generateReport(
    ReportData data,
    List<Check> checks,
  ) async {
    final url = Uri.parse('$baseUrl/generate');
    final body = jsonEncode({
      'data': data.toJson(),
      'checks': checks.map((c) => c.toJson()).toList(),
    });

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Ошибка генерации');
      }
    } on Exception catch (e) {
      throw Exception(_formatError(e));
    }
  }

  Future<Map<String, dynamic>> parseQrImage(File imageFile) async {
    final url = Uri.parse('$baseUrl/parse_qr_image');
    final request = http.MultipartRequest('POST', url);

    final ext = imageFile.path.split('.').last.toLowerCase();
    String mimeType;
    switch (ext) {
      case 'png':
        mimeType = 'image/png';
        break;
      case 'gif':
        mimeType = 'image/gif';
        break;
      case 'webp':
        mimeType = 'image/webp';
        break;
      case 'jpg':
      case 'jpeg':
      default:
        mimeType = 'image/jpeg';
        break;
    }

    request.files.add(await http.MultipartFile.fromPath(
      'qr_image',
      imageFile.path,
      contentType: MediaType.parse(mimeType),
    ));

    try {
      final streamedResponse = await request.send().timeout(_timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Ошибка распознавания QR');
      }
    } on Exception catch (e) {
      throw Exception(_formatError(e));
    }
  }

  Future<Map<String, dynamic>> fetchReceipt(String qrraw, String token) async {
    final url = Uri.parse('$baseUrl/fetch_receipt');

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'qrraw': qrraw, 'token': token}),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Ошибка получения данных из ФНС');
      }
    } on Exception catch (e) {
      throw Exception(_formatError(e));
    }
  }

  Future<File> downloadFile(String urlPath, String fileName) async {
    final url = Uri.parse('$baseUrl$urlPath');

    try {
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Ошибка скачивания файла');
      }

      final dir = Directory.systemTemp;
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } on Exception catch (e) {
      throw Exception(_formatError(e));
    }
  }

  /// Проверка наличия обновления на сервере.
  /// Ожидаемый ответ сервера (GET /check_update):
  /// {
  ///   "version": "1.0.1",
  ///   "build_number": "2",
  ///   "apk_url": "/downloads/avanschek-1.0.1.apk",  // относительный или полный URL
  ///   "changelog": "Что нового..."
  /// }
  Future<UpdateInfo?> checkForUpdate() async {
    final url = Uri.parse('$baseUrl/check_update');
    try {
      final response = await http.get(url).timeout(_timeout);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return UpdateInfo.fromJson(data);
      }
    } on Exception {
      // Не падаем — просто нет обновления или сервер не поддерживает
    }
    return null;
  }

  /// Скачивание APK с прогрессом (0.0 - 1.0).
  /// urlPathOrFull — относительный путь или полный http URL.
  /// onProgress вызывается по мере загрузки.
  Future<File> downloadApkWithProgress(
    String urlPathOrFull,
    String fileName,
    void Function(double progress) onProgress,
  ) async {
    Uri url;
    if (urlPathOrFull.startsWith('http://') || urlPathOrFull.startsWith('https://')) {
      url = Uri.parse(urlPathOrFull);
    } else {
      url = Uri.parse('$baseUrl$urlPathOrFull');
    }

    try {
      final request = http.Request('GET', url);
      final client = http.Client();
      final streamedResponse = await client.send(request).timeout(_timeout);

      if (streamedResponse.statusCode != 200) {
        client.close();
        throw Exception('Ошибка скачивания APK (${streamedResponse.statusCode})');
      }

      final contentLength = streamedResponse.contentLength ?? 0;
      int downloaded = 0;
      final bytes = <int>[];

      await for (final chunk in streamedResponse.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength);
        }
      }

      client.close();

      final dir = Directory.systemTemp;
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      return file;
    } on Exception catch (e) {
      throw Exception(_formatError(e));
    }
  }
}

/// Простая модель информации об обновлении.
class UpdateInfo {
  final String version;
  final String buildNumber;
  final String apkUrl;
  final String? changelog;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.apkUrl,
    this.changelog,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version']?.toString() ?? '',
      buildNumber: json['build_number']?.toString() ?? '',
      apkUrl: json['apk_url']?.toString() ?? '',
      changelog: json['changelog']?.toString(),
    );
  }
}
