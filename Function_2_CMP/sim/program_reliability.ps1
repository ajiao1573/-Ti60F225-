param([string]$EfinityHome = 'E:\software\Efinity',
    [ValidateSet('bean_1080p_reliability','bean_1080p_memory','bean_1080p_runtime','bean_1080p_dualkey')]
    [string]$ReleaseName = 'bean_1080p_reliability')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
Push-Location $projectRoot
try {
    $bit = "output/$ReleaseName.bit"
    $manifest = Get-Content "output/$ReleaseName.manifest.json" -Raw | ConvertFrom-Json
    $hash = (Get-FileHash -LiteralPath $bit -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $manifest.bitstream_sha256) { throw 'Release bitstream hash mismatch' }
    foreach ($entry in $manifest.source_sha256.PSObject.Properties) {
        if ((Get-FileHash -LiteralPath $entry.Name -Algorithm SHA256).Hash.ToLower() -ne $entry.Value) {
            throw "Design input changed since release: $($entry.Name)"
        }
    }
    New-Item -ItemType Directory -Force build/reliability | Out-Null
    $log = if ($ReleaseName -eq 'bean_1080p_dualkey') { 'build/two_key/jtag_program.log' } elseif ($ReleaseName -eq 'bean_1080p_runtime') { 'build/runtime/jtag_program.log' } elseif ($ReleaseName -eq 'bean_1080p_memory') { 'build/memory/jtag_program.log' } else { 'build/reliability/jtag_program.log' }
    $programmer = Join-Path $EfinityHome 'pgm/bin/ftdi_pgm.bat'
    # Explicit primary and alternate URLs avoid a current vendor CLI enum /
    # single-channel URL indexing bug. Both refer to the detected FT232H.
    & $programmer -m jtag -b 'Generic Board Profile Using FT232H' -u 'ftdi://0x0403:0x6014:0:ff/1' -a 'ftdi://0x0403:0x6014:0:ff/1' --jtag_clock_freq 6000000 $bit *> $log
    $result = Get-Content -LiteralPath $log -Raw
    if ($LASTEXITCODE -ne 0 -or $result -match 'Traceback|ERROR:|aborting' -or
        $result -notmatch 'Device ID read from JTAG: 0x10660A79' -or
        $result -notmatch 'finished with JTAG programming') {
        throw "JTAG programming did not confirm success; see $log"
    }
    $record = [ordered]@{
        date = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow,
            [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyy-MM-dd')
        timezone = 'Asia/Shanghai'
        bitstream = "$ReleaseName.bit"; sha256 = $hash
        device = 'Ti60'; jtag_idcode = '0x10660A79'
        programming_mode = 'JTAG volatile; boot Flash unchanged'
        programming_log = $log; programmed_successfully = $true
        configured_resolution = @(1920,1080)
        user_confirmation = $null
        physical_noise_reduction_confirmed = $null
        known_count_accuracy_measured = $false
        physical_freeze_resume_confirmed = $null
        status = 'Programmed; awaiting physical display, noise, known-count and freeze/resume observations'
    }
    $record | ConvertTo-Json -Depth 5 | Set-Content "output/$ReleaseName.hardware_validation.json" -Encoding utf8
    Write-Host "PASS volatile JTAG load: Ti60 0x10660A79; SHA256 $hash"
} finally { Pop-Location }
