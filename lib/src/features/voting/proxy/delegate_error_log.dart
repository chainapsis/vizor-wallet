import '../../../rust/api/proxy_delegate.dart' as rust;
import '../../../rust/api/proxy_registry.dart' as rust_registry;
import 'proxy_delegation_models.dart';

/// [error] for a delegate-mode log line: its type, or a bridged
/// delegate-mode error's kind, and its message, with URLs and long tokens
/// such as keys, signatures and hashes redacted. No message carries a
/// secret.
String describeDelegateError(Object error) {
  if (error is rust_registry.ApiProxyRegistryError) {
    return describeProxyRegistryError(error);
  }
  final (label, text) = error is rust.ApiDelegateModeError
      ? (error.kind.name, error.message)
      : ('${error.runtimeType}', error.toString());
  final message = text
      .replaceAll(RegExp(r'[A-Za-z][A-Za-z0-9+.-]*://\S+'), '<url>')
      .replaceAll(RegExp(r'[A-Za-z0-9+/=_-]{32,}'), '<redacted>')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  const limit = 200;
  final bounded = message.length > limit
      ? '${message.substring(0, limit)}...'
      : message;
  return '$label: $bounded';
}
