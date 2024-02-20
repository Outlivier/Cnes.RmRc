
<#
.SYNOPSIS
	Teste les pré-requis pour ce projet. Voir la documentation en cas d'action requise.
#>
[CmdletBinding()]
param()

# Formatte l'affichage d'un check
function Write-Test
{
	[Alias('wtr')]
	param([string]$title, [string]$result)

	Write-Host "$title : " -NoNewline
	if ($result) { Write-Host "$result"  -ForegroundColor DarkCyan } else { Write-Host "[ ]" -ForegroundColor Red }
	Write-Host ('─' * 50) -ForegroundColor DarkGray
}

Write-Host ""

# PowerShell
$version = if (Get-Command pwsh -ErrorAction Ignore) { (pwsh.exe -command '$psversiontable.PSVersion.ToString()') } else { "" }
wtr 'PowerShell' $version

# Windows Terminal
wtr "Windows Terminal" ((Get-Command wt -ErrorAction Ignore).Version)

# .NET Framework
# Normalement, il est inutile de vérifier ça dans un environnement de dev, vérifier Visual Studio Suffit
wtr '.NET Framework' (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Version

# .NET SDK
# Normalement, il est inutile de vérifier ça dans un environnement de dev, vérifier Visual Studio Suffit
$dotnet = (Get-Command dotnet -ErrorAction ignore)
$sdk = if ($dotnet) { dotnet --info | Out-String } else { "" }
wtr ".NET SDK" $sdk

# NuGet : Liste des sources
$sources = if ($dotnet) { (dotnet nuget list source) 2>&1 | Out-String } else { "" }
wtr 'Sources NuGet' $sources

# Visual Studio
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere)
{
	(&$vswhere -products * -Format json | ConvertFrom-Json) | % {
		wtr "Visual Studio" "$($_.displayName) - $($_.installationVersion)"
	}
}
else
{
	wtr "Visual Studio" ""
}

# 7-Zip
$p7z = Get-ItemPropertyValue -Path "Registry::HKCU\SOFTWARE\7-Zip" -Name "Path64" -ErrorAction SilentlyContinue
$version = if ($p7z -and (Test-Path $p7z)) { (gi (Join-Path $p7z "7z.exe") -ErrorAction Ignore).VersionInfo.ProductVersion } else { "" }
wtr -title '7-Zip' $version