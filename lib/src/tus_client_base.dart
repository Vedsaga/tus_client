import 'dart:async';
import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:speed_test_dart/classes/server.dart';
import 'package:tus_client_dart/tus_client_dart.dart';

typedef PerformUpload = Future<void> Function({
  required Map<String, String> uploadHeaders,
  required http.Client client,
  required Stopwatch uploadStopwatch,
  required int totalBytes,
  void Function(double, Duration)? onProgress,
  void Function()? onComplete,
});

typedef RetryUpload = FutureOr<void> Function(
  Duration retryAfter,
  PerformUpload retry,
);

abstract class TusClientBase {
  TusClientBase(
    this.file, {
    this.maxChunkSizeByte = 6 * 1024 * 1024,
    this.maxRetries = 5,
    this.retryScale = RetryScale.exponential,
    this.firstRetryCooldownTimeSecond = 0,
    this.store,
  });

  /// Version of the tus protocol used by the client. The remote server needs to
  /// support this version, too.
  final tusVersion = '1.0.0';

  /// The tus server Uri
  Uri? url;

  Map<String, String>? metadata;

  /// Any additional headers
  Map<String, String>? headers;

  /// Upload speed in Mb/s
  double? uploadSpeed;

  /// List of [Server] that are good for testing speed
  List<Server>? bestServers;

  /// Create a new upload URL
  Future<void> createUpload();

  /// Checks if upload can be resumed.
  Future<bool> isResumable();

  /// Starts an upload
  Future<void> upload({
    required Uri uri,
    void Function(double, Duration)? onProgress,
    void Function(TusClient, Duration?)? onStart,
    void Function()? onComplete,
    RetryUpload? retryUpload,
    Map<String, String>? metadata = const {},
    Map<String, String>? headers = const {},
  });

  /// Pauses the upload
  Future<bool> pauseUpload();

  /// Cancels the upload
  Future<bool> cancelUpload();

  /// Override this method to customize creating file fingerprint
  String? generateFingerprint() {
    return file.path.replaceAll(RegExp(r'\W+'), '.');
  }

  /// Sets to servers to test for upload speed
  Future<void> setUploadTestServers();

  /// Measures the upload speed of the device
  Future<void> uploadSpeedTest();

  /// Override this to customize creating 'Upload-Metadata'
  String generateMetadata() {
    final meta = Map<String, String>.from(metadata ?? {});

    if (!meta.containsKey('filename')) {
      // Add the filename to the metadata from the whole directory path.
      //I.e: /home/user/file.txt -> file.txt
      meta['filename'] = file.path.split('/').last;
    }

    return meta.entries
        .map(
          (entry) => '${entry.key} ${base64.encode(utf8.encode(entry.value))}',
        )
        .join(',');
  }

  /// Storage used to save and retrieve upload URLs by its fingerprint.
  final TusStore? store;

  /// File to upload, must be in[XFile] type
  final XFile file;

  /// The maximum payload size in bytes when uploading
  /// the file in chunks (6MB)
  final int maxChunkSizeByte;

  /// The number of times that should retry to resume the upload if a failure
  /// occurs after rethrow the error.
  final int maxRetries;

  /// The interval between the first error and the first retry in [seconds].
  final int firstRetryCooldownTimeSecond;

  /// The scale type used to increase the interval of time between every retry.
  final RetryScale retryScale;

  /// Whether the client supports resuming
  bool get resumingEnabled => store != null;
}
