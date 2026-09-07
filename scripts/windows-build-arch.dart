import 'dart:ffi';
import 'dart:io';

// Match Flutter's Windows target selection using the same FVM Dart SDK.
void main() {
  final arch = switch (Abi.current()) {
    Abi.windowsX64 => 'x64',
    Abi.windowsArm64 => 'arm64',
    _ => null,
  };
  if (arch == null) {
    stderr.writeln('Unsupported Windows build SDK ABI: ${Abi.current()}');
    exitCode = 1;
    return;
  }
  stdout.writeln('VIZOR_WINDOWS_BUILD_ARCH=$arch');
}
