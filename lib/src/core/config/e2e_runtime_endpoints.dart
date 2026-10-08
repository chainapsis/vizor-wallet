import 'e2e_runtime_case_manifest.dart';

String resolveE2eRuntimeLightwalletdUrl({
  required int defaultPort,
  E2eRuntimeCaseManifest? manifest,
}) => manifest?.lightwalletdUrl ?? 'http://127.0.0.1:$defaultPort';

String resolveE2eRuntimePrimaryProxyUrl({
  required int defaultPort,
  E2eRuntimeCaseManifest? manifest,
}) => manifest?.primaryProxyUrl ?? 'http://127.0.0.1:$defaultPort';
