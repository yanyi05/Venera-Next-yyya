#include "window_hotkey.h"

#include <cstdlib>
#include <iostream>
#include <map>
#include <utility>

namespace {

void Check(bool value, const char* message) {
  if (!value) {
    std::cerr << "FAILED: " << message << '\n';
    std::exit(EXIT_FAILURE);
  }
}

class FakeApi : public WindowHotkeyApi {
 public:
  std::map<int, std::pair<UINT, UINT>> registrations;
  int toggles = 0;
  bool conflict = false;

  DWORD Register(HWND, int id, UINT modifiers, UINT key) override {
    if (conflict) return ERROR_HOTKEY_ALREADY_REGISTERED;
    Check(registrations.emplace(id, std::make_pair(modifiers, key)).second,
          "registration IDs must not collide");
    return 0;
  }
  void Unregister(HWND, int id) override {
    Check(registrations.erase(id) == 1, "unregister only owned keys once");
  }
  void Toggle(HWND) override { ++toggles; }
};

void TestTransactionAndOwnership() {
  FakeApi api;
  WindowHotkey hotkey(api);
  const auto owner = hotkey.Open();
  Check(api.registrations.empty(), "opening must not register a default key");
  for (const UINT invalid : {0u, 4u, 8u, 10u}) {
    Check(hotkey.Stage(owner, invalid, 'H') == ERROR_INVALID_PARAMETER,
          "reject unmodified, Shift-only and Windows combinations");
  }
  Check(hotkey.Stage(owner, MOD_CONTROL, VK_F12) == ERROR_INVALID_PARAMETER,
        "F12 is reserved for debuggers");
  Check(hotkey.Stage(owner, MOD_CONTROL | MOD_ALT, 'H') == 0, "reserve key");
  const int first = api.registrations.begin()->first;
  Check(!hotkey.HandleHotkey(first), "a staged candidate must not act");
  Check(hotkey.Commit(owner) == 0, "commit initial registration");
  Check(hotkey.HandleHotkey(first) && api.toggles == 1, "active key acts once");
  Check(hotkey.Stage(owner, MOD_CONTROL | MOD_SHIFT, 'J') == 0, "reserve replacement");
  const int second = api.registrations.rbegin()->first;
  Check(api.registrations.size() == 2, "old key stays reserved until commit");
  Check(!hotkey.HandleHotkey(second), "candidate stays inactive during save");
  Check(hotkey.HandleHotkey(first), "previous key still works during save");
  hotkey.Cancel(owner);
  Check(api.registrations.size() == 1, "failed save releases only candidate");
  api.conflict = true;
  Check(hotkey.Stage(owner, MOD_ALT, 'J') == ERROR_HOTKEY_ALREADY_REGISTERED,
        "registration conflicts must be observable");
  Check(hotkey.HandleHotkey(first), "conflict preserves old key");
  api.conflict = false;
  Check(hotkey.Stage(owner, MOD_CONTROL | MOD_ALT, 'H') == 0, "reuse same key");
  Check(api.registrations.size() == 1, "same-key edits must not re-register");
  Check(hotkey.Commit(owner) == 0, "commit same key");
  Check(hotkey.Stage(owner, MOD_ALT | MOD_SHIFT, VK_F11) == 0, "support F11");
  const int final_id = api.registrations.rbegin()->first;
  Check(hotkey.Commit(owner) == 0, "commit replacement");
  Check(!hotkey.HandleHotkey(first) && !hotkey.HandleHotkey(second),
        "queued messages from retired and cancelled registrations must not act");
  Check(hotkey.HandleHotkey(final_id), "replacement acts");
  Check(hotkey.Suspend(owner, true) == 0, "suspend recording and exit");
  Check(!hotkey.HandleHotkey(final_id), "suspended key must not act");
  Check(hotkey.Suspend(owner, false) == 0 && hotkey.HandleHotkey(final_id),
        "cancelled recording or exit resumes key");
  const auto newer = hotkey.Open();
  Check(newer > owner && api.registrations.empty(), "new owner cleans old keys");
  Check(hotkey.Stage(newer, MOD_ALT, 'B') == 0, "new owner reserves key");
  const int newer_id = api.registrations.begin()->first;
  Check(hotkey.Commit(newer) == 0, "new owner commits");
  hotkey.Close(owner);
  hotkey.Cancel(owner);
  Check(hotkey.Suspend(owner, true) == ERROR_INVALID_HANDLE,
        "stale suspensions fail without changing live owner");
  Check(hotkey.Stage(owner, 0, 0) == ERROR_INVALID_HANDLE,
        "stale assignments fail");
  Check(hotkey.HandleHotkey(newer_id), "late old-owner cleanup cannot stop new key");
  Check(hotkey.Stage(newer, 0, 0) == 0 && hotkey.Commit(newer) == 0,
        "disable and clear unregister the active key");
  Check(api.registrations.empty() && !hotkey.HandleHotkey(newer_id),
        "disabled hotkey has no active registration");
  Check(hotkey.Stage(newer, MOD_CONTROL, 'Z') == 0, "pending reservation on exit");
  hotkey.Shutdown();
  hotkey.Shutdown();
  Check(api.registrations.empty(), "shutdown releases even an uncommitted key");
}

void TestRealRegistration() {
  const HWND window = CreateWindowExW(0, L"STATIC", L"Venera-hotkey-test", 0,
                                     0, 0, 100, 100, nullptr, nullptr,
                                     GetModuleHandleW(nullptr), nullptr);
  Check(window != nullptr && !IsWindowVisible(window), "test helper stays hidden");
  auto& api = GetSystemWindowHotkeyApi();
  constexpr int id = 0x5ffe;
  constexpr int contender_id = 0x5fff;
  UINT key = VK_F1;
  // Do not depend on the user's existing shortcuts or synthesize keyboard input.
  while (key <= VK_F11 && api.Register(window, id, 7, key) != 0) ++key;
  Check(key <= VK_F11, "one test combination must be available");
  Check(api.Register(window, contender_id, 7, key) == ERROR_HOTKEY_ALREADY_REGISTERED,
        "Win32 must reject an already-owned combination");
  api.Unregister(window, id);
  Check(api.Register(window, contender_id, 7, key) == 0,
        "Win32 combination is reusable after release");
  api.Unregister(window, contender_id);
  EnableWindow(window, FALSE);
  api.Toggle(window);
  Check(!IsWindowVisible(window), "disabled modal owner must not be shown or hidden");
  DestroyWindow(window);
}

void TestActions() {
  Check(GetHotkeyWindowAction(true, true, false) == HotkeyWindowAction::kHide,
        "visible normal/maximized/fullscreen main window hides");
  Check(GetHotkeyWindowAction(true, false, false) == HotkeyWindowAction::kShow,
        "hidden window shows without changing placement");
  Check(GetHotkeyWindowAction(true, true, true) == HotkeyWindowAction::kRestore,
        "minimized window restores instead of hiding");
  Check(GetHotkeyWindowAction(true, false, true) == HotkeyWindowAction::kRestore,
        "hidden minimized window also restores");
  Check(GetHotkeyWindowAction(false, true, false) == HotkeyWindowAction::kIgnore,
        "native modal dialogs must not be stranded");
}

}  // namespace

int main() {
  TestTransactionAndOwnership();
  TestRealRegistration();
  TestActions();
  std::cout << "Windows global hotkey regression tests passed.\n";
  return EXIT_SUCCESS;
}
