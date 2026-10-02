<#
============================================================================

SMK Corporate Directory Sync

Logging Module

Version : 1.0.0

Author : SMK IT Department

============================================================================
#>

Set-StrictMode -Version Latest

$script:LogFile = $null

$script:Levels = @(
    "INFO",
    "WARN",
    "ERROR",
    "DEBUG",
    "SUCCESS"
)

function Initialize-Logger {

    $Config = $Global:Config

    if (!(Test-Path $Config.LogPath)) {

        New-Item `
            -ItemType Directory `
            -Path $Config.LogPath `
            -Force | Out-Null

    }

    $Date = Get-Date -Format "yyyy-MM-dd"

    $script:LogFile = Join-Path `
        $Config.LogPath `
        "$Date.log"

    if (!(Test-Path $script:LogFile)) {

        New-Item `
            -ItemType File `
            -Path $script:LogFile `
            -Force | Out-Null

    }

    Remove-OldLogs

}

function Write-Log {

    param(

        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR","DEBUG","SUCCESS")]
        [string]$Level = "INFO"

    )

    if([string]::IsNullOrWhiteSpace($Message))
    {
        return
    }

    $Time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $Line = "[{0}] [{1}] {2}" -f `
        $Time,
        $Level,
        $Message

    Add-Content `
        -Path $script:LogFile `
        -Value $Line

    switch($Level){

        "INFO" {

            Write-Host $Line -ForegroundColor White

        }

        "WARN" {

            Write-Host $Line -ForegroundColor Yellow

        }

        "ERROR" {

            Write-Host $Line -ForegroundColor Red

        }

        "DEBUG" {

            Write-Host $Line -ForegroundColor Cyan

        }

        "SUCCESS" {

            Write-Host $Line -ForegroundColor Green

        }

    }

}

function Write-Banner {

    param(
        [string]$Title
    )

    Write-Host ""

    Write-Host "==================================================" `
        -ForegroundColor Cyan

    Write-Host " $Title" `
        -ForegroundColor Green

    Write-Host "==================================================" `
        -ForegroundColor Cyan

    Write-Host ""

}

function Write-Separator {

    Write-Host ""

    Write-Host ("-" * 70) `
        -ForegroundColor DarkGray

    Write-Host ""

}

function Start-Section {

    param(
        [string]$Name
    )

    Write-Separator

    Write-Log "START : $Name"

}

function End-Section {

    param(
        [string]$Name
    )

    Write-Log "END   : $Name" "SUCCESS"

}

function Remove-OldLogs {

    $Config = $Global:Config

    if (!(Test-Path $Config.LogPath)) {

        return

    }

    Get-ChildItem `
        $Config.LogPath `
        -Filter *.log |

    Where-Object {

        $_.CreationTime `
            -lt (Get-Date).AddDays(
                -$Config.LogRetentionDays
            )

    } |

    Remove-Item `
        -Force `
        -ErrorAction SilentlyContinue

}

function Start-TranscriptSafe {

    try{

        Start-Transcript `
            -Path (
                Join-Path `
                $Global:Config.LogPath `
                ("Transcript_{0}.txt" -f (
                    Get-Date -Format "yyyyMMdd_HHmmss"
                ))
            ) `
            -ErrorAction Stop

    }

    catch{

    }

}

function Stop-TranscriptSafe {

    try{

        Stop-Transcript | Out-Null

    }

    catch{

    }

}

function Write-Exception {

    param(

        [System.Exception]$Exception

    )

    Write-Log "Exception:" "ERROR"

    Write-Log $Exception.Message "ERROR"

    if($Exception.InnerException){

        Write-Log `
            $Exception.InnerException.Message `
            "ERROR"

    }

}

function Write-Statistics {

    param(

        [pscustomobject]$Statistics

    )

    Write-Separator

    Write-Host "Synchronization statistics" `
        -ForegroundColor Green

    Write-Separator

    Write-Log "Created : $($Statistics.Created)"

    Write-Log "Updated : $($Statistics.Updated)"

    Write-Log "Deleted : $($Statistics.Deleted)"

    Write-Log "Skipped : $($Statistics.Skipped)"

    Write-Log "Errors  : $($Statistics.Errors)"

}

Export-ModuleMember `
    -Function Initialize-Logger

Export-ModuleMember `
    -Function Write-Log

Export-ModuleMember `
    -Function Write-Banner

Export-ModuleMember `
    -Function Write-Separator

Export-ModuleMember `
    -Function Start-Section

Export-ModuleMember `
    -Function End-Section

Export-ModuleMember `
    -Function Write-Statistics

Export-ModuleMember `
    -Function Write-Exception

Export-ModuleMember `
    -Function Start-TranscriptSafe

Export-ModuleMember `
    -Function Stop-TranscriptSafe