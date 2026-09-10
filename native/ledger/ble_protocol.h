#ifndef VIZOR_LEDGER_BLE_PROTOCOL_H_
#define VIZOR_LEDGER_BLE_PROTOCOL_H_

#include <algorithm>
#include <array>
#include <cstdint>
#include <stdexcept>
#include <string>
#include <vector>

namespace ledger_ble {

using Bytes = std::vector<uint8_t>;

struct Error : std::runtime_error {
  Error(std::string error_code, const std::string& message)
      : std::runtime_error(message), code(std::move(error_code)) {}
  std::string code;
};

struct ServiceSpec {
  const wchar_t* service;
  const wchar_t* notify;
  const wchar_t* write;
  const char* model;
};

// Ledger's device profiles and BLE APDU framing are defined in ledgerjs:
// https://github.com/LedgerHQ/ledger-live/tree/develop/libs/ledgerjs/packages/devices
// https://github.com/LedgerHQ/ledgerjs/tree/master/packages/devices/src/ble
inline constexpr std::array<ServiceSpec, 4> kServices = {{
    {L"13d63400-2c97-0004-0000-4c6564676572",
     L"13d63400-2c97-0004-0001-4c6564676572",
     L"13d63400-2c97-0004-0002-4c6564676572", "Ledger Nano X"},
    {L"13d63400-2c97-6004-0000-4c6564676572",
     L"13d63400-2c97-6004-0001-4c6564676572",
     L"13d63400-2c97-6004-0002-4c6564676572", "Ledger Stax"},
    {L"13d63400-2c97-3004-0000-4c6564676572",
     L"13d63400-2c97-3004-0001-4c6564676572",
     L"13d63400-2c97-3004-0002-4c6564676572", "Ledger Flex"},
    {L"13d63400-2c97-8004-0000-4c6564676572",
     L"13d63400-2c97-8004-0001-4c6564676572",
     L"13d63400-2c97-8004-0002-4c6564676572", "Ledger Nano Gen5"},
}};

inline uint16_t ReadU16(const Bytes& bytes, size_t offset) {
  if (offset + 2 > bytes.size()) {
    throw Error("unavailable", "Ledger returned a truncated response.");
  }
  return static_cast<uint16_t>((bytes[offset] << 8) | bytes[offset + 1]);
}

inline std::vector<Bytes> FrameApdu(const Bytes& apdu, size_t mtu) {
  if (apdu.empty() || apdu.size() > 65535 || mtu < 6 || mtu > 512) {
    throw Error("unavailable", "Ledger APDU or Bluetooth packet size is invalid.");
  }
  std::vector<Bytes> frames;
  size_t offset = 0;
  uint16_t sequence = 0;
  while (offset < apdu.size()) {
    Bytes frame = {0x05, static_cast<uint8_t>(sequence >> 8),
                   static_cast<uint8_t>(sequence)};
    if (sequence == 0) {
      frame.push_back(static_cast<uint8_t>(apdu.size() >> 8));
      frame.push_back(static_cast<uint8_t>(apdu.size()));
    }
    const auto length = std::min(mtu - frame.size(), apdu.size() - offset);
    frame.insert(frame.end(), apdu.begin() + offset,
                 apdu.begin() + offset + length);
    frames.push_back(std::move(frame));
    offset += length;
    ++sequence;
  }
  return frames;
}

class ResponseAssembler {
 public:
  bool Add(const Bytes& frame) {
    if (complete_ || frame.size() < 3 || frame[0] != 0x05 ||
        ReadU16(frame, 1) != sequence_) {
      throw Error("unavailable", "Ledger Bluetooth response sequence is invalid.");
    }
    const size_t header = sequence_ == 0 ? 5 : 3;
    if (frame.size() <= header) {
      throw Error("unavailable", "Ledger returned an empty Bluetooth fragment.");
    }
    if (sequence_ == 0) {
      expected_ = ReadU16(frame, 3);
      if (expected_ < 2) {
        throw Error("unavailable", "Ledger response is missing its status.");
      }
      bytes_.reserve(expected_);
    }
    if (frame.size() - header > expected_ - bytes_.size()) {
      throw Error("unavailable", "Ledger Bluetooth response exceeds its length.");
    }
    bytes_.insert(bytes_.end(), frame.begin() + header, frame.end());
    ++sequence_;
    complete_ = bytes_.size() == expected_;
    return complete_;
  }

  const Bytes& bytes() const { return bytes_; }

 private:
  Bytes bytes_;
  size_t expected_ = 0;
  uint16_t sequence_ = 0;
  bool complete_ = false;
};

inline size_t NegotiatedMtu(const Bytes& response, uint16_t max_pdu_size) {
  if (response.size() < 6 || response[0] != 0x08 || response[5] < 20 ||
      max_pdu_size < 23) {
    throw Error("unavailable", "Ledger Bluetooth packet negotiation failed.");
  }
  return std::min(static_cast<size_t>(response[5]),
                  static_cast<size_t>(max_pdu_size - 3));
}

inline bool HasSuccessStatus(const Bytes& response) {
  return response.size() >= 2 && ReadU16(response, response.size() - 2) == 0x9000;
}

inline void RequireSuccess(const Bytes& response) {
  const auto status = ReadU16(response, response.size() < 2 ? 0 : response.size() - 2);
  if (status == 0x9000) return;
  if (status == 0x5515) {
    throw Error("locked", "Unlock your Ledger and reopen the Zcash app.");
  }
  if (status == 0x6985 || status == 0x5501) {
    throw Error("rejected", "The Ledger request was rejected on the device.");
  }
  if (status == 0x6601 || status == 0x6901) {
    throw Error("device_busy", "Finish or reject the pending request on your Ledger.");
  }
  throw Error("unavailable", "Ledger could not complete the device request.");
}

struct AppInfo {
  std::string name;
  std::string version;
};

inline AppInfo DecodeAppInfo(const Bytes& response) {
  RequireSuccess(response);
  if (response.size() < 5 || response[0] != 1) {
    throw Error("unavailable", "Ledger returned invalid app information.");
  }
  size_t offset = 1;
  const auto read_string = [&]() {
    if (offset >= response.size() - 2) {
      throw Error("unavailable", "Ledger returned truncated app information.");
    }
    const auto length = response[offset++];
    if (length == 0 || offset + length > response.size() - 2) {
      throw Error("unavailable", "Ledger returned invalid app information.");
    }
    std::string value(response.begin() + offset, response.begin() + offset + length);
    offset += length;
    return value;
  };
  auto name = read_string();
  return {std::move(name), read_string()};
}

}  // namespace ledger_ble

#endif  // VIZOR_LEDGER_BLE_PROTOCOL_H_
