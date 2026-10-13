# Builds the Windows version with the Flutter installed here (README.md, "Flutter installed") and packs it as
# build\segue-windows-x64.zip, to run on another computer without Flutter: unzipped, segue\segue.exe runs as it is.
$ErrorActionPreference = 'Stop'
$app = Split-Path $PSScriptRoot
Push-Location $app

try {
  # The build number counts the commits (tool/build-number.sh), as on Linux, Android and iOS, and the settings show it
  # beside the version. git runs that script with the sh it brings, through an alias: Windows has no sh of its own.
  $build = git -c 'alias.build-number=!sh tool/build-number.sh' build-number
  $arguments = 'build', 'windows', '--release', "--build-number=$build"

  # The keys of the services the app asks, where there is a keys.json, as tool/flutter.sh gives them (README.md,
  # "Keys").
  if (Test-Path keys.json) {
    $arguments += '--dart-define-from-file=keys.json'
  }

  flutter @arguments

  if ($LASTEXITCODE -ne 0) {
    throw "flutter build windows failed ($LASTEXITCODE)"
  }

  $package = Join-Path $app build\windows\package\segue

  if (Test-Path $package) {
    Remove-Item $package -Recurse -Force
  }

  New-Item -ItemType Directory (Split-Path $package) -Force | Out-Null
  Copy-Item build\windows\x64\runner\Release $package -Recurse

  # Visual C++'s runtime, which the app and its plugins take (msvcp140.dll, vcruntime140.dll, ...) and a Windows
  # without its redistributable lacks: Microsoft lets an app carry it in its own folder. It comes from the latest
  # Visual Studio with the C++ tools, the one Flutter builds with, and a newer runtime runs what an older one built.
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $studio = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
    -property installationPath
  $redist = Get-Content "$studio\VC\Auxiliary\Build\Microsoft.VCRedistVersion.default.txt"
  Copy-Item "$studio\VC\Redist\MSVC\$redist\x64\Microsoft.VC*.CRT\*.dll" $package

  # Windows's own tar (bsdtar), which writes a zip for a name ending in .zip, its paths with slashes: Windows
  # PowerShell's .NET writes them with backslashes, which unzip elsewhere takes as part of the names. By its path, since
  # another tar first in the PATH, as Git's, may write no zip.
  $zip = Join-Path $app build\segue-windows-x64.zip
  & "$env:SystemRoot\System32\tar.exe" -a -c -f $zip -C (Split-Path $package) segue

  if ($LASTEXITCODE -ne 0) {
    throw "tar failed ($LASTEXITCODE)"
  }

  $zip
}
finally {
  Pop-Location
}
