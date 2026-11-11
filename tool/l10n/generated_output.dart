import 'dart:io';

/// The first symbolic link among the components of [path] (relative, with
/// `/` separators) under [root], or null.
///
/// Generators refuse to write through one: a checkout could point a
/// generated file, or a directory on the way to it, at a file elsewhere,
/// which the write would truncate.
String? symbolicLinkOnPath(String path, {String root = '.'}) {
  final parts = path.split('/');
  for (var i = 1; i <= parts.length; i++) {
    final prefix = parts.take(i).join('/');
    if (FileSystemEntity.isLinkSync('$root/$prefix')) return prefix;
  }
  return null;
}

/// Reports a symbolic link on [path] and sets a failing exit code.
/// Returns whether [path] is safe to read and write.
bool checkGeneratedOutputPath(String path) {
  final link = symbolicLinkOnPath(path);
  if (link == null) return true;
  stderr.writeln(
    link == path
        ? '$path is a symbolic link; it must be a regular file.'
        : '$link is a symbolic link; $path must not be written through it.',
  );
  exitCode = 1;
  return false;
}

/// Preserve timestamps on identical outputs so native/Flutter builds do not
/// see an unrelated localization save as a source change.
bool writeGeneratedTextIfChanged(
  String path,
  String contents, {
  String root = '.',
}) {
  final link = symbolicLinkOnPath(path, root: root);
  if (link != null) {
    throw FileSystemException('Refusing to write through symbolic link', link);
  }
  final file = File('$root/$path');
  if (file.existsSync() && file.readAsStringSync() == contents) return false;
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(contents);
  return true;
}
