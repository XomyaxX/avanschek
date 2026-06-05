import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../models/report_data.dart';
import '../models/check.dart';

class ApiService {
  String baseUrl;

  ApiService({this.baseUrl = 'http://192.168.1.132:5000'});

  Future<Map<String, dynamic>> generateReport(
    ReportData data,
    List<Check> checks,
  ) async {
    final url = Uri.parse('$baseUrl/generate');
    final body = jsonEncode({
      'data': data.toJson(),
      'checks': checks.map((c) => c.toJson()).toList(),
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Ошибка генерации');
    }
  }

  Future<Map<String, dynamic>> parseQrImage(File imageFile) async {
    final url = Uri.parse('$baseUrl/parse_qr_image');
    final request = http.MultipartRequest('POST', url);

    // Определяем MIME-тип по расширению файла
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

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Ошибка распознавания QR');
    }
  }

  Future<Map<String, dynamic>> fetchReceipt(String qrraw, String token) async {
    final url = Uri.parse('$baseUrl/fetch_receipt');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'qrraw': qrraw, 'token': token}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['error'] ?? 'Ошибка получения данных из ФНС');
    }
  }

  Future<File> downloadFile(String urlPath, String fileName) async {
    final url = Uri.parse('$baseUrl$urlPath');
    final response = await http.get(url);

    if (response.statusCode != 200) {
      throw Exception('Ошибка скачивания файла');
    }

    final dir = Directory.systemTemp;
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }
}
