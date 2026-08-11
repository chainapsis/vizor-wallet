# flutter_secure_storage_windows

This is the platform-specific implementation of `flutter_secure_storage` for Windows.

## Features

This implementation serializes all key-value pairs into one JSON object and
protects the complete payload with Windows Data Protection API (DPAPI). The
encrypted payload is stored as `flutter_secure_storage.dat` in the
application-support directory. DPAPI binds decryption to the Windows user
account that encrypted the data; this implementation does not create or store
a separate AES key in Windows Credential Manager.

Windows Credential Manager is accessed only by the optional backward-
compatibility path for reading, migrating, and removing entries written by an
older implementation.

Vizor vendors this package with atomic replacement, inter-process locking, and
validated backup recovery. See [VIZOR_FORK.md](VIZOR_FORK.md) for the temporary,
backup, recovery-marker, and lock sidecars that accompany the primary data
file.

## Installation

Ensure the required C++ ATL libraries are installed alongside Visual Studio Build Tools.

## Usage

Refer to the main [flutter_secure_storage README](../README.md) for common usage instructions.

## License

This project is licensed under the BSD 3 License. See the [LICENSE](../LICENSE) file for details.
