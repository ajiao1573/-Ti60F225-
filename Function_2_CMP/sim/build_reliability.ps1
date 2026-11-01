param([string]$EfinityHome = 'E:\software\Efinity', [switch]$MemoryOptimized,[switch]$RuntimeControls,[switch]$DualKey)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $runner = Join-Path $EfinityHome 'bin\efx_run.bat'
    if (-not (Test-Path -LiteralPath $runner)) { throw "Efinity runner not found: $runner" }
    $outputDir = if ($DualKey) { 'build/dualkey_bitstream' } elseif ($RuntimeControls) { 'build/runtime_bitstream' } elseif ($MemoryOptimized) { 'build/memory_bitstream' } else { 'build/reliability_bitstream' }
    $workDir = if ($DualKey) { 'build/dualkey_build' } elseif ($RuntimeControls) { 'build/runtime_build' } elseif ($MemoryOptimized) { 'build/memory_build' } else { 'build/reliability_build' }
    $releaseName = if ($DualKey) { 'bean_1080p_dualkey' } elseif ($RuntimeControls) { 'bean_1080p_runtime' } elseif ($MemoryOptimized) { 'bean_1080p_memory' } else { 'bean_1080p_reliability' }
    New-Item -ItemType Directory -Force $outputDir,$workDir | Out-Null
    python sim/prepare_bean_project.py
    if ($LASTEXITCODE -ne 0) { throw 'Project snapshot preparation failed' }
    & $runner build/bean_project/Ti60_Demo.xml --flow compile --output_dir $outputDir --work_dir $workDir *> "$workDir/flow.log"
    if ($LASTEXITCODE -ne 0) { throw "Efinity compile failed; see $workDir/flow.log" }
    python sim/verify_bean_build.py --output-dir $outputDir --work-dir $workDir --reliability
    if ($LASTEXITCODE -ne 0) { throw 'Timing, pin or input validation failed' }
    Copy-Item -LiteralPath "$outputDir/Ti60_Demo.bit" -Destination "output/$releaseName.bit" -Force
    Copy-Item -LiteralPath "$outputDir/bean_build_manifest.json" -Destination "output/$releaseName.manifest.json" -Force
    Write-Host "PASS: output/$releaseName.bit; previous releases retained."
} finally { Pop-Location }
