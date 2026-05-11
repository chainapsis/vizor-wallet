import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../../core/storage/wallet_paths.dart';

const _saplingSpendHash = 'a15ab54c2888880e53c823a3063820c728444126';
const _saplingOutputHash = '0ebc5a1ef3653948e1c46cf7a16071eac4b7e352';
const _saplingParamBaseUrl = 'https://download.z.cash/downloads/';

class SaplingParamsStatus {
  const SaplingParamsStatus({
    required this.spendPath,
    required this.outputPath,
    required this.spendExists,
    required this.outputExists,
  });

  final String spendPath;
  final String outputPath;
  final bool spendExists;
  final bool outputExists;

  bool get complete => spendExists && outputExists;
}

Future<SaplingParamsStatus> loadSaplingParamsStatus() async {
  final supportDir = await getWalletSupportDirectory();
  final paramsDir = '${supportDir.path}${Platform.pathSeparator}sapling_params';
  final spendPath = '$paramsDir${Platform.pathSeparator}sapling-spend.params';
  final outputPath = '$paramsDir${Platform.pathSeparator}sapling-output.params';

  return SaplingParamsStatus(
    spendPath: spendPath,
    outputPath: outputPath,
    spendExists: File(spendPath).existsSync(),
    outputExists: File(outputPath).existsSync(),
  );
}

Future<void> downloadMissingSaplingParams(
  SaplingParamsStatus status, {
  required void Function(String message) log,
}) async {
  final paramsDir = File(status.spendPath).parent;
  await paramsDir.create(recursive: true);

  if (!status.spendExists) {
    await _downloadAndVerify(
      '${_saplingParamBaseUrl}sapling-spend.params',
      status.spendPath,
      _saplingSpendHash,
      log: log,
    );
  }
  if (!status.outputExists) {
    await _downloadAndVerify(
      '${_saplingParamBaseUrl}sapling-output.params',
      status.outputPath,
      _saplingOutputHash,
      log: log,
    );
  }
}

Future<void> _downloadAndVerify(
  String url,
  String destPath,
  String expectedSha1, {
  required void Function(String message) log,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw Exception('Download failed: HTTP ${response.statusCode} for $url');
    }

    final tempPath = '${destPath}_tmp';
    final file = File(tempPath);
    final sink = file.openWrite();
    await response.pipe(sink);

    final bytes = await File(tempPath).readAsBytes();
    final digest = sha1.convert(bytes);
    if (digest.toString() != expectedSha1) {
      await File(tempPath).delete();
      throw Exception('SHA-1 mismatch: expected $expectedSha1, got $digest');
    }

    await File(tempPath).rename(destPath);
    log('downloaded and verified $destPath');
  } finally {
    client.close();
  }
}
