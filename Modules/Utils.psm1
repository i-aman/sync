<#
============================================================================

SMK Corporate Directory Sync

Utils Module

Version : 1.0.0

============================================================================
#>

Set-StrictMode -Version Latest


# Проверка существования каталога

function Initialize-Directory {

    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if(!(Test-Path $Path))
    {
        New-Item `
            -ItemType Directory `
            -Path $Path `
            -Force | Out-Null
    }

}

# SHA256

function Get-SHA256 {

    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)

    $SHA = [System.Security.Cryptography.SHA256]::Create()

    $Hash = $SHA.ComputeHash($Bytes)

    return ($Hash |
        ForEach-Object { $_.ToString("x2") }) -join ""

}

# Base64

function Convert-ToBase64 {

    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    return [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($Text)
    )

}

# GUID

function New-GuidString {

    return ([guid]::NewGuid()).ToString()

}

# Время UTC

function Get-UtcNow {

    return (Get-Date).ToUniversalTime()

}

# Формат даты CardDAV

function Get-CardDAVDate {

    return (Get-Date).ToUniversalTime().ToString(
        "yyyyMMddTHHmmssZ"
    )

}

# Очистка строки

function ConvertTo-NormalizedString {

    param(
        [string]$Text
    )

    if([string]::IsNullOrWhiteSpace($Text))
    {
        return ""
    }

    return $Text.Trim()

}

# Email 

function ConvertTo-NormalizedEmail {

    param(
        [string]$Mail
    )

    if([string]::IsNullOrWhiteSpace($Mail))
    {
        return ""
    }

    return $Mail.Trim().ToLower()

}

# Отображаемое имя контакта

function Get-ContactDisplayName {

    param(
        $Contact
    )

    $DisplayName = ConvertTo-NormalizedString $Contact.DisplayName
    $GivenName = ConvertTo-NormalizedString $Contact.GivenName
    $MiddleName = ConvertTo-NormalizedString $Contact.MiddleName
    $Surname = ConvertTo-NormalizedString $Contact.Surname

    if (-not [string]::IsNullOrWhiteSpace($Surname) -and
        -not [string]::IsNullOrWhiteSpace($GivenName)) {
        $NameParts = @($Surname, $GivenName)

        if (-not [string]::IsNullOrWhiteSpace($MiddleName)) {
            $NameParts += $MiddleName
        }

        return $NameParts -join " "
    }

    if ([string]::IsNullOrWhiteSpace($MiddleName)) {
        return $DisplayName
    }

    if (($DisplayName -split '\s+') -contains $MiddleName) {
        return $DisplayName
    }

    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        return $MiddleName
    }

    return "$DisplayName $MiddleName"

}

# Check email 

function Test-Mail {

    param(
        [string]$Mail
    )

    if([string]::IsNullOrWhiteSpace($Mail))
    {
        return $false
    }

    return ($Mail -match "^[^@]+@[^@]+\.[^@]+$")
}


# JSON

function Read-Json {

    param(
        [Parameter(Mandatory)]
        [string]$File
    )

    if(!(Test-Path $File))
    {
        return @{}
    }

    return Get-Content $File -Raw |
        ConvertFrom-Json

}

function Save-Json {

    param(

        [Parameter(Mandatory)]
        $Object,

        [Parameter(Mandatory)]
        [string]$File

    )

    $Object |
        ConvertTo-Json `
        -Depth 20 |
        Set-Content `
        $File `
        -Encoding UTF8

}

# Retry 

function Invoke-WithRetry {

    param(

        [Parameter(Mandatory)]
        [scriptblock]$Script

    )

    $Config = $Global:Config

    for($i=1;$i -le $Config.RetryCount;$i++)
    {

        try{

            return & $Script

        }

        catch{

            if($i -eq $Config.RetryCount)
            {
                throw
            }

            Start-Sleep $Config.RetryDelay

        }

    }

}

# Сравнение объектов

function Compare-Hash {

    param(

        [string]$Left,

        [string]$Right

    )

    return ($Left -eq $Right)

}

# Hash контакта

function Get-ContactHash {

    param(
        $User
    )

    $String = @()

    $String += Get-ContactDisplayName $User

    $String += $User.GivenName

    if($User.PSObject.Properties.Name -contains "MiddleName")
    {
        $String += $User.MiddleName
    }

    $String += $User.Surname

    $String += $User.Department

    $String += $User.Title

    $String += $User.Company

    $String += $User.Mail

    if($User.PSObject.Properties.Name -contains "OfficePhone")
    {
        $String += $User.OfficePhone
    }

    if($User.PSObject.Properties.Name -contains "MobilePhone")
    {
        $String += $User.MobilePhone
    }

    if($User.PSObject.Properties.Name -contains "WebPage")
    {
        $String += $User.WebPage
    }

    return Get-SHA256 (
        ($String -join "|")
    )

}

# Таймер

function Start-Timer {

    return [System.Diagnostics.Stopwatch]::StartNew()

}

function Stop-Timer {

    param($Timer)

    $Timer.Stop()

    return $Timer.Elapsed

}

# Export

Export-ModuleMember -Function Initialize-Directory

Export-ModuleMember -Function Get-SHA256

Export-ModuleMember -Function Convert-ToBase64

Export-ModuleMember -Function New-GuidString

Export-ModuleMember -Function ConvertTo-NormalizedString

Export-ModuleMember -Function ConvertTo-NormalizedEmail

Export-ModuleMember -Function Get-ContactDisplayName

Export-ModuleMember -Function Test-Mail

Export-ModuleMember -Function Read-Json

Export-ModuleMember -Function Save-Json

Export-ModuleMember -Function Invoke-WithRetry

Export-ModuleMember -Function Compare-Hash

Export-ModuleMember -Function Get-ContactHash

Export-ModuleMember -Function Get-UtcNow

Export-ModuleMember -Function Get-CardDAVDate

Export-ModuleMember -Function Start-Timer

Export-ModuleMember -Function Stop-Timer
