/// This exception is thrown if the server sends a request with an unexpected
/// status code or missing/invalid headers.
class ProtocolException implements Exception {
  ProtocolException(this.message, [this.code]);
  final String message;
  final int? code;

  @override
  String toString() => 'ProtocolException: ($code) $message';
}
