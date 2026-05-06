# PP GUI

Эталонное графическое приложение для работы и проверки протокола [`PP`](https://github.com/vakaka1/pp).
Приложение написано на Flutter и работает как оболочка для `pp-client`.

Разработано в полном соответствии с [документацией PP](https://github.com/vakaka1/pp/blob/main/docs/developer/README.md).

## Возможности

- **Подключение**: запуск и остановка `pp-client` с `--full-tunnel` через GUI
- **Проверка**: тестирование подключения через `pp-client test`
- **Конфиги**: импорт из файла, буфера обмена, ppf:// URI; редактирование формой или JSON
- **Логи**: просмотр логов в реальном времени
- **Обновления**: обновление pp-client через `pp-client update`, проверка обновлений GUI
- **CI/CD**: автоматическая сборка и релиз для Linux и Windows через GitHub Actions

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

## Релиз

Создайте аннотированный тег и запушьте — GitHub Actions соберёт бинарники и создаст релиз:

```bash
git tag -a v0.2.0 -m "Описание релиза"
git push origin v0.2.0
```
