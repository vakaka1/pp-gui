#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cstdlib>
#include <string>
#include <utility>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  (void)prev;
  (void)command_line;

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Get the executable directory to find the "data" folder.
  wchar_t buffer[MAX_PATH];
  GetModuleFileName(nullptr, buffer, MAX_PATH);
  std::wstring executable_path(buffer);
  std::wstring executable_dir = executable_path.substr(0, executable_path.find_last_of(L"\\/"));
  std::wstring data_path = executable_dir + L"\\data";

  flutter::DartProject project(data_path);
  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(80, 80);
  Win32Window::Size size(430, 760);
  if (!window.Create(L"PP GUI", origin, size)) {
    MessageBox(nullptr, L"Failed to create window. Make sure the 'data' folder exists in the application directory.", L"PP GUI Error", MB_ICONERROR);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
