#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

enum class SingleInstanceAcquireResult {
  kPrimary,
  kSecondary,
  kError,
};

// Holds an OS file lock for the lifetime of the primary Vizor process.
//
// The lock lives in the current user's LocalAppData and is keyed by
// VIZOR_WINDOWS_STORAGE_PREFIX, so processes that share wallet storage also
// share the same instance boundary. The lock is released automatically when
// the handle is closed, including after an abnormal process termination.
class SingleInstanceGuard {
 public:
  SingleInstanceGuard();
  ~SingleInstanceGuard();

  SingleInstanceGuard(const SingleInstanceGuard&) = delete;
  SingleInstanceGuard& operator=(const SingleInstanceGuard&) = delete;

  SingleInstanceAcquireResult Acquire();

  UINT activation_message() const { return activation_message_; }
  DWORD last_error() const { return last_error_; }

 private:
  HANDLE lock_file_ = INVALID_HANDLE_VALUE;
  OVERLAPPED lock_overlapped_{};
  UINT activation_message_ = 0;
  DWORD last_error_ = ERROR_SUCCESS;
  bool acquire_attempted_ = false;
  bool lock_held_ = false;
};

// Result returned by the matching primary window for an activation message.
constexpr LRESULT kSingleInstanceActivationAcknowledged = 0x56495A4F;

// Tries briefly to find the primary window in the current interactive session
// and asks it to restore and activate itself. Returns false when the primary is
// still starting, hung, elevated beyond the caller, or running in another
// Windows session. Process exclusion remains enforced by the file lock.
bool ActivateExistingInstance(UINT activation_message);

#endif  // RUNNER_SINGLE_INSTANCE_H_
