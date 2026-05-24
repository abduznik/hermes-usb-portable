param(
    [Parameter(Mandatory = $true)]
    [string]$Url,
    [Parameter(Mandatory = $true)]
    [string]$OutFile,
    [string]$ExtractDir = $null
)

$ErrorActionPreference = "Stop"

# ANSI color codes
$CYAN = [char]27 + '[36m';
$GREEN = [char]27 + '[32m';
$YELLOW = [char]27 + '[33m';
$RESET = [char]27 + '[0m';
$BOLD = [char]27 + '[1m';

# Ensure parent directory of OutFile exists
$outFileDir = [System.IO.Path]::GetDirectoryName($OutFile)
if (-not (Test-Path $outFileDir)) {
    New-Item -ItemType Directory -Force -Path $outFileDir | Out-Null
}

Write-Host ""
Write-Host "${CYAN}${BOLD}==> Downloading: $Url${RESET}"

# Use .NET WebRequest for maximum compatibility (works on older .NET / PowerShell)
$request = [System.Net.WebRequest]::Create($Url)
$response = $request.GetResponse()

if ([int]$response.StatusCode -ge 400) {
    throw "HTTP Error: $($response.StatusCode)"
}

$totalBytes = $response.ContentLength
$inputStream = $response.GetResponseStream()
$outputStream = [System.IO.File]::Create($OutFile)

$buffer = New-Object byte[] 65536
$downloaded = 0
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$lastReport = [System.Diagnostics.Stopwatch]::StartNew()

try {
    while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $outputStream.Write($buffer, 0, $bytesRead)
        $downloaded += $bytesRead
        
        # Throttled UI refresh to prevent terminal lag
        if ($lastReport.ElapsedMilliseconds -gt 150 -or $downloaded -eq $totalBytes) {
            $percent = 0
            if ($totalBytes -gt 0) {
                $percent = [math]::Round(($downloaded / $totalBytes) * 100)
            }
            
            $speed = ($downloaded / 1024 / 1024) / ($sw.Elapsed.TotalSeconds + 0.001)
            $speedStr = [string]::Format('{0:F2} MB/s', $speed)
            
            $dlMB = [math]::Round($downloaded / 1024 / 1024, 1)
            
            # Progress bar drawing
            $barWidth = 30
            $filledWidth = 0
            if ($percent -gt 0) {
                $filledWidth = [int]($percent * $barWidth / 100)
            }
            $emptyWidth = $barWidth - $filledWidth
            $bar = ('#' * $filledWidth) + ('-' * $emptyWidth)
            
            if ($totalBytes -gt 0) {
                $totalMB = [math]::Round($totalBytes / 1024 / 1024, 1)
                [Console]::Write("`r  ${YELLOW}[${bar}] ${percent}%${RESET} | ${GREEN}${speedStr}${RESET} | ${dlMB}/${totalMB} MB")
            } else {
                [Console]::Write("`r  ${YELLOW}[${bar}]${RESET} | ${GREEN}${speedStr}${RESET} | ${dlMB} MB")
            }
            
            $lastReport.Restart()
        }
    }
}
finally {
    $outputStream.Close()
    $inputStream.Close()
    $response.Dispose()
}

[Console]::WriteLine("`r  ${GREEN}[##############################] 100% | Download Complete!${RESET}                       ")

# Optional Extraction Flow
if ($ExtractDir) {
    Write-Host ""
    Write-Host "${CYAN}${BOLD}==> Extracting files to: $ExtractDir${RESET}"
    
    if (-not (Test-Path $ExtractDir)) {
        New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    }
    
    # Check if zip file format
    if ($OutFile.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
        [System.Reflection.Assembly]::LoadWithPartialName('System.IO.Compression.FileSystem') | Out-Null
        $zip = [System.IO.Compression.ZipFile]::OpenRead($OutFile)
        $totalEntries = $zip.Entries.Count
        $extracted = 0
        $extSw = [System.Diagnostics.Stopwatch]::StartNew()
        
        try {
            foreach ($entry in $zip.Entries) {
                $targetPath = [System.IO.Path]::Combine($ExtractDir, $entry.FullName)
                
                # Check for directory creation entry
                $targetDir = [System.IO.Path]::GetDirectoryName($targetPath)
                if (-not (Test-Path $targetDir)) {
                    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
                }
                
                # Extract file if it is not just a directory placeholder
                if (-not $entry.FullName.EndsWith('/') -and -not $entry.FullName.EndsWith('\')) {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
                }
                
                $extracted++
                
                $percent = [math]::Round(($extracted / $totalEntries) * 100)
                $barWidth = 30
                $filledWidth = [int]($percent * $barWidth / 100)
                $emptyWidth = $barWidth - $filledWidth
                $bar = ('#' * $filledWidth) + ('-' * $emptyWidth)
                
                [Console]::Write("`r  ${YELLOW}[${bar}] ${percent}%${RESET} | Extracted ${extracted}/${totalEntries} files")
            }
        }
        finally {
            $zip.Dispose()
        }
        
        [Console]::WriteLine("`r  ${GREEN}[##############################] 100% | Extraction Complete!${RESET}                       ")
        
        # Clean up zip file after successful extraction
        Remove-Item $OutFile -Force
    } else {
        Write-Host "${YELLOW}Skipping zip extraction: Not a ZIP archive format.${RESET}"
    }
}
Write-Host ""
