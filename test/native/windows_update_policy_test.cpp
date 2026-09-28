#include "../../windows/runner/windows_update_policy.h"
#include <cassert>
#include <iostream>
int main() {
  using namespace windows_update;
  assert(Channel(0xaa64, "x64", "mainnet") == "win-arm64-mainnet");
  assert(Channel(0xaa64, "arm64", "testnet") == "win-arm64-testnet");
  assert(Channel(0x8664, "x64", "mainnet") == "win-x64-mainnet");
  assert(Channel(0, "x64", "mainnet") == "win-x64-mainnet");
  assert(Channel(0x1234, "arm64", "testnet") == "win-arm64-testnet");
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
  std::cout << "Windows update policy: 15 checks passed\n";
}
