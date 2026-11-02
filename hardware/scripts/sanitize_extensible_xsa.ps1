param(
    [string]$XsaPath = 'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/platform\fengyan_v015_extensible.xsa'
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.IO.Compression

$resolved = (Resolve-Path -LiteralPath $XsaPath).Path
$archive = [System.IO.Compression.ZipFile]::Open($resolved, [System.IO.Compression.ZipArchiveMode]::Update)
try {
    $entry = $archive.GetEntry('prj/rebuild.tcl')
    if (-not $entry) { throw 'XSA does not contain prj/rebuild.tcl' }

    $reader = [System.IO.StreamReader]::new($entry.Open(), [System.Text.Encoding]::UTF8, $true)
    try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }

    $text = $text.Replace('C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/v014_main_project_20261024/iprepo/ip_repo', '$origin_dir/../v014_main_project_20261024/iprepo/ip_repo')
    $text = $text.Replace('C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/v014_main_project_20261024/iprepo/official_ip_repo', '$origin_dir/../v014_main_project_20261024/iprepo/official_ip_repo')
    $userOld = [regex]::Matches($text, '\$origin_dir/(?:\.\./)+v014_main_project_20261024/iprepo/ip_repo').Count
    $officialOld = [regex]::Matches($text, '\$origin_dir/(?:\.\./)+v014_main_project_20261024/iprepo/official_ip_repo').Count
    if ($userOld -lt 2 -or $officialOld -lt 2) {
        throw "Unexpected IP repository references: user=$userOld official=$officialOld"
    }

    $text = [regex]::Replace($text, '\$origin_dir/(?:\.\./)+v014_main_project_20261024/iprepo/ip_repo', '$origin_dir/../iprepo/ip_repo')
    $text = [regex]::Replace($text, '\$origin_dir/(?:\.\./)+v014_main_project_20261024/iprepo/official_ip_repo', '$origin_dir/../iprepo/official_ip_repo')
    $text = [regex]::Replace($text, '(?m)^set_property -name "(?:auto_rqs\.directory|auto_incremental_checkpoint\.directory)"[^\r\n]*(?:\r?\n)?', '')

    $forbidden = @(
        'design_1_wrapper.dcp',
        'target_constrs_file',
        'target_ucf',
        'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/v014_main_project_20261024',
        'C:/Users/Admin/Desktop/大创/V0.17_完整系统集成_20261031/rebuild/v014_main_project_20261024',
        'C:/Users/Admin'
    )
    foreach ($needle in $forbidden) {
        if ($text.Contains($needle)) { throw "Forbidden non-portable reference remains: $needle" }
    }
    if (-not $text.Contains('$origin_dir/../iprepo/ip_repo') -or
        -not $text.Contains('$origin_dir/../iprepo/official_ip_repo')) {
        throw 'Portable in-XSA IP repository references were not produced'
    }

    $entry.Delete()
    $newEntry = $archive.CreateEntry('prj/rebuild.tcl', [System.IO.Compression.CompressionLevel]::Optimal)
    $writer = [System.IO.StreamWriter]::new($newEntry.Open(), [System.Text.UTF8Encoding]::new($false))
    try { $writer.Write($text) } finally { $writer.Dispose() }
} finally {
    $archive.Dispose()
}

Write-Host "SANITIZED_XSA=$resolved"

