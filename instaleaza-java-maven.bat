<# : batch
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([IO.File]::ReadAllText('%~f0'))"
echo.
pause
exit /b
#>

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$MavenVersiune = '3.9.11'
$Optiune = '-Djavax.net.ssl.trustStoreType=Windows-ROOT'

function Pas($text) { Write-Host "`n=== $text" -ForegroundColor Cyan }
function Ok($text) { Write-Host "    OK  $text" -ForegroundColor Green }
function Atentie($text) { Write-Host "    !!  $text" -ForegroundColor Yellow }

function Adauga-InPath($dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $user) { $user = '' }
    $parti = @($user -split ';' | Where-Object { $_ -and ($_ -notmatch '\\(jdk|java|openjdk|apache-maven)[^\\]*\\bin$') })
    $nou = (@($dir) + $parti) -join ';'
    if ($nou -ne $user) { [Environment]::SetEnvironmentVariable('Path', $nou, 'User') }
    $env:Path = "$dir;$env:Path"
}

function Gaseste-Jdk {
    $radacini = @(
        "$env:USERPROFILE\.jdks",
        "$env:ProgramFiles\Java",
        "$env:ProgramFiles\Microsoft",
        "$env:ProgramFiles\Eclipse Adoptium",
        "$env:ProgramFiles\Zulu",
        "$env:ProgramFiles\Amazon Corretto",
        "$env:ProgramFiles\BellSoft"
    )
    Get-ChildItem -Path $radacini -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'bin\javac.exe') } |
        ForEach-Object {
            $versiune = 0
            $release = Join-Path $_.FullName 'release'
            if (Test-Path $release) {
                $m = Select-String -Path $release -Pattern 'JAVA_VERSION="(\d+)'
                if ($m) { $versiune = [int]$m.Matches[0].Groups[1].Value }
            }
            [pscustomobject]@{ Cale = $_.FullName; Versiune = $versiune }
        } |
        Where-Object { $_.Versiune -ge 21 } |
        Sort-Object @{ Expression = { $_.Versiune -eq 21 }; Descending = $true }, @{ Expression = 'Versiune'; Descending = $true } |
        Select-Object -First 1
}

try {
    Pas 'Conexiunea la Maven Central'
    $cerere = [Net.HttpWebRequest]::Create('https://repo.maven.apache.org/maven2/')
    $cerere.GetResponse().Dispose()
    $emitent = $cerere.ServicePoint.Certificate.Issuer
    Write-Host "    Certificat emis de: $emitent"
    if ($emitent -match "Let's Encrypt") {
        Ok 'certificatul e cel original'
    } else {
        Atentie 'certificatul e inlocuit de antivirus sau de proxy; Java trebuie sa foloseasca certificatele din Windows (pasul 4)'
    }

    Pas 'Java (JDK 21)'
    $jdk = Gaseste-Jdk
    if (-not $jdk) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw 'Nu am gasit JDK 21 si nici winget. Instaleaza JDK 21 din IntelliJ: File > Project Structure > SDKs > + > Download JDK, apoi ruleaza din nou.'
        }
        Write-Host '    Instalez Microsoft OpenJDK 21 (accepta fereastra de administrator daca apare)...'
        winget install --id Microsoft.OpenJDK.21 -e --silent --accept-package-agreements --accept-source-agreements
        $jdk = Gaseste-Jdk
        if (-not $jdk) { throw 'Instalarea JDK 21 nu a reusit.' }
    }
    [Environment]::SetEnvironmentVariable('JAVA_HOME', $jdk.Cale, 'User')
    $env:JAVA_HOME = $jdk.Cale
    Adauga-InPath (Join-Path $jdk.Cale 'bin')
    Ok "JAVA_HOME = $($jdk.Cale)"

    Pas "Maven $MavenVersiune"
    $mavenDir = "$env:USERPROFILE\tools\apache-maven-$MavenVersiune"
    if (-not (Test-Path "$mavenDir\bin\mvn.cmd")) {
        $zip = "$env:TEMP\apache-maven-$MavenVersiune-bin.zip"
        $url = "https://archive.apache.org/dist/maven/maven-3/$MavenVersiune/binaries/apache-maven-$MavenVersiune-bin.zip"
        Write-Host "    Descarc $url"
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\tools" | Out-Null
        Expand-Archive -Path $zip -DestinationPath "$env:USERPROFILE\tools" -Force
        Remove-Item $zip
    }
    [Environment]::SetEnvironmentVariable('MAVEN_HOME', $mavenDir, 'User')
    $env:MAVEN_HOME = $mavenDir
    Adauga-InPath "$mavenDir\bin"
    Ok "MAVEN_HOME = $mavenDir"

    Pas 'Java foloseste certificatele din Windows'
    $existent = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'User')
    if ($existent -notlike "*$Optiune*") {
        $valoare = ("$existent $Optiune").Trim()
        [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $valoare, 'User')
    }
    $env:JAVA_TOOL_OPTIONS = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'User')
    Ok "JAVA_TOOL_OPTIONS = $env:JAVA_TOOL_OPTIONS"

    Pas 'Verificare'
    & "$mavenDir\bin\mvn.cmd" -v
    if ($LASTEXITCODE -ne 0) { throw 'mvn -v a esuat.' }
    Write-Host "`n    Descarc spring-boot-starter-parent 4.2.0 de pe Maven Central..."
    & "$mavenDir\bin\mvn.cmd" -q -U dependency:get '-Dartifact=org.springframework.boot:spring-boot-starter-parent:4.2.0:pom'
    if ($LASTEXITCODE -ne 0) { throw 'Descarcarea de pe Maven Central tot nu merge. Trimite profesorului o captura cu fereastra asta.' }
    Ok 'Maven descarca de pe Maven Central'

    Write-Host ''
    Write-Host 'GATA. Mai ai doi pasi:' -ForegroundColor Green
    Write-Host '  1. Inchide COMPLET IntelliJ (File > Exit) si deschide-l din nou.'
    Write-Host '  2. In panoul Maven (dreapta) apasa "Reload All Maven Projects".'
    Write-Host '  Mesajul "Picked up JAVA_TOOL_OPTIONS" care apare la rulare e normal.'
}
catch {
    Write-Host "`nEROARE: $($_.Exception.Message)" -ForegroundColor Red
}
