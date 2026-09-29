#ifndef RUNNER_WINDOWS_UPDATE_POLICY_H_
#define RUNNER_WINDOWS_UPDATE_POLICY_H_
#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

namespace windows_update {
inline std::string Channel(const std::string& arch, const std::string& network) {
  return "win-" + arch + "-" + network;
}
inline bool ProbeArm64(uint16_t native_machine, const std::string& installed_arch) {
  return installed_arch == "x64" && native_machine == 0xaa64;
}

enum class CheckResult { kNone, kAvailable, kMissing, kTransient, kError };
enum class Choice { kNone, kInstalled, kArm64, kError };

inline CheckResult FeedFailure(uint32_t status, bool signature) {
  // A missing signature on an existing feed is never an absent architecture.
  if (status == 404) return signature ? CheckResult::kError : CheckResult::kMissing;
  if (status == 0 || (status >= 200 && status < 300) || status == 408 ||
      status == 429 || (status >= 500 && status < 600)) return CheckResult::kTransient;
  return CheckResult::kError;
}

inline std::vector<std::string> VersionParts(const std::string& value) {
  std::vector<std::string> parts;
  size_t start = 0;
  for (;;) {
    const auto end = value.find('.', start);
    parts.push_back(value.substr(start, end == std::string::npos ? end : end - start));
    if (end == std::string::npos) return parts;
    start = end + 1;
  }
}
inline bool NumericPart(const std::string& value) {
  return !value.empty() && std::all_of(value.begin(), value.end(),
      [](char c) { return c >= '0' && c <= '9'; });
}
inline int CompareNumber(const std::string& left, const std::string& right) {
  if (left.size() != right.size()) return left.size() < right.size() ? -1 : 1;
  return left.compare(right);
}
// Inputs have already been parsed as SemVer by Velopack's update check.
// Compare numeric identifiers without conversion/overflow; ignore build metadata.
inline int CompareVersions(std::string left, std::string right) {
  left = left.substr(0, left.find('+'));
  right = right.substr(0, right.find('+'));
  const auto ld = left.find('-'), rd = right.find('-');
  const auto lc = VersionParts(left.substr(0, ld));
  const auto rc = VersionParts(right.substr(0, rd));
  for (size_t i = 0; i < std::min(lc.size(), rc.size()); ++i) {
    const int cmp = CompareNumber(lc[i], rc[i]);
    if (cmp != 0) return cmp;
  }
  if (ld == std::string::npos || rd == std::string::npos) {
    return ld == rd ? 0 : ld == std::string::npos ? 1 : -1;
  }
  const auto lp = VersionParts(left.substr(ld + 1));
  const auto rp = VersionParts(right.substr(rd + 1));
  for (size_t i = 0; i < std::min(lp.size(), rp.size()); ++i) {
    const bool ln = NumericPart(lp[i]), rn = NumericPart(rp[i]);
    const int cmp = ln && rn ? CompareNumber(lp[i], rp[i]) :
        ln != rn ? (ln ? -1 : 1) : lp[i].compare(rp[i]);
    if (cmp != 0) return cmp;
  }
  return lp.size() == rp.size() ? 0 : lp.size() < rp.size() ? -1 : 1;
}

inline Choice ChooseUpdate(CheckResult installed, const std::string& installed_version,
                           CheckResult arm64, const std::string& arm64_version) {
  if (installed == CheckResult::kError || arm64 == CheckResult::kError) return Choice::kError;
  if (installed == CheckResult::kAvailable && arm64 == CheckResult::kAvailable) {
    return CompareVersions(arm64_version, installed_version) >= 0 ? Choice::kArm64 : Choice::kInstalled;
  }
  if (arm64 == CheckResult::kAvailable) return Choice::kArm64;
  if (installed == CheckResult::kAvailable) return Choice::kInstalled;
  if (installed == CheckResult::kTransient || arm64 == CheckResult::kTransient) return Choice::kError;
  return Choice::kNone;
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
