import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

import 'mobile_test_assets.dart';

const _allPlatforms = {'android', 'ios', 'linux', 'macos', 'web', 'windows'};
const _desktopPlatforms = {'linux', 'macos', 'web', 'windows'};
// Match the pinned Flutter SDK's asset variant directory recognition.
final _resolutionDirectory = RegExp(r'/?(\d+(\.\d*)?)x$');

/// Checks the repository contract independently of the mobile loading filter:
/// desktop/ artwork ships on desktop/web, and other runtime assets are shared.
/// Covers direct directory entries, explicit files, and resolution variants.
List<String> platformAssetContractErrors(
  String pubspec,
  Iterable<String> runtimeAssets,
) {
  final manifest = loadYaml(pubspec) as YamlMap;
  final flutter = manifest['flutter'] as YamlMap;
  final entries = flutter['assets'] as YamlList;
  final fonts = <String>{
    for (final family in flutter['fonts'] as YamlList? ?? [])
      for (final font in (family as YamlMap)['fonts'] as YamlList)
        (font as YamlMap)['asset'] as String,
  };
  final assets = runtimeAssets.toSet();
  final errors = <String>[];
  for (final asset in assets) {
    final actual = <String>{if (fonts.contains(asset)) ..._allPlatforms};
    for (final entry in entries) {
      final path = entry is String
          ? entry
          : (entry as YamlMap)['path'] as String;
      if (!_covers(path, asset, assets)) continue;
      final configured = entry is String
          ? <String>{}
          : ((entry as YamlMap)['platforms'] as YamlList? ?? [])
                .cast<String>()
                .toSet();
      actual.addAll(configured.isEmpty ? _allPlatforms : configured);
    }
    final expected = isDesktopOnlyTestAsset(asset)
        ? _desktopPlatforms
        : _allPlatforms;
    if (!setEquals(actual, expected)) {
      final missing = expected.difference(actual).toList()..sort();
      final unexpected = actual.difference(expected).toList()..sort();
      errors.add('$asset: missing $missing; unexpected $unexpected');
    }
  }
  return errors;
}

bool _covers(String entry, String asset, Set<String> runtimeAssets) {
  if (entry == asset) return true;
  if (entry.endsWith('/')) {
    if (!asset.startsWith(entry)) return false;
    final tail = asset.substring(entry.length).split('/');
    // Flutter discovers directory variants from its direct files, so an
    // orphan variant needs an explicit declaration rather than just a parent.
    return tail.length == 1 ||
        (tail.length == 2 &&
            _resolutionDirectory.hasMatch(tail.first) &&
            runtimeAssets.contains('$entry${tail.last}'));
  }
  // An explicitly declared logical image can have only resolution variants.
  final slash = entry.lastIndexOf('/');
  if (slash < 0) return false;
  final directory = entry.substring(0, slash + 1);
  if (!asset.startsWith(directory)) return false;
  final tail = asset.substring(directory.length).split('/');
  return tail.length == 2 &&
      _resolutionDirectory.hasMatch(tail.first) &&
      tail.last == entry.substring(slash + 1);
}
