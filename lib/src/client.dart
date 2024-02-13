import 'dart:async';
import 'dart:developer';
import 'dart:math' show min;
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:http/http.dart' as http;
import 'package:speed_test_dart/speed_test_dart.dart';
import 'package:tus_client_dart/tus_client_dart.dart';
import 'package:universal_io/io.dart';

/// This class is used for creating or resuming uploads.
class TusClient extends TusClientBase {
  TusClient(
    super.file, {
    super.store,
    super.maxChunkSize,
    super.maxRetries,
    super.retryScale,
    super.firstRetryCooldownTimeSecond,
  }) {
    _fingerprint = generateFingerprint() ?? '';
  }

  /// Override this method to use a custom Client
  http.Client getHttpClient() => http.Client();

  int _actualRetry = 0;

  /// Create a new [upload] throwing [ProtocolException] on server error
  @override
  Future<void> createUpload() async {
    try {
      _fileSize = await file.length();

      final client = getHttpClient();
      final createHeaders = Map<String, String>.from(headers ?? {})
        ..addAll({
          'Tus-Resumable': tusVersion,
          'Upload-Metadata': _uploadMetadata ?? '',
          'Upload-Length': '$_fileSize',
        });

      final uri = url;

      if (uri == null) {
        throw ProtocolException('Error in request, URL is incorrect');
      }

      final response = await client.post(uri, headers: createHeaders);

      if (!(response.statusCode >= 200 && response.statusCode < 300) &&
          response.statusCode != 404) {
        throw ProtocolException(
          'Unexpected Error while creating upload',
          response.statusCode,
        );
      }

      final urlStr = response.headers['location'] ?? '';
      if (urlStr.isEmpty) {
        throw ProtocolException(
          'missing upload Uri in response for creating upload',
        );
      }

      _uploadUrl = _parseUrl(urlStr);
      await store?.storeUploadInfo(_fingerprint, _uploadUrl!);
    } on FileSystemException {
      throw Exception('Cannot find file to upload');
    }
  }

