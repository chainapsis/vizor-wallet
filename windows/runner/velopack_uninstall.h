#ifndef RUNNER_VELOPACK_UNINSTALL_H_
#define RUNNER_VELOPACK_UNINSTALL_H_

// Runs Velopack lifecycle hooks before Flutter starts. Velopack may terminate
// the process while handling install, update, or uninstall hook invocations.
void RunVelopackHooks();

#endif  // RUNNER_VELOPACK_UNINSTALL_H_
