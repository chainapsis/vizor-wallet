#include "password_input_source.h"

#include <flutter/standard_method_codec.h>
#include <imm.h>
#include <msctf.h>
#include <wrl/client.h>

#include <cwchar>
#include <optional>
#include <string>
#include <vector>

#include "utils.h"

namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;
using Microsoft::WRL::ComPtr;

std::string GuidString(REFGUID guid) {
  wchar_t value[40] = {};
  if (!StringFromGUID2(guid, value, 40)) return {};
  return Utf8FromUtf16(value);
}

std::string Text(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return {};
  auto value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}
std::optional<int32_t> Number(const EncodableMap& map, const char* key) {
  auto it = map.find(EncodableValue(key));
  if (it == map.end()) return std::nullopt;
  auto value = std::get_if<int32_t>(&it->second);
  return value ? std::optional<int32_t>(*value) : std::nullopt;
}

bool OwnActiveView(HWND view) {
  return IsWindow(view) && GetAncestor(view, GA_ROOT) == GetForegroundWindow() &&
         GetWindowThreadProcessId(view, nullptr) == GetCurrentThreadId();
}

// Balance COM initialization even when the runner already initialized COM.
struct ComScope {
  HRESULT result = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ~ComScope() { if (SUCCEEDED(result)) CoUninitialize(); }
};

ComPtr<ITfInputProcessorProfileMgr> ProfileManager() {
  ComPtr<ITfInputProcessorProfileMgr> manager;
  CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                   IID_PPV_ARGS(&manager));
  return manager;
}

// Resolve loaded layout identifiers without activating them. Alternate layouts
// encode a registry Layout Id in the device word (for example Dvorak). Unknown
// or ambiguous mappings are deliberately not learned.
std::string LayoutId(HKL layout) {
  const auto value = static_cast<DWORD>(reinterpret_cast<ULONG_PTR>(layout));
  const WORD language = LOWORD(value), device = HIWORD(value);
  wchar_t id[KL_NAMELENGTH] = {};
  if (device == 0 || device == language || (device & 0xf000) == 0xe000) {
    swprintf_s(id, L"%08lX", (device & 0xf000) == 0xe000 ? value : static_cast<DWORD>(language));
    return Utf8FromUtf16(id);
  }
  if ((device & 0xf000) != 0xf000) return {};
  HKEY layouts = nullptr;
  if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
      L"SYSTEM\\CurrentControlSet\\Control\\Keyboard Layouts", 0,
      KEY_READ, &layouts) != ERROR_SUCCESS) return {};
  std::string match;
  for (DWORD index = 0;; ++index) {
    DWORD length = KL_NAMELENGTH;
    if (RegEnumKeyExW(layouts, index, id, &length, nullptr, nullptr, nullptr, nullptr)
        != ERROR_SUCCESS) break;
    if (length != 8 || LOWORD(wcstoul(id, nullptr, 16)) != language) continue;
    wchar_t alternate[16] = {};
    DWORD bytes = sizeof(alternate);
    if (RegGetValueW(layouts, id, L"Layout Id", RRF_RT_REG_SZ, nullptr,
        alternate, &bytes) != ERROR_SUCCESS ||
        wcstoul(alternate, nullptr, 16) !=
            static_cast<unsigned long>(device & 0x0fff)) continue;
    if (!match.empty()) { match.clear(); break; }
    match = Utf8FromUtf16(id);
  }
  RegCloseKey(layouts);
  return match;
}

std::optional<EncodableMap> Capture(HWND view, ITfInputProcessorProfileMgr* manager) {
  if (!OwnActiveView(view) || !manager) return std::nullopt;
  TF_INPUTPROCESSORPROFILE profile = {};
  if (FAILED(manager->GetActiveProfile(GUID_TFCAT_TIP_KEYBOARD, &profile))) {
    return std::nullopt;
  }
  EncodableMap value = {
    {EncodableValue("platform"), EncodableValue("windows")},
    {EncodableValue("type"), EncodableValue(static_cast<int32_t>(profile.dwProfileType))},
    {EncodableValue("language"), EncodableValue(static_cast<int32_t>(profile.langid))},
    {EncodableValue("clsid"), EncodableValue(GuidString(profile.clsid))},
    {EncodableValue("profile"), EncodableValue(GuidString(profile.guidProfile))},
  };
  if (profile.dwProfileType == TF_PROFILETYPE_KEYBOARDLAYOUT) {
    wchar_t klid[KL_NAMELENGTH] = {};
    if (!GetKeyboardLayoutNameW(klid)) return std::nullopt;
    const std::string canonical = Utf8FromUtf16(klid);
    if (LayoutId(profile.hkl) != canonical) return std::nullopt;
    value[EncodableValue("layout")] = EncodableValue(canonical);
  } else if (profile.dwProfileType != TF_PROFILETYPE_INPUTPROCESSOR) {
    return std::nullopt;
  }
  const HIMC context = ImmGetContext(view);
  if (context) {
    DWORD conversion = 0, sentence = 0;
    const bool readable = ImmGetConversionStatus(context, &conversion, &sentence) != FALSE;
    const bool open = ImmGetOpenStatus(context) != FALSE;
    ImmReleaseContext(view, context);
    if (!readable && profile.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR) return std::nullopt;
    if (readable) {
      value[EncodableValue("open")] = EncodableValue(open ? 1 : 0);
      value[EncodableValue("conversion")] = EncodableValue(static_cast<int32_t>(conversion));
      value[EncodableValue("sentence")] = EncodableValue(static_cast<int32_t>(sentence));
    }
  } else if (profile.dwProfileType == TF_PROFILETYPE_INPUTPROCESSOR) {
    return std::nullopt;
  }
  return value;
}

