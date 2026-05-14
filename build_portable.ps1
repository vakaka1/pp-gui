# Скрипт для сборки портативной версии PP GUI для Windows
# Запускать из корня проекта

$ErrorActionPreference = "Stop"

Write-Host "--- Сборка Flutter Windows (Release) ---" -ForegroundColor Cyan
flutter build windows --release

$bundleDir = "build\windows\x64\runner\Release"
$outputZip = "pp-gui-windows-portable.zip"

if (-not (Test-Path $bundleDir)) {
    Write-Error "Директория сборки не найдена: $bundleDir"
}

Write-Host "--- Создание README.txt ---" -ForegroundColor Cyan
$readmeContent = @"
Это портативная версия PP GUI.
Для запуска просто распакуйте все файлы в любую папку и запустите pp_gui.exe.

ВАЖНО: Если программа не запускается, возможно вам нужно установить
Microsoft Visual C++ 2015-2022 Redistributable (x64).
Вы можете скачать его здесь: https://aka.ms/vs/17/release/vc_redist.x64.exe
"@
$readmeContent | Out-File -FilePath "$bundleDir\README.txt" -Encoding utf8

Write-Host "--- Упаковка в ZIP: $outputZip ---" -ForegroundColor Cyan
if (Test-Path $outputZip) { Remove-Item $outputZip }
Compress-Archive -Path "$bundleDir\*" -DestinationPath $outputZip

Write-Host "--- Готово! Портативная версия создана: $outputZip ---" -ForegroundColor Green
