# flutter_secure_storage_windows

This is the platform-specific implementation of `flutter_secure_storage` for Windows.

## Features

In the Windows implementation of the flutter_secure_storage plugin, sensitive data is securely stored using a combination of local file storage and the Windows Credential Manager. The storage mechanism ensures both confidentiality and integrity through encryption and controlled access.

When a key-value pair is stored, the value is encrypted using the AES-GCM (Galois/Counter Mode) encryption algorithm. The plugin generates a unique encryption key, securely managed and stored in the Windows Credential Manager. This key is used to encrypt the value, and the resulting encrypted data is saved to a file in the application's support directory. Each file is named after the key (with a .secure extension) and contains the encrypted value along with a nonce (used for AES-GCM encryption) and an authentication tag to verify the integrity of the data during decryption.

The directory for storing these files is dynamically determined based on the application's context, ensuring isolation and protection against unauthorized access. Additionally, for backward compatibility, the plugin can store and retrieve data directly from the Windows Credential Manager if needed. This hybrid approach leverages the security of encrypted local storage and the reliability of the Credential Manager, ensuring robust data protection for Flutter applications running on Windows.

## Installation

Ensure the required C++ ATL libraries are installed alongside Visual Studio Build Tools.

## Usage

Refer to the main [flutter_secure_storage README](../README.md) for common usage instructions.

## License

This project is licensed under the BSD 3 License. See the [LICENSE](../LICENSE) file for details.
