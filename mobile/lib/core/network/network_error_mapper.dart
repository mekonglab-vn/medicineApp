import 'package:dio/dio.dart';

enum NetworkIssueKind {
  noConnection,
  timeout,
  serviceUnavailable,
  serverError,
  unauthorized,
  unknown,
}

NetworkIssueKind classifyNetworkIssue(Object error) {
  if (error is DioException) {
    return _classifyDioException(error);
  }

  return _classifyRawText(error.toString());
}

String toFriendlyNetworkMessage(
  Object error, {
  String genericMessage = 'Đã xảy ra lỗi. Vui lòng thử lại.',
}) {
  final issue = classifyNetworkIssue(error);

  switch (issue) {
    case NetworkIssueKind.noConnection:
      return 'Bạn đang offline. Vui lòng kiểm tra Wi-Fi hoặc dữ liệu di động rồi thử lại.';
    case NetworkIssueKind.timeout:
      return 'Kết nối quá chậm nên yêu cầu đã hết thời gian chờ. Vui lòng thử lại.';
    case NetworkIssueKind.serviceUnavailable:
      return 'Máy chủ đang tạm thời không phản hồi. Vui lòng thử lại sau ít phút.';
    case NetworkIssueKind.serverError:
      return 'Máy chủ đang gặp sự cố. Vui lòng thử lại sau.';
    case NetworkIssueKind.unauthorized:
      return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    case NetworkIssueKind.unknown:
      return genericMessage;
  }
}

NetworkIssueKind _classifyDioException(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return NetworkIssueKind.timeout;
    case DioExceptionType.connectionError:
      return NetworkIssueKind.noConnection;
    case DioExceptionType.badResponse:
      final statusCode = error.response?.statusCode;
      if (statusCode == 401) {
        return NetworkIssueKind.unauthorized;
      }
      if (statusCode == 408) {
        return NetworkIssueKind.timeout;
      }
      if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
        return NetworkIssueKind.serviceUnavailable;
      }
      if (statusCode != null && statusCode >= 500) {
        return NetworkIssueKind.serverError;
      }
      break;
    case DioExceptionType.badCertificate:
    case DioExceptionType.cancel:
    case DioExceptionType.unknown:
      break;
  }

  final raw = [
    error.message,
    error.error?.toString(),
    error.response?.statusMessage,
    error.response?.data?.toString(),
  ].whereType<String>().join(' ');

  return _classifyRawText(raw, fallbackStatusCode: error.response?.statusCode);
}

NetworkIssueKind _classifyRawText(String raw, {int? fallbackStatusCode}) {
  final text = raw.toLowerCase();
  final statusCode = _extractStatusCode(text) ?? fallbackStatusCode;

  if (statusCode != null) {
    if (statusCode == 401) {
      return NetworkIssueKind.unauthorized;
    }
    if (statusCode == 408) {
      return NetworkIssueKind.timeout;
    }
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return NetworkIssueKind.serviceUnavailable;
    }
    if (statusCode >= 500) {
      return NetworkIssueKind.serverError;
    }
  }

  if (_containsAny(text, const [
    'socketexception',
    'failed host lookup',
    'connection refused',
    'connection reset by peer',
    'connection closed',
    'network is unreachable',
    'no route to host',
    'không kết nối',
    'khong ket noi',
  ])) {
    return NetworkIssueKind.noConnection;
  }

  if (_containsAny(text, const ['timeout', 'timed out', 'time out'])) {
    return NetworkIssueKind.timeout;
  }

  if (_containsAny(text, const [
    'service unavailable',
    'temporarily unavailable',
    'upstream connect error',
    'bad gateway',
    'gateway timeout',
    'server unavailable',
  ])) {
    return NetworkIssueKind.serviceUnavailable;
  }

  return NetworkIssueKind.unknown;
}

bool _containsAny(String value, List<String> probes) {
  for (final probe in probes) {
    if (value.contains(probe)) {
      return true;
    }
  }
  return false;
}

int? _extractStatusCode(String value) {
  final codePattern = RegExp(r'(status\s*code(?:\s*of)?|http)\D*(\d{3})');
  final match = codePattern.firstMatch(value);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(2) ?? '');
}
