# smart_mirror_prototype

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Windows Flutter SDK

This project now supports a local Flutter SDK installation at `C:\flutter\flutter` when `FLUTTER_ROOT` is not set.
You can run the helper scripts from the `smart_mirror_prototype` folder to install packages and build the Windows app.

- PowerShell: `powershell -ExecutionPolicy Bypass -File smart_mirror_prototype\build_flutter_windows.ps1`
- CMD: `smart_mirror_prototype\build_flutter_windows.bat`

The scripts will run `flutter pub get` and then `flutter build windows` from the correct project folder.

## Windows Flutter SDK

This project now supports a local Flutter SDK installation at `C:\flutter\flutter` when `FLUTTER_ROOT` is not set. No manual PATH edits are required for the Windows build if Flutter is installed in that default location.
