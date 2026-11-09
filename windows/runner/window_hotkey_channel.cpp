#include "window_hotkey_channel.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <variant>

namespace {

std::optional<std::int64_t> ReadInteger(const flutter::EncodableMap& arguments,
                                      const char* key) {
  const auto found = arguments.find(flutter::EncodableValue(key));
  if (found == arguments.end()) return std::nullopt;
  if (const auto* value = std::get_if<std::int64_t>(&found->second)) return *value;
  if (const auto* value = std::get_if<std::int32_t>(&found->second)) return *value;
  return std::nullopt;
}

}  // namespace

void RegisterWindowHotkeyChannel(flutter::BinaryMessenger* messenger,
                                 WindowHotkey& hotkey) {
  flutter::MethodChannel<> channel(messenger, "venera/window_hotkey",
                                    &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [&hotkey](const flutter::MethodCall<>& call,
                std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "open") {
          result->Success(flutter::EncodableValue(hotkey.Open()));
          return;
        }
        const auto* arguments = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        const auto owner = arguments ? ReadInteger(*arguments, "owner")
                                     : std::nullopt;
        if (!arguments || !owner || *owner <= 0) {
          result->Error("invalid_hotkey", "Expected a hotkey owner");
          return;
        }
        DWORD error = 0;
        const auto& method = call.method_name();
        if (method == "stage") {
          const auto modifiers = ReadInteger(*arguments, "modifiers");
          const auto key = ReadInteger(*arguments, "keyCode");
          if (!modifiers || !key || *modifiers < 0 || *modifiers > 7 ||
              *key < 0 || *key > 0xff) {
            error = ERROR_INVALID_PARAMETER;
          } else {
            error = hotkey.Stage(*owner, static_cast<UINT>(*modifiers),
                                 static_cast<UINT>(*key));
          }
        } else if (method == "commit") {
          error = hotkey.Commit(*owner);
        } else if (method == "cancel") {
          hotkey.Cancel(*owner);
        } else if (method == "suspend") {
          const auto value = arguments->find(flutter::EncodableValue("value"));
          const auto* suspended = value != arguments->end()
              ? std::get_if<bool>(&value->second) : nullptr;
          error = suspended ? hotkey.Suspend(*owner, *suspended)
                             : ERROR_INVALID_PARAMETER;
        } else if (method == "close") {
          hotkey.Close(*owner);
        } else {
          result->NotImplemented();
          return;
        }
        if (error == 0) {
          result->Success();
        } else {
          const char* code = error == ERROR_HOTKEY_ALREADY_REGISTERED
              ? "hotkey_conflict" : error == ERROR_INVALID_PARAMETER
              ? "invalid_hotkey" : "hotkey_registration_failed";
          result->Error(code, "Windows hotkey operation failed",
                         flutter::EncodableValue(static_cast<std::int64_t>(error)));
        }
      });
}
