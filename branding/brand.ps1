$ErrorActionPreference = "Stop"

# ============================================================
# GT CONNECT - SCRIPT DE PERSONALIZAÇÃO
# Guedes Tecnologia e Sistemas
# ============================================================

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ConfigFile  = Join-Path $PSScriptRoot "config.json"
$AssetsDir   = Join-Path $PSScriptRoot "assets"

Write-Host ""
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host "       GT CONNECT - BRANDING AUTOMATICO      " -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------
# Validações iniciais
# ------------------------------------------------------------

if (-not (Test-Path $ConfigFile)) {
    throw "Arquivo não encontrado: $ConfigFile"
}

$config = Get-Content $ConfigFile -Raw | ConvertFrom-Json

$ProductName  = $config.productName
$BinaryName   = $config.binaryName
$CompanyName  = $config.companyName
$Description  = $config.description
$Copyright    = $config.copyright
$Website      = $config.website
$IdServer     = $config.idServer
$RelayServer  = $config.relayServer
$PublicKey    = $config.publicKey

if ([string]::IsNullOrWhiteSpace($ProductName)) {
    throw "productName não definido no config.json"
}

if ([string]::IsNullOrWhiteSpace($IdServer)) {
    throw "idServer não definido no config.json"
}

if ([string]::IsNullOrWhiteSpace($PublicKey)) {
    throw "publicKey não definido no config.json"
}

function Backup-File {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return
    }

    $BackupPath = "$Path.gtconnect-backup"

    if (-not (Test-Path $BackupPath)) {
        Copy-Item $Path $BackupPath -Force
        Write-Host "Backup criado: $BackupPath" -ForegroundColor DarkGray
    }
}

function Replace-Required {
    param(
        [Parameter(Mandatory = $true)]
        [string]$File,

        [Parameter(Mandatory = $true)]
        [string]$Pattern,

        [Parameter(Mandatory = $true)]
        [string]$Replacement,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path $File)) {
        throw "Arquivo não encontrado: $File"
    }

    $content = Get-Content $File -Raw

    if ($content -match $Pattern) {
        $newContent = [regex]::Replace(
            $content,
            $Pattern,
            $Replacement
        )

        Set-Content `
            -Path $File `
            -Value $newContent `
            -Encoding UTF8 `
            -NoNewline

        Write-Host "[OK] $Description" -ForegroundColor Green
        return
    }

    # Se o valor personalizado já estiver presente, não trata como erro.
    if ($content.Contains($Replacement)) {
        Write-Host "[OK] $Description já aplicado" -ForegroundColor Yellow
        return
    }

    throw "Não foi possível aplicar: $Description"
}

# ============================================================
# 1. CONFIGURAÇÕES CENTRAIS DO CLIENTE
# ============================================================

$HbbConfig = Join-Path $ProjectRoot "libs\hbb_common\src\config.rs"

Backup-File $HbbConfig

Replace-Required `
    -File $HbbConfig `
    -Pattern 'pub static ref PROD_RENDEZVOUS_SERVER:\s*RwLock<String>\s*=\s*RwLock::new\("[^"]*"\.to_owned\(\)\);' `
    -Replacement "pub static ref PROD_RENDEZVOUS_SERVER: RwLock<String> = RwLock::new(`"$IdServer`".to_owned());" `
    -Description "Servidor principal embutido"

Replace-Required `
    -File $HbbConfig `
    -Pattern 'pub static ref APP_NAME:\s*RwLock<String>\s*=\s*RwLock::new\("[^"]*"\.to_owned\(\)\);' `
    -Replacement "pub static ref APP_NAME: RwLock<String> = RwLock::new(`"$ProductName`".to_owned());" `
    -Description "Nome interno do aplicativo"

Replace-Required `
    -File $HbbConfig `
    -Pattern 'pub const RENDEZVOUS_SERVERS:\s*&\[&str\]\s*=\s*&\[[^\]]*\];' `
    -Replacement "pub const RENDEZVOUS_SERVERS: &[&str] = &[`"$IdServer`"];" `
    -Description "Lista padrão de servidores"

Replace-Required `
    -File $HbbConfig `
    -Pattern 'pub const RS_PUB_KEY:\s*&str\s*=\s*"[^"]*";' `
    -Replacement "pub const RS_PUB_KEY: &str = `"$PublicKey`";" `
    -Description "Chave pública do servidor"

# ============================================================
# 2. NOME DO EXECUTÁVEL
# ============================================================

$CMakeFile = Join-Path $ProjectRoot "CMakeLists.txt"

