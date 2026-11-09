#ifndef RUNNER_WINDOW_HOTKEY_H_
#define RUNNER_WINDOW_HOTKEY_H_

#include <windows.h>

#include <cstdint>
#include <optional>

enum class HotkeyWindowAction { kIgnore, kHide, kShow, kRestore };
HotkeyWindowAction GetHotkeyWindowAction(bool enabled, bool visible,
                                       bool minimized);

class WindowHotkeyApi {
 public:
  virtual ~WindowHotkeyApi() = default;
  virtual DWORD Register(HWND window, int id, UINT modifiers, UINT key) = 0;
  virtual void Unregister(HWND window, int id) = 0;
  virtual void Toggle(HWND window) = 0;
};

WindowHotkeyApi& GetSystemWindowHotkeyApi();

class WindowHotkey {
 public:
  explicit WindowHotkey(WindowHotkeyApi& api = GetSystemWindowHotkeyApi());
  ~WindowHotkey();
  void SetWindow(HWND window);
  std::int64_t Open();
  DWORD Stage(std::int64_t owner, UINT modifiers, UINT key);
  DWORD Commit(std::int64_t owner);
  void Cancel(std::int64_t owner);
  DWORD Suspend(std::int64_t owner, bool value);
  void Close(std::int64_t owner);
  void Shutdown();
  bool HandleHotkey(WPARAM id);

 private:
  struct Registration {
    int id;
    UINT modifiers;
    UINT key;
  };
  WindowHotkeyApi& api_;
  HWND window_ = nullptr;
  std::int64_t owner_ = 0;
  std::int64_t next_owner_ = 0;
  int next_id_ = 0x6000;
  bool suspended_ = true;
  bool staged_ = false;
  bool reuse_ = false;
  std::optional<Registration> current_;
  std::optional<Registration> pending_;
};

#endif  // RUNNER_WINDOW_HOTKEY_H_
