#ifndef RUNNER_VELOPACK_UNINSTALL_H_
#define RUNNER_VELOPACK_UNINSTALL_H_

// Handles Velopack's uninstall hook if the current process was launched for
// uninstall cleanup. Returns true when the process should exit immediately.
bool HandleVelopackUninstallHook();

#endif  // RUNNER_VELOPACK_UNINSTALL_H_
