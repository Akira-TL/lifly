$ErrorActionPreference = "Stop"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ClientDir = Join-Path $ProjectRoot "apps\client_flutter"
$OpaqueManifest = Join-Path $ProjectRoot "tools\opaque-helper\Cargo.toml"
$OpaqueOutputDir = Join-Path $ProjectRoot "build\native-opaque\windows"
$OpaqueSource = Join-Path $ProjectRoot "tools\opaque-helper\target\release\lifly_opaque_helper.dll"
$OpaqueOutput = Join-Path $OpaqueOutputDir "lifly_opaque_helper.dll"

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
  throw "Cargo is required to build the Windows native OPAQUE runtime"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw "Flutter is required to build the Windows Desktop release"
}

cargo test --manifest-path $OpaqueManifest
cargo build --release --manifest-path $OpaqueManifest
if (-not (Test-Path $OpaqueSource)) {
  throw "Windows OPAQUE DLL missing: $OpaqueSource"
}
New-Item -ItemType Directory -Force -Path $OpaqueOutputDir | Out-Null
Copy-Item -Force $OpaqueSource $OpaqueOutput

Push-Location $ClientDir
try {
  flutter clean
  flutter pub get
  flutter build windows --release
} finally {
  Pop-Location
}

$BundleCandidates = @(
  (Join-Path $ClientDir "build\windows\x64\runner\Release"),
  (Join-Path $ClientDir "build\windows\x64\runner\Release\bundle")
)
$Bundle = $BundleCandidates | Where-Object { Test-Path (Join-Path $_ "client_flutter.exe") } | Select-Object -First 1
if (-not $Bundle) {
  throw "Windows release executable was not found"
}
if (-not (Test-Path (Join-Path $Bundle "lifly_opaque_helper.dll"))) {
  throw "Windows release is not self-contained: bundled OPAQUE DLL missing"
}

Write-Output "WINDOWS_RELEASE=PASS bundle=$Bundle opaque_native=true"
