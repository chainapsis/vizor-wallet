#include "single_instance.h"

#include <unistd.h>

#include <iostream>
#include <string>

int main(int argc, char** argv) {
  if (argc != 3) return 2;
  SingleInstanceGuard guard;
  const auto result = guard.Acquire(argv[1]);
  if (result == SingleInstanceAcquireResult::kSecondary) return 3;
  if (result == SingleInstanceAcquireResult::kError) {
    std::cerr << guard.last_error() << std::endl;
    return 1;
  }
  std::cout << "primary" << std::endl;
  if (std::string(argv[2]) == "hold") {
    std::string command;
    std::getline(std::cin, command);
    if (command == "exit-without-dispose") {
      // Exercise kernel cleanup without sending a signal to any process.
      _exit(0);
    }
  } else if (std::string(argv[2]) == "exec-child") {
    execl("/bin/sleep", "sleep", "2", nullptr);
    return 2;
  }
  return 0;
}
