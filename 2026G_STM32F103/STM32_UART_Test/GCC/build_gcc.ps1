$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputDir = Join-Path $projectRoot 'Objects\gcc'
$toolRoot = if ($env:ARM_GCC_ROOT) {
    $env:ARM_GCC_ROOT
} else {
    'D:\Vivado_2018.3\SDK\2018.3\gnu\aarch32\nt\gcc-arm-none-eabi\bin'
}

$gcc = Join-Path $toolRoot 'arm-none-eabi-gcc.exe'
$objcopy = Join-Path $toolRoot 'arm-none-eabi-objcopy.exe'
$sizeTool = Join-Path $toolRoot 'arm-none-eabi-size.exe'
foreach ($tool in @($gcc, $objcopy, $sizeTool)) {
    if (-not (Test-Path -LiteralPath $tool)) {
        throw "ARM GCC tool not found: $tool"
    }
}

if (Test-Path -LiteralPath $outputDir) {
    $resolvedOutput = [System.IO.Path]::GetFullPath($outputDir)
    if (-not $resolvedOutput.StartsWith($projectRoot,
            [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to clean output outside project: $resolvedOutput"
    }
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $outputDir | Out-Null

$common = @(
    '-mcpu=cortex-m3', '-mthumb', '-std=gnu90', '-Os',
    '-ffunction-sections', '-fdata-sections',
    '-DSTM32F10X_MD', '-DUSE_STDPERIPH_DRIVER',
    '-IStart', '-ILibrary', '-IUser', '-ISystem', '-IHardware'
)

$sources = @()
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Start') -Filter '*.c' |
    Where-Object { $_.Name -ne 'core_cm3.c' }
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Library') -Filter '*.c'
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'System') -Filter '*.c'
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'Hardware') -Filter '*.c'
$sources += Get-ChildItem -LiteralPath (Join-Path $projectRoot 'User') -Filter '*.c'
$sources += Get-Item -LiteralPath (Join-Path $PSScriptRoot 'syscalls.c')

$objects = @()
Push-Location $projectRoot
try {
    foreach ($source in $sources) {
        $object = Join-Path $outputDir ($source.BaseName + '.o')
        & $gcc @common -c $source.FullName -o $object
        if ($LASTEXITCODE -ne 0) {
            throw "Compile failed: $($source.FullName)"
        }
        $objects += $object
    }

    $startupObject = Join-Path $outputDir 'startup_stm32f103c8.o'
    & $gcc -mcpu=cortex-m3 -mthumb -x assembler-with-cpp -c `
        (Join-Path $PSScriptRoot 'startup_stm32f103c8.s') -o $startupObject
    if ($LASTEXITCODE -ne 0) {
        throw 'Startup assembly failed'
    }
    $objects += $startupObject

    $elf = Join-Path $outputDir 'FPGA_Display.elf'
    $map = Join-Path $outputDir 'FPGA_Display.map'
    $hex = Join-Path $outputDir 'FPGA_Display.hex'
    $bin = Join-Path $outputDir 'FPGA_Display.bin'
    $linker = Join-Path $PSScriptRoot 'stm32f103c8.ld'

    & $gcc -mcpu=cortex-m3 -mthumb -nostartfiles `
        "-T$linker" '-Wl,--gc-sections' "-Wl,-Map=$map" `
        '-Wl,--build-id=none' @objects '-Wl,--start-group' '-lc' '-lm' `
        '-Wl,--end-group' -o $elf
    if ($LASTEXITCODE -ne 0) {
        throw 'Firmware link failed'
    }

    & $objcopy -O ihex $elf $hex
    if ($LASTEXITCODE -ne 0) { throw 'HEX generation failed' }
    & $objcopy -O binary $elf $bin
    if ($LASTEXITCODE -ne 0) { throw 'BIN generation failed' }
    & $sizeTool $elf

    Write-Output 'STM32_GCC_BUILD_PASS'
    Write-Output "ELF=$elf"
    Write-Output "HEX=$hex"
    Write-Output "BIN=$bin"
} finally {
    Pop-Location
}
