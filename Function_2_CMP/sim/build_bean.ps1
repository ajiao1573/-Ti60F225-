param([string]$EfinityHome = 'E:\software\Efinity')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $runner = Join-Path $EfinityHome 'bin\efx_run.bat'
    if (-not (Test-Path -LiteralPath $runner)) { throw "Efinity runner not found: $runner" }
    New-Item -ItemType Directory -Force build\bean_bitstream,build\bean_build,build\bean_project | Out-Null
    # A private snapshot prevents an open Efinity GUI replacing the source list.
    python sim/prepare_bean_project.py
    if ($LASTEXITCODE -ne 0) { throw 'Project snapshot preparation failed' }
    & $runner build/bean_project/Ti60_Demo.xml --flow compile --output_dir build/bean_bitstream --work_dir build/bean_build *> build/bean_build/flow.log
    if ($LASTEXITCODE -ne 0) { throw 'Efinity compile failed; see build/bean_build/flow.log' }
    python sim/verify_bean_build.py
    if ($LASTEXITCODE -ne 0) { throw 'Final timing/pin/bitstream validation failed' }
    New-Item -ItemType Directory -Force output | Out-Null
    Copy-Item -LiteralPath build/bean_bitstream/Ti60_Demo.bit -Destination output/bean_1080p_contour.bit -Force
    Copy-Item -LiteralPath build/bean_bitstream/bean_build_manifest.json -Destination output/bean_1080p_contour.manifest.json -Force
    Copy-Item -LiteralPath build/bean_bitstream/Ti60_Demo.bit -Destination output/bean_1080p_denoise.bit -Force
    Copy-Item -LiteralPath build/bean_bitstream/bean_build_manifest.json -Destination output/bean_1080p_denoise.manifest.json -Force
    python sim/prepare_bean_project.py --sync-source-list-only
    if ($LASTEXITCODE -ne 0) { throw 'Canonical project source-list update failed' }
    Write-Host 'Compile passed. Review build/bean_bitstream/Ti60_Demo.timing.rpt before programming.'
    Write-Host 'Bitstream: build/bean_bitstream/Ti60_Demo.bit'
    Write-Host 'Download this native 1080p + 5x5 RGB median + edge smoothing + contour build: output/bean_1080p_denoise.bit'
} finally {
    Pop-Location
}
