import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/storage/wallet_paths.dart';

Future<Directory> votingCacheDirectory() async =>
    Directory('${await getWalletDbPath()}.voting-cache');

/// Full-wallet reset only, after draining voting work. Discover caches without
/// consulting secure storage: a prior failed reset may have erased the DB name.
Future<void> clearVotingCachesForReset({
  Future<Directory> Function() resolveSupportDirectory =
      getWalletSupportDirectory,
  Future<void> Function(Directory)? deleteDirectory,
}) async {
  final root = await resolveSupportDirectory();
  if (!await root.exists()) return;
  // Current randomized DB names (12 random bytes), plus the legacy fixed name.
  final pattern = RegExp(r'^zcash_wallet(?:_[0-9a-f]{24})?\.db\.voting-cache$');
  Object? firstError;
  StackTrace? firstStack;
  await for (final entry in root.list(followLinks: false)) {
    if (entry is! Directory ||
        !pattern.hasMatch(entry.path.split(Platform.pathSeparator).last)) {
      continue;
    }
    try {
      if (deleteDirectory != null) {
        await deleteDirectory(entry);
      } else {
        await entry.delete(recursive: true);
      }
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
  }
  if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
}

/// App-private disposable files, separate from secure storage and voting secrets.
/// Callers hold the voting destructive-operation lease for the whole operation.
class VotingFileCache {
  VotingFileCache({Future<Directory> Function()? directory})
    : directory = directory ?? votingCacheDirectory;
  final Future<Directory> Function() directory;
  static final Map<String, Future<void>> _writes = {};

  static String digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  Future<T> _serialized<T>(String path, Future<T> Function() work) async {
    final previous = _writes[path] ?? Future<void>.value();
    final done = Completer<void>();
    _writes[path] = done.future;
    await previous;
    try {
      return await work();
    } finally {
      done.complete();
      if (identical(_writes[path], done.future)) _writes.remove(path);
    }
  }

  Future<String?> read(String relative) async {
    final file = File('${(await directory()).path}/$relative');
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String relative, String value) async {
    final file = File('${(await directory()).path}/$relative');
    await _serialized(file.path, () => _replace(file, value));
  }

  Future<void> _replace(File file, String value) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.pending');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }

  /// Register before reading the candidate notes. Rust updates this token only
  /// when an actual scan/rewind reaches this snapshot. File.create does not
  /// truncate existing files, including a concurrent Rust token replacement.
  Future<String> snapshotRevision(int snapshot) async {
    final file = File('${(await directory()).path}/snapshots/$snapshot');
    await file.create(recursive: true);
    final revision = await file.readAsString();
    return revision.isEmpty ? '0' : revision;
  }

  String notePath(String account, String scope) =>
      '${digest(account)}/${digest(scope)}.json';

  Future<Map<String, dynamic>> readNotes(String account, String scope) async {
    try {
      final raw = await read(notePath(account, scope));
      if (raw == null) return {};
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['version'] != 1 || json['scope'] != scope) return {};
      final notes = Map<String, dynamic>.from(json['notes'] as Map);
      notes.removeWhere(
        (key, value) =>
            !RegExp(r'^0100[0-9a-f]{128}$').hasMatch(key) ||
            value is! Map ||
            value['used'] is! bool ||
            value['height'] is! int ||
            (value['height'] as int) < 0,
      );
      return notes;
    } catch (_) {
      return {};
    }
  }

  String _endedPath(String network, String round) =>
      'ended-${digest('$network|$round')}';

  Future<void> writeNotes(
    String account,
    String scope,
    Map<String, dynamic> notes,
  ) async {
    final root = await directory();
    final file = File('${root.path}/${notePath(account, scope)}');
    await _serialized(file.path, () async {
      final parts = jsonDecode(scope) as List;
      if (await File(
        '${root.path}/${_endedPath(parts[0] as String, parts[1] as String)}',
      ).exists()) {
        return;
      }
      final merged = await readNotes(account, scope);
      for (final entry in notes.entries) {
        final old = merged[entry.key] as Map?;
        final next = entry.value as Map;
        if (old?['used'] == true) continue;
        if (next['used'] != true &&
            (old?['height'] as int? ?? -1) > (next['height'] as int)) {
          continue;
        }
        merged[entry.key] = next;
      }
      await _replace(
        file,
        jsonEncode({'version': 1, 'scope': scope, 'notes': merged}),
      );
    });
  }

  Future<void> removeAccount(String account) async {
    final folder = Directory('${(await directory()).path}/${digest(account)}');
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  Future<void> clear() async {
    final folder = await directory();
    if (await folder.exists()) await folder.delete(recursive: true);
  }

  /// Scope contains network, round, snapshot, and protocol identity. Only remove
  /// an explicitly ended round, never infer termination from a missing listing.
  Future<void> removeRound(String network, String round) async {
    final folder = await directory();
    if (!await folder.exists()) return;
    await write(_endedPath(network, round), 'ended');
    await for (final file in folder.list(recursive: true, followLinks: false)) {
      if (file is! File ||
          !file.path.endsWith('.json') ||
          file.parent.path == folder.path) {
        continue;
      }
      try {
        final value = jsonDecode(await file.readAsString()) as Map;
        final scope = jsonDecode(value['scope'] as String) as List;
        if (scope[0] == network && scope[1] == round) {
          await _serialized(file.path, () async {
            if (await file.exists()) await file.delete();
          });
        }
      } catch (_) {
        // Corrupt records are retried on demand, not interpreted as termination.
      }
    }
  }
}
