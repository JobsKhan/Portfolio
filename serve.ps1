# Static file server — no Node.js required.
param(
  [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path $PSScriptRoot).Path

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".htm"  = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "application/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".gif"  = "image/gif"
  ".svg"  = "image/svg+xml"
  ".ico"  = "image/x-icon"
  ".pdf"  = "application/pdf"
  ".woff" = "font/woff"
  ".woff2" = "font/woff2"
  ".txt"  = "text/plain; charset=utf-8"
}

function Get-SafeFilePath {
  param([string]$UrlPath)
  $rel = [System.Uri]::UnescapeDataString(($UrlPath -replace "^/", ""))
  if ([string]::IsNullOrWhiteSpace($rel)) { $rel = "index.html" }
  $rel = $rel -replace "/", [IO.Path]::DirectorySeparatorChar
  $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine($root, $rel))
  if (-not $candidate.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $null }
  if (Test-Path $candidate -PathType Container) {
    $idx = Join-Path $candidate "index.html"
    if (Test-Path -LiteralPath $idx -PathType Leaf) { return $idx }
  }
  return $candidate
}

$prefix = "http://localhost:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
  $listener.Start()
} catch {
  Write-Host "Could not bind to $prefix" -ForegroundColor Red
  Write-Host $_.Exception.Message
  Write-Host ""
  Write-Host "Try a different port: .\serve.ps1 -Port 9090" -ForegroundColor Yellow
  Write-Host "Or open the site without a server:" -ForegroundColor Yellow
  Write-Host "  Start-Process `"$root\index.html`"" -ForegroundColor Yellow
  exit 1
}

$url = $prefix.TrimEnd("/")
Write-Host "Serving: $root" -ForegroundColor Green
Write-Host "URL:     $url" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
try { Start-Process $url } catch { }

try {
  while ($listener.IsListening) {
    $ctx = $null
    try {
      $ctx = $listener.GetContext()
    } catch [System.Net.HttpListenerException] {
      break
    }
    if (-not $ctx) { continue }

    $req = $ctx.Request
    $res = $ctx.Response
    $path = Get-SafeFilePath $req.Url.AbsolutePath

    if (-not $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
      $res.StatusCode = 404
      $msg = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
      $res.ContentLength64 = [long]$msg.Length
      $res.OutputStream.Write($msg, 0, $msg.Length)
      $res.Close()
      continue
    }

    $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
    $type = $mime[$ext]
    if (-not $type) { $type = "application/octet-stream" }
    $res.ContentType = $type

    $bytes = [IO.File]::ReadAllBytes($path)
    $res.ContentLength64 = $bytes.LongLength
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.Close()
  }
} finally {
  if ($listener -and $listener.IsListening) {
    $listener.Stop()
  }
  if ($listener) {
    $listener.Close()
  }
}
