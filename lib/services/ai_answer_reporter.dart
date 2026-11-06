import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/release_config.dart';

class ReportException implements Exception {
  final String message;
  const ReportException(this.message);
}

/// Reports are user-initiated. No property database, keys or hidden chat context
/// are attached. The selected answer is included only with explicit opt-in.
class AiAnswerReporter {
  final http.Client client;
  final Uri endpoint;
  AiAnswerReporter({http.Client? client, Uri? endpoint})
    : client = client ?? http.Client(),
      endpoint = endpoint ?? Uri.parse(ReleaseConfig.reportEndpoint);
  Future<void> send({
    required String reason,
    required String comments,
    String? answer,
  }) async {
    if (endpoint.scheme != 'https' ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty) {
      throw const ReportException(
        'Reporting is not configured. Contact support from Privacy & support.',
      );
    }
    if (comments.trim().isEmpty && (answer == null || answer.trim().isEmpty)) {
      throw const ReportException(
        'Add a comment or include the answer so support can review the problem.',
      );
    }
    if (comments.length > 2000 || (answer?.length ?? 0) > 12000) {
      throw const ReportException('The report is too long. Please shorten it.');
    }
    try {
      final response = await client
          .post(
            endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'name': 'LandO in-app answer report',
              '_subject': 'LandO AI answer report',
              '_captcha': 'false',
              'reason': reason,
              'comments': _redact(comments.trim()),
              if (answer != null) 'selected_answer': _redact(answer),
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 || response.body.length > 100000) {
        throw const ReportException(
          'Report was not confirmed. Check your connection and try again.',
        );
      }
      final data = jsonDecode(response.body);
      if (data is! Map ||
          (data['success'] != true && data['success'] != 'true')) {
        throw const ReportException(
          'The reporting service did not accept this report. Please try again later.',
        );
      }
      final status = (data['message'] ?? '').toString().toLowerCase();
      if (status.contains('activat') || status.contains('confirm your')) {
        throw const ReportException(
          'Report delivery is awaiting setup. Contact support from Privacy & support.',
        );
      }
    } on ReportException {
      rethrow;
    } on Object {
      throw const ReportException(
        'Report was not confirmed. Check your connection and try again.',
      );
    }
  }

  static String _redact(String text) => text.replaceAll(
    RegExp(r'\b(?:AIza[\w-]{20,}|sk-[\w-]{10,}|AQ\.[\w-]{15,})'),
    '[credential removed]',
  );
  void dispose() => client.close();
}