if (Test-Path $CMakeFile) {
    Backup-File $CMakeFile

    $cmakeContent = Get-Content $CMakeFile -Raw

    $patterns = @(
        'set\s*\(\s*BINARY_NAME\s+"?rustdesk"?\s*\)',
        'set\s*\(\s*BINARY_NAME\s+rustdesk\s*\)'
    )

    $changed = $false

    foreach ($pattern in $patterns) {
        if ($cmakeContent -match $pattern) {
            $cmakeContent = [regex]::Replace(
                $cmakeContent,
                $pattern,
                "set(BINARY_NAME `"$BinaryName`")"
            )

            $changed = $true
        }
    }

    if ($changed) {
        Set-Content `
            -Path $CMakeFile `
            -Value $cmakeContent `
            -Encoding UTF8 `
            -NoNewline

        Write-Host "[OK] Nome do executável: $BinaryName.exe" -ForegroundColor Green
    }
    else {
        Write-Host "[AVISO] BINARY_NAME não localizado em CMakeLists.txt" -ForegroundColor Yellow
    }
}

# ============================================================
# 3. METADADOS DO EXECUTÁVEL WINDOWS
# ============================================================

$RunnerRcCandidates = @(
    (Join-Path $ProjectRoot "flutter\windows\runner\Runner.rc"),
    (Join-Path $ProjectRoot "flutter\windows\runner\runner.rc")
)

$RunnerRc = $RunnerRcCandidates |
    Where-Object { Test-Path $_ } |
    Select-Object -First 1

if ($RunnerRc) {
    Backup-File $RunnerRc

    $rc = Get-Content $RunnerRc -Raw

    $replacements = @{
        'VALUE\s+"CompanyName",\s*"[^"]*\\0"' =
            "VALUE `"CompanyName`", `"$CompanyName\0`""

        'VALUE\s+"FileDescription",\s*"[^"]*\\0"' =
            "VALUE `"FileDescription`", `"$Description\0`""

        'VALUE\s+"InternalName",\s*"[^"]*\\0"' =
            "VALUE `"InternalName`", `"$BinaryName\0`""

        'VALUE\s+"OriginalFilename",\s*"[^"]*\\0"' =
            "VALUE `"OriginalFilename`", `"$BinaryName.exe\0`""

        'VALUE\s+"ProductName",\s*"[^"]*\\0"' =
            "VALUE `"ProductName`", `"$ProductName\0`""

        'VALUE\s+"LegalCopyright",\s*"[^"]*\\0"' =
            "VALUE `"LegalCopyright`", `"$Copyright\0`""
    }

    foreach ($pattern in $replacements.Keys) {
        if ($rc -match $pattern) {
            $rc = [regex]::Replace(
                $rc,
                $pattern,
                $replacements[$pattern]
            )
        }
    }

    Set-Content `
        -Path $RunnerRc `
        -Value $rc `
        -Encoding Unicode `
        -NoNewline

    Write-Host "[OK] Metadados do executável Windows" -ForegroundColor Green
}
else {
    Write-Host "[AVISO] Runner.rc não encontrado" -ForegroundColor Yellow
}

# ============================================================
# 4. ÍCONE
# ============================================================

$BrandIcon = Join-Path $AssetsDir "app_icon.ico"

$IconCandidates = @(
    (Join-Path $ProjectRoot "flutter\windows\runner\resources\app_icon.ico"),
    (Join-Path $ProjectRoot "res\icon.ico")
)

if (Test-Path $BrandIcon) {
    foreach ($IconTarget in $IconCandidates) {
        $IconFolder = Split-Path -Parent $IconTarget

        if (Test-Path $IconFolder) {
            Backup-File $IconTarget
            Copy-Item $BrandIcon $IconTarget -Force
            Write-Host "[OK] Ícone aplicado: $IconTarget" -ForegroundColor Green
        }
    }
}
else {
    Write-Host "[AVISO] Ícone não encontrado: $BrandIcon" -ForegroundColor Yellow
}

# ============================================================
# 5. SUBSTITUIÇÕES VISUAIS SEGURAS
# ============================================================

$FlutterLib = Join-Path $ProjectRoot "flutter\lib"

if (Test-Path $FlutterLib) {
    $dartFiles = Get-ChildItem `
        -Path $FlutterLib `
        -Filter "*.dart" `
        -Recurse `
        -File

    $visualChanges = 0

    foreach ($file in $dartFiles) {
        $content = Get-Content $file.FullName -Raw
        $original = $content

        # Somente textos literais claramente visíveis.
        $content = $content.Replace('"RustDesk"', "`"$ProductName`"")
        $content = $content.Replace("'RustDesk'", "'$ProductName'")

        if ($content -ne $original) {
            Backup-File $file.FullName

            Set-Content `
                -Path $file.FullName `
                -Value $content `
                -Encoding UTF8 `
                -NoNewline

            $visualChanges++
        }
    }

    Write-Host "[OK] Arquivos visuais alterados: $visualChanges" -ForegroundColor Green
}

# ============================================================
# 6. VALIDAÇÃO FINAL
# ============================================================

$validation = Get-Content $HbbConfig -Raw

$checks = @(
    @{
        Name  = "Nome do aplicativo"
        Value = $ProductName
    },
    @{
        Name  = "Servidor"
        Value = $IdServer
    },
    @{
        Name  = "Chave pública"
        Value = $PublicKey
    }
)

Write-Host ""
Write-Host "Validando personalização..." -ForegroundColor Cyan

foreach ($check in $checks) {
    if ($validation.Contains($check.Value)) {
        Write-Host "[OK] $($check.Name)" -ForegroundColor Green
    }
    else {
        throw "Falha na validação: $($check.Name)"
    }
}

Write-Host ""
Write-Host "=============================================" -ForegroundColor Green
Write-Host "   PERSONALIZACAO DO GT CONNECT CONCLUIDA    " -ForegroundColor Green
Write-Host "=============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Produto:  $ProductName"
Write-Host "Empresa:  $CompanyName"
Write-Host "Servidor: $IdServer"
Write-Host "Relay:    $RelayServer"
Write-Host "Binário:  $BinaryName.exe"
Write-Host ""
Write-Host "Agora você já pode compilar o projeto." -ForegroundColor Cyan