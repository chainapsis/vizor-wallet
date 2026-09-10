#include "single_instance.h"

#include <gio/gio.h>
#include <glib/gstdio.h>
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cerrno>

SingleInstanceGuard::~SingleInstanceGuard() {
  if (lock_file_ >= 0) {
    close(lock_file_);
  }
}

SingleInstanceAcquireResult SingleInstanceGuard::Acquire(
    const char* application_id) {
  if (acquire_attempted_) {
    last_error_ = EALREADY;
    return SingleInstanceAcquireResult::kError;
  }
  acquire_attempted_ = true;
  if (application_id == nullptr || !g_application_id_is_valid(application_id)) {
    last_error_ = EINVAL;
    return SingleInstanceAcquireResult::kError;
  }

  // XDG_RUNTIME_DIR is shared by the user's login sessions. Unlike a D-Bus
  // name, this lock also excludes a process on a different session bus.
  g_autofree gchar* directory = g_build_filename(
      g_get_user_runtime_dir(), "vizor-instance-locks", nullptr);
  if (g_mkdir_with_parents(directory, 0700) != 0) {
    last_error_ = errno;
    return SingleInstanceAcquireResult::kError;
  }
  const int directory_fd =
      open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
  if (directory_fd < 0) {
    last_error_ = errno;
    return SingleInstanceAcquireResult::kError;
  }
  struct stat directory_stat {};
  if (fstat(directory_fd, &directory_stat) != 0) {
    last_error_ = errno;
    close(directory_fd);
    return SingleInstanceAcquireResult::kError;
  }
  if (directory_stat.st_uid != geteuid() ||
      (directory_stat.st_mode & 0022) != 0) {
    last_error_ = EACCES;
    close(directory_fd);
    return SingleInstanceAcquireResult::kError;
  }

  g_autofree gchar* filename = g_strconcat(application_id, ".lock", nullptr);
  lock_file_ = openat(directory_fd, filename,
                      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
  last_error_ = lock_file_ < 0 ? errno : 0;
  close(directory_fd);
  if (lock_file_ < 0) {
    return SingleInstanceAcquireResult::kError;
  }
  struct stat file_stat {};
  if (fstat(lock_file_, &file_stat) != 0) {
    last_error_ = errno;
  } else if (!S_ISREG(file_stat.st_mode) || file_stat.st_uid != geteuid()) {
    last_error_ = EACCES;
  } else if (flock(lock_file_, LOCK_EX | LOCK_NB) == 0) {
    return SingleInstanceAcquireResult::kPrimary;
  } else {
    last_error_ = errno;
  }

  close(lock_file_);
  lock_file_ = -1;
  if (last_error_ == EWOULDBLOCK || last_error_ == EAGAIN) {
    return SingleInstanceAcquireResult::kSecondary;
  }
  return SingleInstanceAcquireResult::kError;
}
