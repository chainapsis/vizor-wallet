#include "../../windows/runner/windows_update_policy.h"
#include <cassert>
#include <iostream>
int main() {
  using namespace windows_update;
  assert(Channel("x64", "mainnet") == "win-x64-mainnet");
  assert(Channel("arm64", "testnet") == "win-arm64-testnet");
  assert(ProbeArm64(0xaa64, "x64"));
  assert(!ProbeArm64(0xaa64, "arm64"));
  assert(!ProbeArm64(0x8664, "x64"));
  assert(!ProbeArm64(0, "x64"));
  assert(!ProbeArm64(0x1234, "arm64"));

  using R = CheckResult;
  using C = Choice;
  // ARM64 absent, empty, old, or already at the installed version: continue x64.
  for (const auto arm : {R::kMissing, R::kNone, R::kTransient}) {
    assert(ChooseUpdate(R::kAvailable, "1.2.3", arm, "") == C::kInstalled);
  }
  assert(ChooseUpdate(R::kNone, "", R::kMissing, "") == C::kNone);
  assert(ChooseUpdate(R::kNone, "", R::kNone, "") == C::kNone);
  assert(ChooseUpdate(R::kAvailable, "1.2.3", R::kAvailable, "1.2.3") == C::kArm64);
  assert(ChooseUpdate(R::kAvailable, "1.2.4", R::kAvailable, "1.2.3") == C::kInstalled);
  assert(ChooseUpdate(R::kAvailable, "1.2.3", R::kAvailable, "1.2.4") == C::kArm64);
  assert(ChooseUpdate(R::kNone, "", R::kAvailable, "1.2.4") == C::kArm64);
  assert(ChooseUpdate(R::kTransient, "", R::kAvailable, "1.2.4") == C::kArm64);
  assert(ChooseUpdate(R::kNone, "", R::kTransient, "") == C::kError);
  assert(ChooseUpdate(R::kTransient, "", R::kMissing, "") == C::kError);
  assert(ChooseUpdate(R::kTransient, "", R::kTransient, "") == C::kError);
  // Never hide a signature, identity, or format failure behind the other feed.
  assert(ChooseUpdate(R::kAvailable, "1.2.3", R::kError, "") == C::kError);
  assert(ChooseUpdate(R::kError, "", R::kAvailable, "1.2.3") == C::kError);
  assert(FeedFailure(404, false) == R::kMissing);
  assert(FeedFailure(404, true) == R::kError);
  for (const auto status : {0, 200, 408, 429, 500, 502, 503, 504}) {
    assert(FeedFailure(status, false) == R::kTransient);
    assert(FeedFailure(status, true) == R::kTransient);
  }
  for (const auto status : {301, 400, 401, 403, 410}) {
    assert(FeedFailure(status, false) == R::kError);
  }
  // SemVer order, including numeric prerelease identifiers and metadata.
  const std::vector<std::string> versions = {
      "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta",
      "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0",
      "1.0.9", "1.0.10", "1.2.0", "1.10.0", "2.0.0"};
  for (size_t i = 0; i < versions.size(); ++i) {
    for (size_t j = 0; j < versions.size(); ++j) {
      const auto cmp = CompareVersions(versions[i], versions[j]);
      assert(i == j ? cmp == 0 : i < j ? cmp < 0 : cmp > 0);
    }
  }
  assert(CompareVersions("1.2.3+build.2", "1.2.3+build.99") == 0);
  assert(CompareVersions("1.2.3-internal.9", "1.2.3-internal.10") < 0);
  assert(CompareVersions("1.2.3-99999999999999999999", "1.2.3-100000000000000000000") < 0);
  const std::string hash(64, 'a');
  const std::string id = "com.keplr.vizor", channel = "win-arm64-mainnet";
  auto valid = [&](std::string package, std::string version, std::string type,
                   std::string file, std::string digest) {
    return ValidAsset(package, version, type, file, digest, id, channel);
  };
  const std::string file = id + "-1.2.3-" + channel + "-full.nupkg";
  assert(valid(id, "1.2.3", "Full", file, hash));
  assert(!valid("com.keplr.vizor.testnet", "1.2.3", "Full", file, hash));
  assert(!valid(id, "1.2.3", "Delta", file, hash));
  assert(!valid(id, "1.2.3", "Full", "../" + file, hash));
  assert(!valid(id, "1.2.3", "Full", id + "-1.2.3-win-x64-mainnet-full.nupkg", hash));
  assert(!valid(id, "1.2.4", "Full", file, hash));
  assert(!valid(id, "1.2.3", "Full", file, ""));
  assert(!valid(id, "1.2.3", "Full", file, std::string(64, 'g')));
  assert(!SafeVersion("../../bad"));
  assert(SafeVersion("1.2.3-internal.4"));
  assert(ValidAsset(id, "1.2.3", "Full", id + "-1.2.3-win-x64-mainnet-full.nupkg",
      hash, id, "win-x64-mainnet"));
  assert(!ValidAsset(id, "1.2.3", "Full", file, hash, id, "win-x64-mainnet"));
  std::cout << "Windows update policy: all checks passed\n";
}
