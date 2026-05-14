$ErrorActionPreference = "Stop"

Write-Host "--- Building Flutter Windows release ---" -ForegroundColor Cyan
flutter build windows --release

$bundleDir = "build\windows\x64\runner\Release"
$outputZip = "pp-gui-windows-portable.zip"

if (-not (Test-Path $bundleDir)) {
    Write-Error "Build directory was not found: $bundleDir"
}

$requiredFiles = @(
    "$bundleDir\pp_gui.exe",
    "$bundleDir\flutter_windows.dll",
    "$bundleDir\data\icudtl.dat",
    "$bundleDir\data\app.so",
    "$bundleDir\data\flutter_assets\AssetManifest.bin"
)

foreach ($requiredFile in $requiredFiles) {
    if (-not (Test-Path $requiredFile)) {
        Write-Error "Incomplete build, missing file: $requiredFile"
    }
}

Write-Host "--- Creating README.txt ---" -ForegroundColor Cyan
$readmeContent = @"
PP GUI portable build.

Extract all files into one folder and run pp_gui.exe.

If the application does not start, install Microsoft Visual C++ 2015-2022 Redistributable (x64):
https://aka.ms/vs/17/release/vc_redist.x64.exe
"@
$readmeContent | Out-File -FilePath "$bundleDir\README.txt" -Encoding utf8

Write-Host "--- Packing ZIP: $outputZip ---" -ForegroundColor Cyan
if (Test-Path $outputZip) {
    Remove-Item $outputZip -Force
}
Compress-Archive -Path "$bundleDir\*" -DestinationPath $outputZip -Force

Write-Host "--- Done: $outputZip ---" -ForegroundColor Green
