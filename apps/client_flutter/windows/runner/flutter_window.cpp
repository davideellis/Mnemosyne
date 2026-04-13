#include "flutter_window.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetUpWindowChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetUpWindowChannel() {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "mnemosyne/window",
      &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const auto& method = call.method_name();
        auto begin_resize = [&](LONG hit_test) {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, hit_test, 0);
          result->Success();
        };
        if (method == "minimize") {
          ShowWindow(GetHandle(), SW_MINIMIZE);
          result->Success();
          return;
        }
        if (method == "maximizeOrRestore") {
          ShowWindow(GetHandle(), IsZoomed(GetHandle()) ? SW_RESTORE : SW_MAXIMIZE);
          result->Success();
          return;
        }
        if (method == "close") {
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
          result->Success();
          return;
        }
        if (method == "isMaximized") {
          result->Success(flutter::EncodableValue(IsZoomed(GetHandle()) != FALSE));
          return;
        }
        if (method == "startDrag") {
          ReleaseCapture();
          SendMessage(GetHandle(), WM_NCLBUTTONDOWN, HTCAPTION, 0);
          result->Success();
          return;
        }
        if (method == "startResize") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (!arguments) {
            result->Error("invalid_args", "Missing resize direction.");
            return;
          }
          const auto direction_it =
              arguments->find(flutter::EncodableValue("direction"));
          if (direction_it == arguments->end()) {
            result->Error("invalid_args", "Missing resize direction.");
            return;
          }
          const auto* direction =
              std::get_if<std::string>(&direction_it->second);
          if (!direction) {
            result->Error("invalid_args", "Resize direction must be a string.");
            return;
          }

          if (*direction == "left") {
            begin_resize(HTLEFT);
            return;
          }
          if (*direction == "right") {
            begin_resize(HTRIGHT);
            return;
          }
          if (*direction == "top") {
            begin_resize(HTTOP);
            return;
          }
          if (*direction == "bottom") {
            begin_resize(HTBOTTOM);
            return;
          }
          if (*direction == "topLeft") {
            begin_resize(HTTOPLEFT);
            return;
          }
          if (*direction == "topRight") {
            begin_resize(HTTOPRIGHT);
            return;
          }
          if (*direction == "bottomLeft") {
            begin_resize(HTBOTTOMLEFT);
            return;
          }
          if (*direction == "bottomRight") {
            begin_resize(HTBOTTOMRIGHT);
            return;
          }

          result->Error("invalid_args", "Unknown resize direction.");
          return;
        }
        result->NotImplemented();
      });

  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      window_channel;
  window_channel = std::move(channel);
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  switch (message) {
    case WM_NCHITTEST:
    case WM_NCCALCSIZE:
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