bool Restore(HWND view, ITfInputProcessorProfileMgr* manager,
             const EncodableMap& target, const EncodableMap& expected) {
  auto current = Capture(view, manager);
  if (!current || *current != expected || Text(target, "platform") != "windows") return false;
  if (*current == target) return true;
  auto type = Number(target, "type"), language = Number(target, "language");
  if (!type || !language || *language < 0 || *language > 0xffff) return false;
  const auto open = Number(target, "open");
  const auto conversion = Number(target, "conversion");
  const auto sentence = Number(target, "sentence");
  if (open && (*open < 0 || *open > 1 || !conversion || !sentence)) return false;
  ComPtr<IEnumTfInputProcessorProfiles> profiles;
  if (FAILED(manager->EnumProfiles(static_cast<LANGID>(*language), &profiles))) return false;
  TF_INPUTPROCESSORPROFILE profile = {};
  ULONG count = 0;
  while (profiles->Next(1, &profile, &count) == S_OK && count == 1) {
    if (profile.dwProfileType != static_cast<DWORD>(*type) ||
        !(profile.dwFlags & TF_IPP_FLAG_ENABLED) ||
        GuidString(profile.clsid) != Text(target, "clsid") ||
        GuidString(profile.guidProfile) != Text(target, "profile")) continue;
    if (profile.dwProfileType == TF_PROFILETYPE_KEYBOARDLAYOUT) {
      if (LayoutId(profile.hkl) != Text(target, "layout")) continue;
      // Select only layouts already loaded; never install or load one.
      const int total = GetKeyboardLayoutList(0, nullptr);
      if (total <= 0) return false;
      std::vector<HKL> loaded(total);
      const int received = GetKeyboardLayoutList(total, loaded.data());
      bool found = false;
      for (int i = 0; i < received; ++i) found |= loaded[i] == profile.hkl;
      if (!found) return false;
    }
    if (!OwnActiveView(view)) return false;
    if (profile.dwProfileType == TF_PROFILETYPE_KEYBOARDLAYOUT) {
      if (!ActivateKeyboardLayout(profile.hkl, 0)) return false;
    } else {
      // Change only the calling UI thread's language. Do not set ENABLEPROFILE
      // or FORSESSION: an absent/disabled source must remain absent/disabled.
      ComPtr<ITfInputProcessorProfiles> languages;
      if (FAILED(manager->QueryInterface(IID_PPV_ARGS(&languages))) ||
          languages->ChangeCurrentLanguage(profile.langid) != S_OK) return false;
      if (manager->ActivateProfile(profile.dwProfileType, profile.langid,
          profile.clsid, profile.guidProfile, nullptr, 0) != S_OK) return false;
    }
    // Partial failure may leave the selected layout active, but never detaches
    // an IME or intercepts keys. Manual switching always remains available.
    if (open) {
      HIMC context = ImmGetContext(view);
      if (!context) return false;
      const bool mode_ok = ImmSetConversionStatus(context,
          static_cast<DWORD>(*conversion), static_cast<DWORD>(*sentence)) != FALSE;
      const bool open_ok = ImmSetOpenStatus(context, *open != 0) != FALSE;
      ImmReleaseContext(view, context);
      if (!mode_ok || !open_ok) return false;
    }
    const auto applied = Capture(view, manager);
    return applied && *applied == target;
  }
  return false;
}
}  // namespace

std::unique_ptr<flutter::MethodChannel<EncodableValue>>
CreatePasswordInputSourceChannel(flutter::BinaryMessenger* messenger, HWND view) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "com.zcash.wallet/password_input_source",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([view](const auto& call, auto result) {
    ComScope com;
    auto manager = ProfileManager();
    if (call.method_name() == "capture") {
      auto value = Capture(view, manager.Get());
      if (value) result->Success(EncodableValue(*value));
      else result->Success();
    } else if (call.method_name() == "restore") {
      const auto* args = call.arguments();
      const auto* map = args ? std::get_if<EncodableMap>(args) : nullptr;
      if (map) {
        auto t = map->find(EncodableValue("target"));
        auto e = map->find(EncodableValue("expected"));
        if (t != map->end() && e != map->end()) {
          const auto* target = std::get_if<EncodableMap>(&t->second);
          const auto* expected = std::get_if<EncodableMap>(&e->second);
          if (target && expected) Restore(view, manager.Get(), *target, *expected);
        }
      }
      result->Success();
    } else result->NotImplemented();
  });
  return channel;
}
