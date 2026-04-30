# PP GUI

Настольный графический интерфейс для [`vakaka1/pp`](https://github.com/vakaka1/pp).
Приложение написано на Flutter и работает как оболочка для `pp-client`.

Разработано в полном соответствии с документацией [`PP`](https://github.com/vakaka1/pp/blob/main/docs/developer/README.md).

## Сборка

```bash
flutter pub get
flutter config --enable-linux-desktop
flutter build linux --release
```

Windows:

```powershell
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release
```

## Разработка

```bash
flutter analyze
flutter test
flutter run
```