  @override
  Future<bool> isResumable() async {
    try {
      _fileSize = await file.length();
      _pauseUpload = false;

      if (!resumingEnabled) {
        return false;
      }

      _uploadUrl = await store?.fetchUploadUri(_fingerprint);

      if (_uploadUrl == null) {
        return false;
      }
      return true;
    } on FileSystemException {
      throw Exception('Cannot find file to upload');
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> setUploadTestServers() async {
    final tester = SpeedTestDart();

    try {
      final settings = await tester.getSettings();
      final servers = settings.servers;

      bestServers = await tester.getBestServers(
        servers: servers,
      );
    } catch (_) {
      bestServers = null;
    }
  }

  @override
  Future<void> uploadSpeedTest() async {
    final tester = SpeedTestDart();

    // If bestServers are null or they are empty, we will not measure upload
    // speed as it wouldn't be accurate at all
    if (bestServers == null || (bestServers?.isEmpty ?? true)) {
      uploadSpeed = null;
      return;
    }

    try {
      uploadSpeed = await tester.testUploadSpeed(servers: bestServers ?? []);
    } catch (_) {
      uploadSpeed = null;
    }
  }

  /// Start or resume an upload in chunks of [maxChunkSize] throwing
  /// [ProtocolException] on server error
  @override
  Future<void> upload({
    required Uri uri,
    void Function(double, Duration)? onProgress,
    void Function(TusClient, Duration?)? onStart,
    void Function()? onComplete,
    RetryUpload? retryUpload,
    Map<String, String>? metadata = const {},
    Map<String, String>? headers = const {},
    bool measureUploadSpeed = false,
  }) async {
    setUploadData(uri, headers, metadata);

    final canResumeUpload = await isResumable();

    if (measureUploadSpeed) {
      await setUploadTestServers();
      await uploadSpeedTest();
    }

    if (!canResumeUpload) {
      await createUpload();
    }

    // get offset from server
    _offset = await _getOffset();

    // Save the file size as an int in a variable to avoid having to call
    final totalBytes = _fileSize!;

    // We start a stopwatch to calculate the upload speed
    final uploadStopwatch = Stopwatch()..start();

    // start upload
    final client = getHttpClient();

    if (onStart != null) {
      Duration? estimate;
      if (uploadSpeed != null) {
        final workedUploadSpeed = uploadSpeed! * 1000000;

        estimate = Duration(
          seconds: (totalBytes / workedUploadSpeed).round(),
        );
      }
      // The time remaining to finish the upload
      onStart(this, estimate);
    }

    while (!_pauseUpload && _offset < totalBytes) {
      final uploadHeaders = Map<String, String>.from(headers ?? {})
        ..addAll({
          'Tus-Resumable': tusVersion,
          'Upload-Offset': '$_offset',
          'Content-Type': 'application/offset+octet-stream',
        });

      await _performUpload(
        onComplete: onComplete,
        onProgress: onProgress,
        uploadHeaders: uploadHeaders,
        client: client,
        uploadStopwatch: uploadStopwatch,
        totalBytes: totalBytes,
      );
    }
  }

  Future<void> _performUpload({
    required Map<String, String> uploadHeaders,
    required http.Client client,
    required Stopwatch uploadStopwatch,
    required int totalBytes,
    FutureOr<void> Function(double, Duration)? onProgress,
    FutureOr<void> Function()? onComplete,
    RetryUpload? retryUpload,
  }) async {
    try {
      final uri = _uploadUrl;
      if (uri == null) {
        throw ProtocolException(
          'Missing upload Uri in response for creating upload',
        );
      }
      final request = http.Request('PATCH', uri)
        ..headers.addAll(uploadHeaders)
        ..bodyBytes = await _getData();
      _response = await client.send(request);

      if (_response != null) {
        _response?.stream.listen(
          (newBytes) {
            if (_actualRetry != 0) _actualRetry = 0;
          },
          onDone: () {
            if (onProgress != null && !_pauseUpload) {
              // Total byte sent
              final totalSent = _offset + maxChunkSize;
              var workedUploadSpeed = 1.0;

              // If upload speed != null, it means it has been measured
              if (uploadSpeed != null) {
                // Multiplied by 10^6 to convert from Mb/s to b/s
                workedUploadSpeed = uploadSpeed! * 1000000;
              } else {
                workedUploadSpeed =
                    totalSent / uploadStopwatch.elapsedMilliseconds;
              }

              // The data that hasn't been sent yet
              final remainData = totalBytes - totalSent;

              // The time remaining to finish the upload
              final estimate = Duration(
                seconds: (remainData / workedUploadSpeed).round(),
              );

              final progress = totalSent / totalBytes * 100;
              onProgress(progress.clamp(0, 100), estimate);
              _actualRetry = 0;
            }
          },
        );

        // check if correctly uploaded
        if (!(_response!.statusCode >= 200 && _response!.statusCode < 300)) {
          throw ProtocolException(
            'Error while uploading file',
            _response!.statusCode,
          );
        }

        final serverOffset = _parseOffset(_response!.headers['upload-offset']);
        if (serverOffset == null) {
          throw ProtocolException(
            '''Response to PATCH request contains no or invalid Upload-Offset header''',
          );
        }
        if (_offset != serverOffset) {
          throw ProtocolException(
            '''Response contains different Upload-Offset value ($serverOffset) than expected ($_offset)''',
          );
        }

        if (_offset == totalBytes && !_pauseUpload) {
         await onComplete?.call();
          if (onComplete != null) {
            onComplete();
          }
        }
      } else {
        throw ProtocolException('Error getting Response from server');
      }
    } catch (e) {
      if (_actualRetry >= maxRetries) rethrow;
      final waitInterval = retryScale.getInterval(
        _actualRetry,
        firstRetryCooldownTimeSecond,
      );
      _actualRetry += 1;
      log('Failed to upload,try: $_actualRetry, interval: $waitInterval');
     await retryUpload?.call(waitInterval, _performUpload);
    }
  }

  /// Pause the current upload
  @override
  Future<bool> pauseUpload() async {
    try {
      _pauseUpload = true;
      _response?.stream.timeout(Duration.zero);
      return true;
    } catch (e) {
      throw Exception('Error pausing upload');
    }
  }

  @override
  Future<bool> cancelUpload() async {
    try {
      await pauseUpload();
      await store?.deleteUploadEntry(_fingerprint);
      return true;
    } catch (_) {
      throw Exception('Error cancelling upload');
    }
  }

  void setUploadData(
    Uri url,
    Map<String, String>? headers,
    Map<String, String>? metadata,
  ) {
    this.url = url;
    this.headers = headers;
    this.metadata = metadata;
    _uploadMetadata = generateMetadata();
  }

  /// Get offset from server throwing [ProtocolException] on error
  Future<int> _getOffset() async {
    final client = getHttpClient();

    final offsetHeaders = Map<String, String>.from(headers ?? {})
      ..addAll({
        'Tus-Resumable': tusVersion,
      });
    final response = await client.head(_uploadUrl!, headers: offsetHeaders);

    if (!(response.statusCode >= 200 && response.statusCode < 300)) {
      throw ProtocolException(
        'Unexpected error while resuming upload',
        response.statusCode,
      );
    }

    final serverOffset = _parseOffset(response.headers['upload-offset']);
    if (serverOffset == null) {
      throw ProtocolException(
        'missing upload offset in response for resuming upload',
      );
    }
    return serverOffset;
  }

  /// Get data from file to upload

  Future<Uint8List> _getData() async {
    final start = _offset;
    var end = _offset + maxChunkSize;
    end = end > (_fileSize ?? 0) ? _fileSize ?? 0 : end;

    final result = BytesBuilder();
    await for (final chunk in file.openRead(start, end)) {
      result.add(chunk);
    }

    final bytesRead = min(maxChunkSize, result.length);
    _offset = _offset + bytesRead;

    return result.takeBytes();
  }

  int? _parseOffset(String? offsetValue) {
    var offset = offsetValue;
    if (offset == null || offset.isEmpty) {
      return null;
    }
    if (offset.contains(',')) {
      offset = offset.substring(0, offset.indexOf(','));
    }
    return int.tryParse(offset);
  }

  Uri _parseUrl(String urlString) {
    var urlStr = urlString;
    if (urlStr.contains(',')) {
      urlStr = urlStr.substring(0, urlStr.indexOf(','));
    }
    var uploadUrl = Uri.parse(urlStr);
    if (uploadUrl.host.isEmpty) {
      uploadUrl = uploadUrl.replace(host: url?.host, port: url?.port);
    }
    if (uploadUrl.scheme.isEmpty) {
      uploadUrl = uploadUrl.replace(scheme: url?.scheme);
    }
    return uploadUrl;
  }

  http.StreamedResponse? _response;

  int? _fileSize;

  String _fingerprint = '';

  String? _uploadMetadata;

  Uri? _uploadUrl;

  int _offset = 0;

  bool _pauseUpload = false;

  /// The URI on the server for the file
  Uri? get uploadUrl => _uploadUrl;

  /// The fingerprint of the file being uploaded
  String get fingerprint => _fingerprint;

  /// The 'Upload-Metadata' header sent to server
  String get uploadMetadata => _uploadMetadata ?? '';
}
