#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

enum class SingleInstanceAcquireResult {
  kPrimary,
  kSecondary,
  kError,
};

// Protects the Linux keyring namespace, which is keyed by APPLICATION_ID.
// Keep this guard alive until the Flutter application has been disposed.
// The OS releases the lock on process exit; the lock file must not be deleted.
class SingleInstanceGuard {
 public:
  SingleInstanceGuard() = default;
  ~SingleInstanceGuard();

  SingleInstanceGuard(const SingleInstanceGuard&) = delete;
  SingleInstanceGuard& operator=(const SingleInstanceGuard&) = delete;

  SingleInstanceAcquireResult Acquire(const char* application_id);
  int last_error() const { return last_error_; }

 private:
  int lock_file_ = -1;
  int last_error_ = 0;
  bool acquire_attempted_ = false;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
