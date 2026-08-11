# Vizor Windows secure-storage fork

This directory vendors `flutter_secure_storage_windows` 4.1.0. The root
`pubspec.yaml` selects it with a path override because the upstream Windows
implementation writes its DPAPI-encrypted JSON file in place.

Vizor-specific guarantees:

- All public storage operations share one process-wide asynchronous lock.
- A sidecar `.lock` file serializes the complete read-modify-write transaction
  across Windows processes.
- Writes go to a same-directory temporary file, are flushed, and are committed
  with `ReplaceFileW` or `MoveFileExW` instead of overwriting the primary file.
- Successful replacements refresh a validated `.bak` snapshot to the latest
  committed primary, so recovery does not normally resurrect a deleted key.
- A `.bak.invalid` marker prevents a stale backup from being restored if its
  refresh is interrupted after the primary commit. A later successful read
  repairs that backup without turning the committed write into an API failure.
- If `ReplaceFileW` partially fails after moving the old primary to the backup
  path, that validated previous primary is restored before the write error is
  returned. A `.bak.restore` marker makes a transiently failed restoration
  retryable on the next load without treating an unvalidated stale backup as
  recoverable. Every new save must remove any older restore marker before it
  can commit, so restore authorization cannot outlive the backup it validated.
- A primary is recovered only after a DPAPI decryption or payload-format
  failure, and only from a backup that decrypts and parses successfully.
  Transient file-access and other native errors are returned to the caller.
  Unreadable files are never automatically deleted.

Keep changes to the Dart FFI implementation and its tests focused so this fork
can be removed after equivalent behavior ships upstream.
