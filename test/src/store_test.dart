import 'package:test/test.dart';
import 'package:tus_client_dart/tus_client_dart.dart';

void main() {
  const fingerprint = 'test';
  const url = 'https://example.com/files/pic.jpg?token=987298374';
  final uri = Uri.parse(url);
  group('url_store:TusMemoryStore', () {
    test('set', () async {
      final store = TusMemoryStore();
      await store.set(fingerprint, uri);
      final foundUrl = await store.get(fingerprint);
      expect(foundUrl, uri);
    });

    test('get.empty', () async {
      final store = TusMemoryStore();
      final foundUrl = await store.get(fingerprint);
      expect(foundUrl, isNull);
    });

    test('remove', () async {
      final store = TusMemoryStore();
      await store.set(fingerprint, uri);
      await store.remove(fingerprint);
      final foundUrl = await store.get(fingerprint);
      expect(foundUrl, isNull);
    });

    test('remove.empty', () async {
      final store = TusMemoryStore();
      var foundUrl = await store.get(fingerprint);
      expect(foundUrl, isNull);
      await store.remove(fingerprint);
      foundUrl = await store.get(fingerprint);
      expect(foundUrl, isNull);
    });
  });
}
