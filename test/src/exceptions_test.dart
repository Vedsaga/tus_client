import 'package:test/test.dart';
import 'package:tus_client_dart/tus_client_dart.dart';

void main() {
  test('exceptions_test.ProtocolException', () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        '$err',
        'ProtocolException: '
            "(null) Expected HEADER 'Tus-Resumable'");
  });

  test('exceptions_test.ProtocolException.response.shouldRetry', () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        '$err',
        'ProtocolException: '
            "(null) Expected HEADER 'Tus-Resumable'");
  });

  test('exceptions_test.ProtocolException.response.shouldNotRetry', () {
    final err = ProtocolException("Expected HEADER 'Tus-Resumable'");
    expect(
        '$err',
        'ProtocolException: '
            "(null) Expected HEADER 'Tus-Resumable'");
  });
}
