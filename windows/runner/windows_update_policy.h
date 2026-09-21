#ifndef RUNNER_WINDOWS_UPDATE_POLICY_H_
#define RUNNER_WINDOWS_UPDATE_POLICY_H_
#include <algorithm>
#include <cstdint>
#include <string>

namespace windows_update {
inline std::string Channel(uint16_t native_machine, const std::string& installed_arch,
                           const std::string& network) {
  const std::string arch = native_machine == 0xaa64 ? "arm64" :
      native_machine == 0x8664 ? "x64" : installed_arch;
  return "win-" + arch + "-" + network;
}
inline bool SafeVersion(const std::string& version) {
  return !version.empty() && version.size() <= 128 &&
      std::all_of(version.begin(), version.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') ||
            (c >= 'A' && c <= 'Z') || c == '.' || c == '-' || c == '+';
      });
}
inline bool ValidAsset(const std::string& id, const std::string& version,
                       const std::string& type, const std::string& filename,
                       const std::string& sha256, const std::string& expected_id,
                       const std::string& channel) {
  return id == expected_id && SafeVersion(version) && type == "Full" &&
      filename == id + "-" + version + "-" + channel + "-full.nupkg" &&
      sha256.size() == 64 && std::all_of(sha256.begin(), sha256.end(), [](unsigned char c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
      });
}
}  // namespace windows_update
#endif
