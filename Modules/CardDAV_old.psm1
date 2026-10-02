<#
============================================================================

SMK Corporate Directory Sync

CardDAV Module

Version : 1.0.0

Author  : SMK IT Department

Purpose :

Work with Nextcloud CardDAV

============================================================================
#>

Set-StrictMode -Version Latest

$Script:Config = $null

$Script:Credential = $null

$Script:Headers = $null

$Script:BaseUri = $null

$Script:AddressBookUri = $null

# Инициализация

function Initialize-CardDAV {

    Write-Log "Initializing CardDAV module..."

    $Script:Config = $Global:Config

    if($null -eq $Script:Config)
    {
        throw "Configuration not loaded."
    }

    $SecurePassword = ConvertTo-SecureString `
        $Script:Config.Password `
        -AsPlainText `
        -Force

    $Script:Credential = New-Object `
        System.Management.Automation.PSCredential `
        (
            $Script:Config.Username,
            $SecurePassword
        )

    $Bytes = [System.Text.Encoding]::ASCII.GetBytes(
        "$($Script:Config.Username):$($Script:Config.Password)"
    )

    $Token = [Convert]::ToBase64String($Bytes)

    $Script:Headers = @{

        Authorization = "Basic $Token"

    }

    $Script:BaseUri = $Script:Config.Server.TrimEnd('/')

    $Script:AddressBookUri =
        "$($Script:BaseUri)/remote.php/dav/addressbooks/users/$($Script:Config.UserId)/$($Script:Config.AddressBook)/"

    Write-Log "CardDAV initialized." "SUCCESS"

}

# Проверка подключения

function Test-CardDAV {

    Write-Log "Testing CardDAV connection..."

    try {

        Invoke-WebRequest `
            -Uri $Script:AddressBookUri `
            -Headers $Script:Headers `
            -Method GET `
            -UseBasicParsing `
            -TimeoutSec 30 `
            | Out-Null

        Write-Log "Connection successful." "SUCCESS"

        return $true

    }

    catch {

        Write-Exception $_.Exception

        return $false

    }

}

# Универсальный запрос

function Invoke-CardDAV {

    param(

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Method,

        [string]$ContentType,

        $Body,

        $Headers

    )

    try {

        $RequestHeaders = @{}

        foreach($Key in $Script:Headers.Keys)
        {
            $RequestHeaders[$Key] = $Script:Headers[$Key]
        }

        if($Headers)
        {
            foreach($Key in $Headers.Keys)
            {
                $RequestHeaders[$Key] = $Headers[$Key]
            }
        }

        $Params = @{

            Uri = $Uri

            Method = $Method

            Headers = $RequestHeaders

            UseBasicParsing = $true

            TimeoutSec = 60

            ErrorAction = "Stop"

        }

        if($ContentType)
        {
            $Params.ContentType = $ContentType
        }

        if($null -ne $Body)
        {
            $Params.Body = $Body
        }

        return Invoke-WebRequest @Params

    }

    catch {

        Write-Exception $_.Exception

        throw

    }

}

# Создание имени файла контакта

function New-CardFileName {

    param($User)

    $Name = $User.Mail.ToLower()

    $Name = $Name.Replace("@","_")

    $Name = $Name.Replace(".","_")

    return "$Name.vcf"

}

# Получение URI карточки

function Get-CardUri {

    param($User)

    $File = New-CardFileName $User

    return $Script:AddressBookUri + $File

}

#Проверка существования книги

function Test-AddressBook {

    Write-Log "Checking address book..."

    try {

        Invoke-CardDAV `
            -Uri $Script:AddressBookUri `
            -Method GET `
            | Out-Null

        Write-Log "Address book found." "SUCCESS"

        return $true

    }

    catch {

        Write-Log "Address book not found." "ERROR"

        return $false

    }

}

# Получение ETag

function Get-ETag {

    param($Response)

    if($Response.Headers.ETag)
    {
        return $Response.Headers.ETag
    }

    return $null

}

# Получение UID из URI

function Get-CardId {

    param([string]$Uri)

    return [System.IO.Path]::GetFileNameWithoutExtension($Uri)

}

# Проверка инициализации

function Test-Initialization {

    if($null -eq $Script:Headers)
    {
        throw "CardDAV module is not initialized."
    }

}

#==============================================================================
# Read CardDAV Address Book
#==============================================================================

