#ifndef RUNNER_WINDOW_HOTKEY_CHANNEL_H_
#define RUNNER_WINDOW_HOTKEY_CHANNEL_H_

#include <flutter/binary_messenger.h>

#include "window_hotkey.h"

void RegisterWindowHotkeyChannel(flutter::BinaryMessenger* messenger,
                                 WindowHotkey& hotkey);

#endif  // RUNNER_WINDOW_HOTKEY_CHANNEL_H_
