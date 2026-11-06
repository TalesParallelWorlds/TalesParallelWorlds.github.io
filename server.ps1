# Local web server for the site (needed for Unity WebGL). Close this window to stop.
$root = $PSScriptRoot
$port = 8080
$prefix = "http://localhost:$port/"

# Try to listen on the whole home network (phones on the same Wi-Fi).
# This needs "Run as administrator"; otherwise only this computer can open the site.
$network = $false
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$port/")
try { $listener.Start(); $network = $true }
catch {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($prefix)
    try { $listener.Start() }
    catch {
        Write-Host "Port $port is busy. Maybe the server is already running?"
        Read-Host "Press Enter to exit"
        exit
    }
}

if ($network) {
    # allow phones through Windows Firewall (once)
    if (-not (Get-NetFirewallRule -DisplayName "Parallel Worlds site" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "Parallel Worlds site" -Direction Inbound -Protocol TCP -LocalPort $port -Action Allow -Profile Any | Out-Null
    }
    $ips = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -ExpandProperty IPAddress
    Write-Host ""
    Write-Host "PHONE (same Wi-Fi): open one of these addresses in the phone browser:"
    foreach ($ip in $ips) { Write-Host ("   http://" + $ip + ":" + $port + "/") }
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Only this computer can open the site."
    Write-Host "For phones: right-click 'Zapustit sait.bat' -> Run as administrator."
    Write-Host ""
}

$startPage = "index.html"
$mime = @{
    '.html' = 'text/html; charset=utf-8'; '.htm' = 'text/html; charset=utf-8'
    '.js' = 'application/javascript'; '.css' = 'text/css'; '.wasm' = 'application/wasm'
    '.data' = 'application/octet-stream'; '.json' = 'application/json'
    '.png' = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.ico' = 'image/x-icon'
    '.svg' = 'image/svg+xml'; '.woff' = 'font/woff'; '.woff2' = 'font/woff2'; '.ttf' = 'font/ttf'
    '.mp4' = 'video/mp4'; '.webm' = 'video/webm'; '.mp3' = 'audio/mpeg'; '.ogg' = 'audio/ogg'
    '.txt' = 'text/plain; charset=utf-8'
}

Write-Host "Site is running: $prefix"
Write-Host "Close this window to stop the server."
Start-Process ($prefix + [Uri]::EscapeDataString($startPage))

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $res = $ctx.Response
    try {
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ($rel -eq '') { $rel = $startPage }
        $path = [IO.Path]::GetFullPath((Join-Path $root $rel))

        if (-not $path.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $res.StatusCode = 404
        }
        else {
            $name = $path
            if ($name.EndsWith('.br')) { $res.AddHeader('Content-Encoding', 'br'); $name = $name.Substring(0, $name.Length - 3) }
            elseif ($name.EndsWith('.gz')) { $res.AddHeader('Content-Encoding', 'gzip'); $name = $name.Substring(0, $name.Length - 3) }

            $ext = [IO.Path]::GetExtension($name).ToLower()
            if ($mime.ContainsKey($ext)) { $res.ContentType = $mime[$ext] } else { $res.ContentType = 'application/octet-stream' }
            $res.AddHeader('Cache-Control', 'no-cache')

            $bytes = [IO.File]::ReadAllBytes($path)
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
    }
    catch { }
    finally { $res.Close() }
}