function Get-CardDAVContacts {

    Test-Initialization

    Write-Log "Reading CardDAV address book..."

    $XmlBody = @"
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
    <d:prop>
        <d:getetag/>
    </d:prop>
</d:propfind>
"@

    $Response = Invoke-CardDAV `
        -Uri $Script:AddressBookUri `
        -Method PROPFIND `
        -ContentType "application/xml" `
        -Body $XmlBody `
        -Headers @{
            Depth = "1"
        }

    [xml]$Xml = $Response.Content

    $Contacts = @()

    foreach($Node in $Xml.multistatus.response)
    {

        if($Node.href -match "/$($Script:Config.AddressBook)/$")
        {
            continue
        }

        $Href = $Node.href

        $ETag = $null

        try
        {
            $ETag = $Node.propstat.prop.getetag
        }
        catch
        {
        }

        $Card = Read-CardDAVContact `
            -Uri ($Script:BaseUri + $Href) `
            -ETag $ETag

        if($null -ne $Card)
        {
            $Contacts += $Card
        }

    }

    Write-Log "Loaded $($Contacts.Count) contacts."

    return $Contacts

}

# Чтение одной карточки

function Read-CardDAVContact {

    param(

        [string]$Uri,

        [string]$ETag

    )

    try
    {

        $Response = Invoke-CardDAV `
            -Uri $Uri `
            -Method GET

        return ConvertFrom-VCard `
            -Text $Response.Content `
            -Uri $Uri `
            -ETag $ETag

    }

    catch
    {

        Write-Log "Cannot read $Uri" "ERROR"

        return $null

    }

}

# Разбор vCard

function ConvertFrom-VCard {

    param(

        [string]$Text,

        [string]$Uri,

        [string]$ETag

    )

    $Object = [ordered]@{

        DisplayName = ""

        GivenName = ""

        Surname = ""

        Department = ""

        Title = ""

        Company = ""

        Mail = ""

        Uri = $Uri

        ETag = $ETag

        Hash = ""

    }

    foreach($Line in ($Text -split "`r?`n"))
    {

        if($Line.StartsWith("FN:"))
        {
            $Object.DisplayName = $Line.Substring(3)
            continue
        }

        if($Line.StartsWith("N:"))
        {

            $Parts = $Line.Substring(2).Split(";")

            if($Parts.Count -ge 2)
            {
                $Object.Surname = $Parts[0]
                $Object.GivenName = $Parts[1]
            }

            continue

        }

        if($Line.StartsWith("TITLE:"))
        {
            $Object.Title = $Line.Substring(6)
            continue
        }

        if($Line.StartsWith("ORG:"))
        {

            $Parts = $Line.Substring(4).Split(";")

            if($Parts.Count -gt 0)
            {
                $Object.Company = $Parts[0]
            }

            if($Parts.Count -gt 1)
            {
                $Object.Department = $Parts[1]
            }

            continue

        }

        if($Line.StartsWith("EMAIL"))
        {

            $Index = $Line.IndexOf(":")

            if($Index -gt 0)
            {
                $Object.Mail = $Line.Substring($Index+1).ToLower()
            }

            continue

        }

    }

    $Object.Hash = Get-ContactHash $Object

    return [PSCustomObject]$Object

}

# Получение одной карточки по URI

function Get-CardDAVContact {

    param(

        [string]$Uri

    )

    return Read-CardDAVContact `
        -Uri $Uri `
        -ETag ""

}

# Получение контакта по email

function Find-CardDAVContact {

    param(

        [string]$Mail,

        $Contacts

    )

    foreach($Contact in $Contacts)
    {

        if($Contact.Mail.ToLower() -eq $Mail.ToLower())
        {
            return $Contact
        }

    }

    return $null

}

#==============================================================================
# Create contact
#==============================================================================

function Add-CardDAVContact {

    param($User)

    Test-Initialization

    Write-Log "Creating contact: $($User.DisplayName)"

    $Uri = Get-CardUri $User

    $VCard = New-VCard $User

    Invoke-CardDAV `
        -Uri $Uri `
        -Method PUT `
        -ContentType "text/vcard; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($VCard))

    Write-Log "Contact created." "SUCCESS"

}

function Update-CardDAVContact {

    param(

        $User,

        $Remote

    )

    Test-Initialization

    Write-Log "Updating $($User.DisplayName)"

    $VCard = New-VCard $User

    $Headers = @{}

    if($Remote.ETag)
    {
        $Headers["If-Match"] = $Remote.ETag
    }

    Invoke-CardDAV `
        -Uri $Remote.Uri `
        -Method PUT `
        -Headers $Headers `
        -ContentType "text/vcard; charset=utf-8" `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($VCard))

    Write-Log "Contact updated." "SUCCESS"

}

