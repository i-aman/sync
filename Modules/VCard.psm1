<#
============================================================================

SMK Corporate Directory Sync

VCard Module

RFC6350

Version : 1.0.0

============================================================================
#>

Set-StrictMode -Version Latest

function Test-VCardNeedsEncoding {

    param([string]$Text)

    if([string]::IsNullOrEmpty($Text))
    {
        return $false
    }

    foreach($Character in $Text.ToCharArray())
    {
        if([int][char]$Character -gt 127)
        {
            return $true
        }
    }

    return $false

}

function Convert-ToQuotedPrintableUtf8 {

    param([string]$Text)

    if([string]::IsNullOrEmpty($Text))
    {
        return ""
    }

    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)

    return (($Bytes | ForEach-Object { "={0:X2}" -f $_ }) -join "")

}

function New-VCardTextLine {

    param(

        [string]$Name,

        [string]$Value

    )

    if([string]::IsNullOrWhiteSpace($Value))
    {
        return $null
    }

    if(Test-VCardNeedsEncoding $Value)
    {
        return ("{0}:{1}" -f $Name, $Value)
    }

    return ("{0}:{1}" -f $Name, $Value)

}

# Экранирование специальных символов

function Escape-VCardText {

    param([string]$Text)

    if([string]::IsNullOrWhiteSpace($Text))
    {
        return ""
    }

    $Text = $Text.Replace("\","\\")
    $Text = $Text.Replace(";","\;")
    $Text = $Text.Replace(",","\,")
    $Text = $Text.Replace("`r","")
    $Text = $Text.Replace("`n","\n")

    return $Text.Trim()

}

# 

function Get-VCardName {

    param($User)

    return "{0};{1};;;" -f `
        (Escape-VCardText $User.Surname),
        (Escape-VCardText $User.GivenName)

}

# 

function Get-VCardFormattedName {

    param($User)

    return Escape-VCardText $User.DisplayName

}

# EMAIL

function Get-VCardEmail {

    param($User)

    if([string]::IsNullOrWhiteSpace($User.Mail))
    {
        return $null
    }

    return $User.Mail.ToLower()

}

# ORGANIZATION

function Get-VCardOrganization {

    param($User)

    return Escape-VCardText $User.Company

}

# TITLE 

function Get-VCardTitle {

    param($User)

    return Escape-VCardText $User.Title

}

# DEPARTAMENT

function Get-VCardDepartment {

    param($User)

    return Escape-VCardText $User.Department

}

function Get-VCardOfficePhone {

    param($User)

    return Escape-VCardText $User.OfficePhone

}

function Get-VCardMobilePhone {

    param($User)

    return Escape-VCardText $User.MobilePhone

}

function Get-VCardWebPage {

    param($User)

    return Escape-VCardText $User.WebPage

}

# Создание UID

function Get-VCardUID {

    param($User)

    if ($User.PSObject.Properties.Name -contains "Guid") {

        $Guid = [string]$User.Guid

        if (-not [string]::IsNullOrWhiteSpace($Guid)) {
            return $Guid.Trim().ToLower()
        }

    }

    if (-not [string]::IsNullOrWhiteSpace($User.Mail)) {
        return $User.Mail.ToLower()
    }

    return ([guid]::NewGuid()).ToString().ToLower()

}

# Время изменения

function Get-VCardRevision {

    return (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")

}

# Построение vCard

function New-VCard {

    param($User)

    $Card = @()

    $Card += "BEGIN:VCARD"
    $Card += "VERSION:3.0"

    $Card += "UID:$((Get-VCardUID $User))"

    $FormattedName = Get-VCardFormattedName $User

    $Line = New-VCardTextLine -Name "FN" -Value $FormattedName

    if($Line)
    {
        $Card += $Line
    }

    $Line = New-VCardTextLine -Name "N" -Value (Get-VCardName $User)

    if($Line)
    {
        $Card += $Line
    }

    if($User.Company)
    {
        if($User.Department)
        {
            $Line = New-VCardTextLine -Name "ORG" -Value "$((Get-VCardOrganization $User));$((Get-VCardDepartment $User))"
        }
        else
        {
            $Line = New-VCardTextLine -Name "ORG" -Value (Get-VCardOrganization $User)
        }

        if($Line)
        {
            $Card += $Line
        }
    }

    if($User.Title)
    {
        $Line = New-VCardTextLine -Name "TITLE" -Value (Get-VCardTitle $User)

        if($Line)
        {
            $Card += $Line
        }
    }

    if($User.Mail)
    {
        $Card += "EMAIL;TYPE=INTERNET:$((Get-VCardEmail $User))"
    }

    if($User.OfficePhone)
    {
        $Card += "TEL;TYPE=WORK,VOICE:$((Get-VCardOfficePhone $User))"
    }

    if($User.MobilePhone)
    {
        $Card += "TEL;TYPE=CELL:$((Get-VCardMobilePhone $User))"
    }

    if($User.WebPage)
    {
        $Card += "URL:$((Get-VCardWebPage $User))"
    }

    $Card += "REV:$(Get-VCardRevision)"

    $Card += "END:VCARD"

    return ($Card -join "`r`n")

}

# Сохранение vCard

function Save-VCard {

    param(

        $User,

        [string]$Folder

    )

    if(!(Test-Path $Folder))
    {
        New-Item -ItemType Directory -Path $Folder | Out-Null
    }

    $Name = $User.Mail.Replace("@","_")

    $Path = Join-Path $Folder "$Name.vcf"

    New-VCard $User |

        Set-Content `
            -Encoding UTF8 `
            -Path $Path

}

# Проверка vCard

function Test-VCard {

    param($User)

    $Card = New-VCard $User

    if($Card -notmatch "BEGIN:VCARD")
    {
        return $false
    }

    if($Card -notmatch "END:VCARD")
    {
        return $false
    }

    return $true

}

# export

Export-ModuleMember -Function New-VCard

Export-ModuleMember -Function Save-VCard

Export-ModuleMember -Function Test-VCard