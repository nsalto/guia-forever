@echo off
rem Guia Forever updater for Windows: double click to install or update the addon from GitHub.
rem Downloads the main branch, copies the addon files into World of Warcraft\_forever_\Interface\AddOns\GuiaForever.
title Actualizar Guia Forever
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference='Stop';" ^
  "$cfgDir = Join-Path $env:APPDATA 'GuiaForever'; $cfg = Join-Path $cfgDir 'addons-path.txt';" ^
  "$addons = $null; if (Test-Path $cfg) { $addons = (Get-Content $cfg -Raw).Trim() }" ^
  "if (-not $addons -or -not (Test-Path $addons)) {" ^
  "  $guess = @('C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns','C:\Program Files\World of Warcraft\_forever_\Interface\AddOns','D:\World of Warcraft\_forever_\Interface\AddOns','D:\Games\World of Warcraft\_forever_\Interface\AddOns','C:\Games\World of Warcraft\_forever_\Interface\AddOns');" ^
  "  $addons = $guess | Where-Object { Test-Path $_ } | Select-Object -First 1 }" ^
  "if (-not $addons) {" ^
  "  Add-Type -AssemblyName System.Windows.Forms; $d = New-Object System.Windows.Forms.FolderBrowserDialog;" ^
  "  $d.Description = 'Elegi la carpeta World of Warcraft\_forever_\Interface\AddOns';" ^
  "  if ($d.ShowDialog() -ne 'OK') { Write-Host 'Cancelado.'; exit 1 }; $addons = $d.SelectedPath }" ^
  "New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null; Set-Content -Path $cfg -Value $addons;" ^
  "Write-Host ('Carpeta de addons: ' + $addons);" ^
  "$tmp = Join-Path $env:TEMP ('guia-' + [guid]::NewGuid()); New-Item -ItemType Directory -Path $tmp | Out-Null;" ^
  "$zip = Join-Path $tmp 'guia.zip';" ^
  "Write-Host 'Bajando la ultima version...';" ^
  "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
  "Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/nsalto/guia-forever/archive/refs/heads/main.zip' -OutFile $zip;" ^
  "Expand-Archive -Path $zip -DestinationPath $tmp -Force;" ^
  "$src = Join-Path $tmp 'guia-forever-main'; $dst = Join-Path $addons 'GuiaForever';" ^
  "foreach ($x in @('tools','docs','updater','.gitignore','README.md','THIRD_PARTY_LICENSES.md')) { Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $src $x) }" ^
  "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $dst, (Join-Path $addons 'GuiaForever_Data');" ^
  "Move-Item -Path $src -Destination $dst;" ^
  "Remove-Item -Recurse -Force $tmp;" ^
  "$v = (Select-String -Path (Join-Path $dst 'GuiaForever.toc') -Pattern '^## Version: (.*)').Matches[0].Groups[1].Value;" ^
  "Write-Host ''; Write-Host ('Listo: Guia Forever ' + $v + ' instalada. Si el juego esta abierto, cerralo y abrilo de nuevo.')"
echo.
pause