function Remove-CardDAVContact {

    param($Contact)

    Test-Initialization

    Write-Log "Deleting $($Contact.DisplayName)"

    Invoke-CardDAV `
        -Uri $Contact.Uri `
        -Method DELETE

    Write-Log "Contact deleted." "SUCCESS"

}

function Test-CardDAVContact {

    param($User)

    Test-Initialization

    try
    {

        Invoke-CardDAV `
            -Uri (Get-CardUri $User) `
            -Method HEAD `
            | Out-Null

        return $true

    }

    catch
    {

        return $false

    }

}

function Add-CardDAVContacts {

    param($Users)

    foreach($User in $Users)
    {

        Add-CardDAVContact $User

    }

}

function Remove-CardDAVContacts {

    param($Contacts)

    foreach($Contact in $Contacts)
    {

        Remove-CardDAVContact $Contact

    }

}

function Update-CardDAVContacts {

    param(

        $Users,

        $RemoteContacts

    )

    foreach($User in $Users)
    {

        $Remote = Find-CardDAVContact `
            -Mail $User.Mail `
            -Contacts $RemoteContacts

        if($null -eq $Remote)
        {
            continue
        }

        Update-CardDAVContact `
            -User $User `
            -Remote $Remote

    }

}

function Get-CardDAVStatistics {

    param($Contacts)

    return [PSCustomObject]@{

        Total = $Contacts.Count

    }

}

function Test-CardDAVWrite {

    Test-Initialization

    try
    {

        $Response = Invoke-CardDAV `
            -Uri $Script:AddressBookUri `
            -Method OPTIONS

        return $true

    }

    catch
    {

        return $false

    }

}

#==============================================================================
# Backup CardDAV
#==============================================================================

function Backup-CardDAV {

    Test-Initialization

    Write-Log "Creating CardDAV backup..."

    $Contacts = Get-CardDAVContacts

    if($Contacts.Count -eq 0)
    {
        Write-Log "Address book is empty."

        return
    }

    $Folder = Join-Path `
        $Config.ArchiveRoot `
        ("CardDAV_" + (Get-Date -Format "yyyyMMdd_HHmmss"))

    New-Item `
        -ItemType Directory `
        -Path $Folder `
        -Force | Out-Null

    foreach($Contact in $Contacts)
    {

        $Response = Invoke-CardDAV `
            -Uri $Contact.Uri `
            -Method GET

        $File = Join-Path `
            $Folder `
            ((Get-CardId $Contact.Uri) + ".vcf")

        $Response.Content |
            Set-Content `
                -Path $File `
                -Encoding UTF8

    }

    Write-Log "Backup completed."

}

function Get-CardDAVByMail {

    param(

        [string]$Mail,

        $Contacts

    )

    foreach($Contact in $Contacts)
    {

        if($Contact.Mail.ToLower() -eq $Mail.ToLower())
        {
            return $Contact
        }

    }

    return $null

}

function Clear-CardDAV {

    Test-Initialization

    $Contacts = Get-CardDAVContacts

    foreach($Contact in $Contacts)
    {

        Remove-CardDAVContact $Contact

    }

}

function Export-Statistics {

    param($Stats)

    Write-Host ""

    Write-Log "==============================="

    Write-Log "Synchronization finished"

    Write-Host ""

    Write-Log "Created : $($Stats.Created)"

    Write-Log "Updated : $($Stats.Updated)"

    Write-Log "Deleted : $($Stats.Deleted)"

    Write-Log "Skipped : $($Stats.Skipped)"

    Write-Log "Errors  : $($Stats.Errors)"

    Write-Host ""

}

function Close-CardDAV {

    $Script:Headers = $null

    $Script:Credential = $null

    $Script:Config = $null

    Write-Log "CardDAV session closed."

}

Export-ModuleMember `
    -Function Initialize-CardDAV,
              Test-CardDAV,
              Test-AddressBook,
              Backup-CardDAV,
              Get-CardDAVContacts,
              Get-CardDAVContact,
              Get-CardDAVByMail,
              Add-CardDAVContact,
              Update-CardDAVContact,
              Remove-CardDAVContact,
              Clear-CardDAV,
              Export-Statistics,
              Close-CardDAV
