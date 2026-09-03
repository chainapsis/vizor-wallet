import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// Asks the platform's own save panel where a PNG the user is exporting
/// should go, and returns the chosen absolute path (null when cancelled).
///
/// On sandboxed macOS the panel is the only way to reach a folder outside the
/// app container, and it is also where the user confirms replacing a file they
/// already have.
Future<String?> pickPngSaveLocation({required String suggestedName}) async {
  final location = await getSaveLocation(
    suggestedName: suggestedName,
    // Open on Downloads rather than wherever the panel last was: an exported
    // image is something the user is about to hand to someone else.
    initialDirectory: await _downloadsDirectoryPath(),
    canCreateDirectories: true,
    acceptedTypeGroups: const [
      XTypeGroup(
        label: 'PNG image',
        extensions: ['png'],
        mimeTypes: ['image/png'],
        uniformTypeIdentifiers: ['public.png'],
      ),
    ],
  );
  return location?.path;
}

/// The platform Downloads folder, or null when the platform has none — the
/// panel then opens wherever it would have anyway.
Future<String?> _downloadsDirectoryPath() async {
  try {
    return (await getDownloadsDirectory())?.path;
  } on Object {
    return null;
  }
}
