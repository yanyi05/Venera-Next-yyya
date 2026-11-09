#include "window_hotkey.h"

namespace {

bool IsValidHotkey(UINT modifiers, UINT key) {
  return modifiers != 0 && (modifiers & ~7u) == 0 &&
         (modifiers & (MOD_CONTROL | MOD_ALT)) != 0 &&
         ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'Z') ||
          (key >= VK_F1 && key <= VK_F11));
}

class SystemWindowHotkeyApi : public WindowHotkeyApi {
 public:
  DWORD Register(HWND window, int id, UINT modifiers, UINT key) override {
    if (RegisterHotKey(window, id, modifiers | MOD_NOREPEAT, key)) return 0;
    const DWORD error = GetLastError();
    return error == 0 ? ERROR_GEN_FAILURE : error;
  }

  void Unregister(HWND window, int id) override { UnregisterHotKey(window, id); }

  void Toggle(HWND window) override {
    const auto action = GetHotkeyWindowAction(
        IsWindowEnabled(window) != FALSE, IsWindowVisible(window) != FALSE,
        IsIconic(window) != FALSE);
    if (action == HotkeyWindowAction::kIgnore) return;
    if (action == HotkeyWindowAction::kHide) {
      ShowWindow(window, SW_HIDE);
      return;
    }
    ShowWindow(window, action == HotkeyWindowAction::kRestore ? SW_RESTORE
                                                            : SW_SHOW);
    SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
                 SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    // Foreground activation is subject to Windows policy, not forced by hooks.
    SetForegroundWindow(window);
  }
};

}  // namespace

HotkeyWindowAction GetHotkeyWindowAction(bool enabled, bool visible,
                                       bool minimized) {
  if (!enabled) return HotkeyWindowAction::kIgnore;
  if (minimized) return HotkeyWindowAction::kRestore;
  return visible ? HotkeyWindowAction::kHide : HotkeyWindowAction::kShow;
}

WindowHotkeyApi& GetSystemWindowHotkeyApi() {
  static SystemWindowHotkeyApi api;
  return api;
}

WindowHotkey::WindowHotkey(WindowHotkeyApi& api) : api_(api) {}
WindowHotkey::~WindowHotkey() { Shutdown(); }
void WindowHotkey::SetWindow(HWND window) { window_ = window; }

std::int64_t WindowHotkey::Open() {
  Shutdown();
  owner_ = ++next_owner_;
  suspended_ = false;
  return owner_;
}

DWORD WindowHotkey::Stage(std::int64_t owner, UINT modifiers, UINT key) {
  if (owner == 0 || owner != owner_) return ERROR_INVALID_HANDLE;
  if ((modifiers != 0 || key != 0) && !IsValidHotkey(modifiers, key)) {
    return ERROR_INVALID_PARAMETER;
  }
  Cancel(owner);
  staged_ = true;
  if (modifiers == 0 && key == 0) return 0;
  if (current_ && current_->modifiers == modifiers && current_->key == key) {
    reuse_ = true;
    return 0;
  }
  if (++next_id_ > 0xbfff) next_id_ = 0x6000;
  const DWORD error = api_.Register(window_, next_id_, modifiers, key);
  if (error != 0) {
    staged_ = false;
    return error;
  }
  pending_ = Registration{next_id_, modifiers, key};
  return 0;
}

DWORD WindowHotkey::Commit(std::int64_t owner) {
  if (owner == 0 || owner != owner_) return ERROR_INVALID_HANDLE;
  if (!staged_) return ERROR_INVALID_STATE;
  if (!reuse_) {
    if (current_) api_.Unregister(window_, current_->id);
    current_ = pending_;
  }
  pending_.reset();
  staged_ = false;
  reuse_ = false;
  return 0;
}

void WindowHotkey::Cancel(std::int64_t owner) {
  if (owner == 0 || owner != owner_) return;
  if (pending_) api_.Unregister(window_, pending_->id);
  pending_.reset();
  staged_ = false;
  reuse_ = false;
}

DWORD WindowHotkey::Suspend(std::int64_t owner, bool value) {
  if (owner == 0 || owner != owner_) return ERROR_INVALID_HANDLE;
  suspended_ = value;
  return 0;
}

void WindowHotkey::Close(std::int64_t owner) {
  if (owner != 0 && owner == owner_) Shutdown();
}

void WindowHotkey::Shutdown() {
  Cancel(owner_);
  if (current_) api_.Unregister(window_, current_->id);
  current_.reset();
  suspended_ = true;
  owner_ = 0;
}

bool WindowHotkey::HandleHotkey(WPARAM id) {
  if (!current_ || static_cast<WPARAM>(current_->id) != id || suspended_) {
    return false;
  }
  api_.Toggle(window_);
  return true;
}
