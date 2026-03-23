<#
.SYNOPSIS
    Lokaler Test für den Code-Signing-Schritt aus dem GitHub Actions Workflow.
    Erstellt ein temporäres Testzertifikat und simuliert den vollständigen Signing-Flow.
#>
[CmdletBinding()]
param(
    [string] $TimestampServer = 'http://timestamp.digicert.com/rfc3161',
    [int]    $TimeoutSeconds  = 30
)

$ErrorActionPreference = 'Stop'

Write-Host '=== Code-Signing Lokaler Test ===' -ForegroundColor Cyan
Write-Host "Timestamp-Server : $TimestampServer"
Write-Host "Signing-Timeout  : ${TimeoutSeconds}s"
Write-Host ''

# 1. Erreichbarkeit des Timestamp-Servers testen
Write-Host '--- Schritt 1: Timestamp-Server Erreichbarkeit ---' -ForegroundColor Yellow
try {
    $tcpClient = [System.Net.Sockets.TcpClient]::new()
    $uri       = [System.Uri]$TimestampServer
    $host_     = $uri.Host
    $port      = if ($uri.Port -gt 0) { $uri.Port } else { 80 }

    $connectTask = $tcpClient.ConnectAsync($host_, $port)
    if ($connectTask.Wait(5000)) {
        Write-Host "  TCP-Verbindung zu ${host_}:${port} erfolgreich." -ForegroundColor Green
    }
    else {
        Write-Warning "  TCP-Verbindung zu ${host_}:${port} TIMEOUT (5s). Server könnte nicht erreichbar sein!"
    }
    $tcpClient.Dispose()
}
catch {
    Write-Warning "  TCP-Verbindung fehlgeschlagen: $($_.Exception.Message)"
}

# Echter HTTP-Request via .NET HttpClient
Write-Host '  Sende RFC 3161 Dummy-Anfrage...' -NoNewline
try {
    $httpClient = [System.Net.Http.HttpClient]::new()
    $httpClient.Timeout = [TimeSpan]::FromSeconds(10)

    $dummyPayload = [System.Net.Http.ByteArrayContent]::new([byte[]](0x30, 0x19, 0x30, 0x17, 0x30, 0x0D))
    $dummyPayload.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('application/timestamp-query')

    $responseTask = $httpClient.PostAsync($TimestampServer, $dummyPayload)
    if ($responseTask.Wait(12000)) {
        $statusCode = [int]$responseTask.Result.StatusCode
        Write-Host " HTTP $statusCode" -ForegroundColor $(if ($statusCode -lt 500) { 'Green' } else { 'Yellow' })
        Write-Host "  Server antwortet — HTTP $statusCode ist OK (Fehler wegen Dummy-Payload ist erwartet)" -ForegroundColor Green
    }
    else {
        Write-Host ' TIMEOUT!' -ForegroundColor Red
        Write-Warning '  Der Timestamp-Server antwortet nicht innerhalb von 10s — das erklärt den Workflow-Hang!'
    }
    $httpClient.Dispose()
}
catch {
    Write-Host " Fehler: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ''

# 2. Temporäres Code-Signing-Zertifikat erstellen
Write-Host '--- Schritt 2: Temporäres Test-Zertifikat erstellen ---' -ForegroundColor Yellow
$testCert = New-SelfSignedCertificate `
    -Subject            'CN=Test Code Signing (lokal)' `
    -CertStoreLocation  'Cert:\CurrentUser\My' `
    -Type               CodeSigningCert `
    -HashAlgorithm      SHA256 `
    -KeyExportPolicy    Exportable `
    -NotAfter           (Get-Date).AddMinutes(30)

Write-Host "  Zertifikat erstellt: $($testCert.Thumbprint)" -ForegroundColor Green
Write-Host ''

# 3. Test-Datei erstellen
Write-Host '--- Schritt 3: Test-Datei + Signing ---' -ForegroundColor Yellow
$testFile = Join-Path $env:TEMP 'test-signing.ps1'
Set-Content -Path $testFile -Value "# Signing Test`nWrite-Host 'Hello'"

# 4. Signing mit Start-Job Timeout (wie im Workflow)
Write-Host "  Starte Set-AuthenticodeSignature mit Timeout ${TimeoutSeconds}s ..." -ForegroundColor Yellow
$elapsed = [System.Diagnostics.Stopwatch]::StartNew()

$signingJob = Start-Job -ScriptBlock {
    param([string]$path, [string]$thumbprint, [string]$tsUrl)
    $signingCert = Get-Item -Path "Cert:\CurrentUser\My\$thumbprint" -ErrorAction Stop
    Set-AuthenticodeSignature -FilePath $path -Certificate $signingCert `
        -TimestampServer $tsUrl -HashAlgorithm SHA256
} -ArgumentList $testFile, $testCert.Thumbprint, $TimestampServer

$completedJob = Wait-Job $signingJob -Timeout $TimeoutSeconds
$elapsed.Stop()

if (-not $completedJob) {
    Stop-Job  $signingJob
    Remove-Job $signingJob -Force
    Write-Host "  TIMEOUT nach $($elapsed.Elapsed.TotalSeconds.ToString('F1'))s!" -ForegroundColor Red
    Write-Host ''
    Write-Host '>>> DIAGNOSE: Set-AuthenticodeSignature hängt!' -ForegroundColor Red
    Write-Host "    Der Timestamp-Server '$TimestampServer' antwortet nicht rechtzeitig." -ForegroundColor Red
    Write-Host '    Im Workflow gibt es dasselbe Problem — der 120s-Timeout wird feuern.' -ForegroundColor Yellow
}
else {
    try {
        $result = Receive-Job $signingJob -ErrorAction Stop
        Remove-Job $signingJob -Force
        Write-Host "  Signing abgeschlossen in $($elapsed.Elapsed.TotalSeconds.ToString('F1'))s" -ForegroundColor Green
        Write-Host "  Signatur-Status : $($result.Status)" -ForegroundColor $(if ($result.Status -notin 'NotSigned','HashMismatch') { 'Green' } else { 'Red' })
        Write-Host "  Signer-Thumbprint: $($result.SignerCertificate.Thumbprint)" -ForegroundColor $(if ($result.SignerCertificate.Thumbprint -eq $testCert.Thumbprint) { 'Green' } else { 'Red' })
        Write-Host "  (UnknownError = self-signed, nicht vertraut — normal ohne Root-Import)" -ForegroundColor DarkGray
    }
    catch {
        Write-Host "  Job-Fehler: $($_.Exception.Message)" -ForegroundColor Red
        Remove-Job $signingJob -Force -ErrorAction SilentlyContinue
    }
}
Write-Host ''

# 5. Cleanup
Write-Host '--- Schritt 4: Cleanup ---' -ForegroundColor Yellow
Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue
$myStore = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
$myStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
$toRemove = $myStore.Certificates | Where-Object { $_.Thumbprint -eq $testCert.Thumbprint }
foreach ($c in $toRemove) { $myStore.Remove($c) }
$myStore.Close()
Write-Host '  Temporäres Zertifikat entfernt.' -ForegroundColor Green
Write-Host '=== Test abgeschlossen ===' -ForegroundColor Cyan
