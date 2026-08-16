/// ENS name helpers. v1 accepts the deterministic ASCII subset of ENSIP-15
/// (lowercase a-z, 0-9, hyphen; no leading/trailing hyphen; non-empty labels)
/// and rejects anything else instead of guessing at Unicode normalization.
class EnsNameException implements Exception {
  const EnsNameException(this.message);
  final String message;
  @override
  String toString() => 'EnsNameException: $message';
}

final _label = RegExp(r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?$');

bool isEnsName(String input) {
  final t = input.trim().toLowerCase();
  if (!t.endsWith('.eth')) return false;
  return t.split('.').length >= 2 && t.split('.').every((l) => l.isNotEmpty);
}

String normalizeEnsName(String input) {
  final t = input.trim().toLowerCase();
  if (!t.endsWith('.eth')) {
    throw const EnsNameException('Not a .eth name');
  }
  final labels = t.split('.');
  if (labels.length < 2) {
    throw const EnsNameException('Name needs at least one label before .eth');
  }
  for (final label in labels) {
    if (!_label.hasMatch(label)) {
      throw const EnsNameException(
        'Only lowercase letters, numbers, and hyphens are supported',
      );
    }
  }
  return t;
}
