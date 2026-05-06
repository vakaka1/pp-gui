
# PP GUI

Эталонное графическое приложение для работы и проверки протокола [`PP`](https://github.com/vakaka1/pp).  
Написано на Flutter, работает на **Linux** и **Windows**. Является оболочкой над `pp-client`.

> Разработано в полном соответствии с [документацией PP](https://github.com/vakaka1/pp/blob/main/docs/developer/README.md).

---

## Установка

### Linux

Скачайте файл `pp-gui-vX.X.X-linux.bin` со [страницы релизов](https://github.com/vakaka1/pp-gui/releases/latest) и запустите:

```bash
chmod +x pp-gui-vX.X.X-linux.bin
sudo ./pp-gui-vX.X.X-linux.bin
```

Установщик скопирует приложение в `/opt/pp-gui/`, создаст команду `pp-gui` в PATH  
и добавит **ярлык в меню приложений** (GNOME, KDE, XFCE и другие).

Работает на любом дистрибутиве Linux с GTK 3.

### Windows

Скачайте `pp-gui-vX.X.X-windows-setup.exe` и запустите его.  
Установщик поместит приложение в `Program Files\PP GUI` и создаст ярлыки на рабочем столе и в меню Пуск.

---

## Обновление

Новые версии можно установить прямо из приложения:  
откройте вкладку **«О программе»** — если доступна новая версия, появится кнопка **«Обновить GUI»**.  
Приложение скачает обновление и перезапустится автоматически.

Также можно скачать архив `.tar.gz` (Linux) или `.zip` (Windows) вручную и распаковать его поверх каталога установки.

---

## Возможности

| Функция | Описание |
|---|---|
| **Подключение** | Запуск и остановка `pp-client` с `--full-tunnel` через GUI |
| **Тестирование** | Проверка подключения через `pp-client test` с отображением пинга |
| **Конфиги** | Импорт из файла, буфера обмена и `ppf://` URI; редактирование формой или JSON |
| **Логи** | Просмотр логов `pp-client` в реальном времени |
| **Системный трей** | Сворачивание в трей, работа в фоне |
| **Обновления** | Автообновление `pp-client` и GUI прямо из приложения |
| **Кросс-платформенность** | Linux (любой дистрибутив) и Windows 10/11 |

---

## Сборка из исходников

Требования: [Flutter SDK](https://flutter.dev/docs/get-started/install) ≥ 3.5.0

### Linux

```bash
flutter pub get
flutter config --enable-linux-desktop
flutter build linux --release
# Готовый бандл: build/linux/x64/release/bundle/
```

### Windows

```powershell
flutter pub get
flutter config --enable-windows-desktop
flutter build windows --release
# Готовый бандл: build\windows\x64\runner\Release\
```

### Разработка

```bash
flutter analyze
flutter test
flutter run
```

---

## Структура проекта

```
lib/
  main.dart                      # Точка входа
  src/
    models/app_models.dart        # Модели данных, версия
    services/
      github_release_service.dart # Проверка обновлений через GitHub API
      gui_updater.dart            # Самообновление GUI
      pp_client_service.dart      # Управление процессом pp-client
      profile_store.dart          # Хранение профилей
      settings_store.dart         # Настройки приложения
    ui/
      app_shell.dart              # Главный виджет, вся бизнес-логика
      home_screen.dart            # Экран подключения
      configs_screen.dart         # Управление профилями
      logs_screen.dart            # Просмотр логов
      about_screen.dart           # О программе / обновления
installer/
  linux/install.sh               # Скрипт makeself-установщика
  windows/pp-gui.iss             # Скрипт Inno Setup
.github/workflows/
  ci.yml                         # Проверка при каждом пуше
  release.yml                    # Сборка и публикация релиза по тегу
```

---

