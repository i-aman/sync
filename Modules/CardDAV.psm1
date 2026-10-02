#==============================================================================
#
# Module : CardDAV
#
# SMK Corporate Directory Sync
#
#==============================================================================

Set-StrictMode -Version Latest

function Convert-FromQuotedPrintableUtf8 {

    param([string]$Text)

    if([string]::IsNullOrEmpty($Text))
    {
        return ""
    }

    $Matches = [regex]::Matches($Text, '=[0-9A-Fa-f]{2}')

    if($Matches.Count -eq 0)
    {
        return $Text
    }

    $Bytes = New-Object byte[] $Matches.Count

    for($Index = 0; $Index -lt $Matches.Count; $Index++)
    {
        $Bytes[$Index] = [Convert]::ToByte($Matches[$Index].Value.Substring(1), 16)
    }

    return [System.Text.Encoding]::UTF8.GetString($Bytes)

}

function Unescape-VCardText {

    param([string]$Text)

    if([string]::IsNullOrEmpty($Text))
    {
        return ""
    }

    $Text = $Text.Replace('\n', "`n")
    $Text = $Text.Replace('\N', "`n")
    $Text = $Text.Replace('\;', ';')
    $Text = $Text.Replace('\,', ',')
    $Text = $Text.Replace('\\', '\')

    return $Text

}

function Convert-FromVCardValue {

    param(

        [string]$Line,

        [string]$Value

    )

    if($Line -match '(?i)ENCODING=QUOTED-PRINTABLE')
    {
        return Convert-FromQuotedPrintableUtf8 $Value
    }

    return Unescape-VCardText $Value

}

function Test-TextContainsNonAscii {

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

$Script:Initialized = $false

$Script:Config = $null
$Script:Credential = $null

$Script:BaseUri = $null
$Script:AddressBookUri = $null

#------------------------------------------------------------------------------
# Initialize CardDAV
#------------------------------------------------------------------------------

function Initialize-CardDAV {

    Write-Log "Initializing CardDAV module..."

    $Script:Config = $Global:Config

    if (-not $Script:Config) {
        throw "Configuration not loaded."
    }

    $SecurePassword = ConvertTo-SecureString `
        $Script:Config.Password `
        -AsPlainText `
        -Force

    $Script:Credential = New-Object System.Management.Automation.PSCredential(
        $Script:Config.Username,
        $SecurePassword
    )

    $Script:BaseUri = $Script:Config.Server.TrimEnd('/')

    $Script:AddressBookUri =
        "$($Script:BaseUri)/remote.php/dav/addressbooks/users/$($Script:Config.UserId)/$($Script:Config.AddressBook)/"

    $Script:Initialized = $true

    Write-Log "CardDAV initialized." "SUCCESS"

}

#------------------------------------------------------------------------------
# Test initialization
#------------------------------------------------------------------------------

function Test-Initialization {

    if (-not $Script:Initialized) {
        throw "CardDAV module is not initialized."
    }

}

#------------------------------------------------------------------------------
# Close session
#------------------------------------------------------------------------------

function Close-CardDAV {

    $Script:Initialized = $false

    $Script:Credential = $null

    Write-Log "CardDAV session closed."

}

#------------------------------------------------------------------------------
# Universal WebDAV Request
#------------------------------------------------------------------------------

function Invoke-CardDAV {

    param(

        [Parameter(Mandatory)]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [string]$ContentType = "application/xml; charset=utf-8",

        [hashtable]$Headers,

        [string]$Body

    )

    Test-Initialization

    Write-Log "$Method $Uri"

    try {

        $Request = [System.Net.HttpWebRequest]::Create($Uri)

        $Request.Method = $Method

        $Request.Credentials = $Script:Credential

        $Request.PreAuthenticate = $true

        $Request.UserAgent = "SMK Corporate Directory Sync"

        $Request.Accept = "*/*"

        if ($ContentType) {
            $Request.ContentType = $ContentType
        }

        if ($Headers) {

            foreach ($Header in $Headers.Keys) {

                switch ($Header) {

                    "Depth" {
                        $Request.Headers.Add("Depth", $Headers[$Header])
                    }

                    "If-Match" {
                        $Request.Headers.Add("If-Match", $Headers[$Header])
                    }

                    "If-None-Match" {
                        $Request.Headers.Add("If-None-Match", $Headers[$Header])
                    }

                    default {
                        $Request.Headers.Add($Header, $Headers[$Header])
                    }

                }

            }

        }

        if ($Body) {

            $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)

            $Request.ContentLength = $Bytes.Length

            $Stream = $Request.GetRequestStream()

            $Stream.Write($Bytes, 0, $Bytes.Length)

            $Stream.Close()

        }

        $Response = $Request.GetResponse()

        $Reader = New-Object System.IO.StreamReader(
            $Response.GetResponseStream()
        )

        $Content = $Reader.ReadToEnd()

        $Reader.Close()

        return [PSCustomObject]@{

            StatusCode = [int]$Response.StatusCode

            Headers = $Response.Headers

            Content = $Content

            Response = $Response

        }

    }
    catch [System.Net.WebException] {

        if ($_.Exception.Response) {

            $Reader = New-Object System.IO.StreamReader(
                $_.Exception.Response.GetResponseStream()
            )

            $Message = $Reader.ReadToEnd()

            $Reader.Close()

            Write-Log $Message "ERROR"

        }

        throw

    }

}

#------------------------------------------------------------------------------
# Test Connection
#------------------------------------------------------------------------------

function Test-CardDAV {

    Write-Log "Testing CardDAV connection..."

    try {

        $null = Invoke-CardDAV `
            -Method "OPTIONS" `
            -Uri $Script:AddressBookUri `
            -ContentType $null

        Write-Log "Connection successful." "SUCCESS"

        return $true

    }
    catch {

        Write-Exception $_.Exception

        return $false

    }

}


#------------------------------------------------------------------------------
# Get CardDAV contacts
#------------------------------------------------------------------------------

function Get-CardDAVContacts {

    Test-Initialization

    Write-Log "Reading CardDAV address book..."

    $Body = @'
<?xml version="1.0" encoding="utf-8"?>
<d:propfind
 xmlns:d="DAV:"
 xmlns:cs="http://calendarserver.org/ns/">

    <d:prop>

        <d:getetag/>

        <d:getcontenttype/>

    </d:prop>

</d:propfind>
'@

    $Response = Invoke-CardDAV `
        -Method "PROPFIND" `
        -Uri $Script:AddressBookUri `
        -Headers @{ Depth = "1" } `
        -Body $Body

    [xml]$Xml = $Response.Content

    $Result = @()

    foreach($Node in $Xml.multistatus.response)
    {

        if($Node.href -match "/$($Script:Config.AddressBook)/$")
        {
            continue
        }

        if($Node.href -notmatch "\.vcf$")
        {
            continue
        }

        $Href = [System.Uri]::UnescapeDataString($Node.href)

        $ETag = $Node.propstat.prop.getetag

        Write-Log "Found $Href"

        $Contact = Get-CardDAVContact `
                        -Href $Href `
                        -ETag $ETag

        if($Contact)
        {
            $Result += $Contact
        }

    }

    Write-Log "Loaded $($Result.Count) contacts."

    return @($Result)

}

#------------------------------------------------------------------------------
# Download single vCard
#------------------------------------------------------------------------------

function Get-CardDAVContact {

    param(

        [Parameter(Mandatory)]
        [string]$Href,

        [Parameter(Mandatory)]
        [string]$ETag

    )

    $Uri = "$($Script:BaseUri)$Href"

    Write-Log "Downloading $Uri"

    $Response = Invoke-CardDAV `
                    -Method "GET" `
                    -Uri $Uri `
                    -ContentType $null

    $VCard = $Response.Content

    return ConvertFrom-VCard `
                -VCard $VCard `
                -Href $Href `
                -ETag $ETag

}

#------------------------------------------------------------------------------
# Parse vCard
#------------------------------------------------------------------------------

function ConvertFrom-VCard {

    param(

        [string]$VCard,

        [string]$Href,

        [string]$ETag

    )

    $Contact = [ordered]@{

        DisplayName = ""

        GivenName = ""

        Surname = ""

        Department = ""

        Title = ""

        Company = ""

        Mail = ""

        OfficePhone = ""

        MobilePhone = ""

        WebPage = ""

        Uid = ""

        NeedsEncodingUpgrade = $false

        Href = $Href

        ETag = $ETag

        Hash = ""

    }

    foreach($Line in ($VCard -split "`r?`n"))
    {

        $ShouldCheckEncoding = $Line -notmatch '(?i)ENCODING=QUOTED-PRINTABLE'

        switch -Regex ($Line)
        {

            '^FN(?:;[^:]*)?:(.*)$'
            {
                $Contact.DisplayName = Convert-FromVCardValue $Line $Matches[1]

                if($ShouldCheckEncoding -and (Test-TextContainsNonAscii $Contact.DisplayName))
                {
                    $Contact.NeedsEncodingUpgrade = $true
                }
            }

            '^N(?:;[^:]*)?:(.*)$'
            {
                $NameValue = Convert-FromVCardValue $Line $Matches[1]

                $Parts = $NameValue -split ';'

                if($Parts.Count -gt 0)
                {
                    $Contact.Surname = $Parts[0]
                }

                if($Parts.Count -gt 1)
                {
                    $Contact.GivenName = $Parts[1]
                }

                if($ShouldCheckEncoding -and (Test-TextContainsNonAscii $NameValue))
                {
                    $Contact.NeedsEncodingUpgrade = $true
                }
            }

            '^ORG(?:;[^:]*)?:(.*)$'
            {
                $OrgValue = Convert-FromVCardValue $Line $Matches[1]

                $Parts = $OrgValue -split ";", 2

                $Contact.Company = $Parts[0]

                if ($Parts.Count -gt 1) {
                    $Contact.Department = $Parts[1]
                }

                if($ShouldCheckEncoding -and (Test-TextContainsNonAscii $OrgValue))
                {
                    $Contact.NeedsEncodingUpgrade = $true
                }
            }

            '^TITLE(?:;[^:]*)?:(.*)$'
            {
                $Contact.Title = Convert-FromVCardValue $Line $Matches[1]

                if($ShouldCheckEncoding -and (Test-TextContainsNonAscii $Contact.Title))
                {
                    $Contact.NeedsEncodingUpgrade = $true
                }
            }

            '^EMAIL(?:;[^:]*)?:(.*)$'
            {
                $Contact.Mail = Convert-FromVCardValue $Line $Matches[1]
            }

            '^TEL(?:;[^:]*)?:(.*)$'
            {
                $PhoneValue = Convert-FromVCardValue $Line $Matches[1]

                if($Line -match '(?i)TYPE=CELL')
                {
                    $Contact.MobilePhone = $PhoneValue
                }
                else
                {
                    $Contact.OfficePhone = $PhoneValue
                }
            }

            '^URL(?:;[^:]*)?:(.*)$'
            {
                $Contact.WebPage = Convert-FromVCardValue $Line $Matches[1]
            }

            '^UID(?:;[^:]*)?:(.*)$'
            {
                $Contact.Uid = Convert-FromVCardValue $Line $Matches[1]
            }

            '^X-DEPARTMENT(?:;[^:]*)?:(.*)$'
            {
                $Contact.Department = Convert-FromVCardValue $Line $Matches[1]

                if($ShouldCheckEncoding -and (Test-TextContainsNonAscii $Contact.Department))
                {
                    $Contact.NeedsEncodingUpgrade = $true
                }
            }

        }

    }

    $Contact.Hash = Get-ContactHash $Contact

    return [PSCustomObject]$Contact

}

#------------------------------------------------------------------------------
# Add CardDAV contact
#------------------------------------------------------------------------------

function Add-CardDAVContact {

    param(
        [Parameter(Mandatory)]
        $User
    )

    Write-Log "Creating contact: $($User.DisplayName)"

    $FileName = "$([guid]::NewGuid().ToString()).vcf"

    $Uri = "$($Script:AddressBookUri)$FileName"

    $VCard = New-VCard $User

    $null = Invoke-CardDAV `
        -Method "PUT" `
        -Uri $Uri `
        -ContentType "text/vcard; charset=utf-8" `
        -Headers @{
            "If-None-Match"="*"
        } `
        -Body $VCard

    Write-Log "Created: $($User.DisplayName)" "SUCCESS"

}

#------------------------------------------------------------------------------
# Update CardDAV contact
#------------------------------------------------------------------------------

function Update-CardDAVContact {

    param(

        [Parameter(Mandatory)]
        $User,

        [Parameter(Mandatory)]
        $Remote

    )

    Write-Log "Updating contact: $($User.DisplayName)"

    $Uri = "$($Script:BaseUri)$($Remote.Href)"

    $VCard = New-VCard $User

    $null = Invoke-CardDAV `
        -Method "PUT" `
        -Uri $Uri `
        -ContentType "text/vcard; charset=utf-8" `
        -Headers @{
            "If-Match" = $Remote.ETag
        } `
        -Body $VCard

    Write-Log "Updated: $($User.DisplayName)" "SUCCESS"

}

#------------------------------------------------------------------------------
# Remove CardDAV contact
#------------------------------------------------------------------------------

function Remove-CardDAVContact {

    param(

        [Parameter(Mandatory)]
        $Contact

    )

    Write-Log "Deleting: $($Contact.DisplayName)"

    $Uri = "$($Script:BaseUri)$($Contact.Href)"

    $null = Invoke-CardDAV `
        -Method "DELETE" `
        -Uri $Uri `
        -Headers @{
            "If-Match" = $Contact.ETag
        } `
        -ContentType $null

    Write-Log "Deleted: $($Contact.DisplayName)" "SUCCESS"

}

#------------------------------------------------------------------------------
# Exists
#------------------------------------------------------------------------------

function Test-CardDAVContact {

    param(
        [string]$Mail,
        $Contacts
    )

    foreach($Item in $Contacts){

        if($Item.Mail -eq $Mail){
            return $Item
        }

    }

    return $null

}

#------------------------------------------------------------------------------
# Find contact
#------------------------------------------------------------------------------

function Find-CardDAVContact {

    param(

        [string]$Mail,

        $Contacts

    )

    return $Contacts |
        Where-Object Mail -eq $Mail |
        Select-Object -First 1

}

#------------------------------------------------------------------------------
# Backup CardDAV
#------------------------------------------------------------------------------

function Backup-CardDAV {

    Test-Initialization

    Write-Log "Creating CardDAV backup..."

    $Contacts = @(Get-CardDAVContacts)

    if ($Contacts.Count -eq 0) {

        Write-Log "Address book is empty."

        return

    }

    $Folder = Join-Path `
        $Script:Config.ArchiveRoot `
        (Get-Date -Format "yyyy-MM-dd")

    if (!(Test-Path $Folder)) {

        New-Item `
            -ItemType Directory `
            -Path $Folder | Out-Null

    }

    foreach ($Contact in $Contacts) {

        try {

            $Uri = "$($Script:BaseUri)$($Contact.Href)"

            $Response = Invoke-CardDAV `
                -Method "GET" `
                -Uri $Uri `
                -ContentType $null

            $Name = Split-Path $Contact.Href -Leaf

            $File = Join-Path $Folder $Name

            Set-Content `
                -Path $File `
                -Value $Response.Content `
                -Encoding UTF8

        }
        catch {

            Write-Exception $_.Exception

        }

    }

    Write-Log "Backup completed." "SUCCESS"

}

#------------------------------------------------------------------------------
# Statistics
#------------------------------------------------------------------------------

function Get-CardDAVStatistics {

    param($Contacts)

    $SafeContacts = @($Contacts)

    return [PSCustomObject]@{

        Total = $SafeContacts.Count

        WithEmail = ($SafeContacts | Where-Object Mail).Count

        WithoutEmail = ($SafeContacts | Where-Object {-not $_.Mail}).Count

    }

}
#------------------------------------------------------------------------------
# Test AddressBook
#------------------------------------------------------------------------------

function Test-AddressBook {

    Test-Initialization

    try {

        $null = Invoke-CardDAV `
            -Method "OPTIONS" `
            -Uri $Script:AddressBookUri `
            -ContentType $null

        return $true

    }
    catch {

        return $false

    }

}


#------------------------------------------------------------------------------
# Clear AddressBook
#------------------------------------------------------------------------------

function Clear-CardDAV {

    $Contacts = @(Get-CardDAVContacts)

    foreach ($Contact in $Contacts) {

        Remove-CardDAVContact $Contact

    }

}

Export-ModuleMember `
    -Function Initialize-CardDAV,
              Close-CardDAV,
              Test-CardDAV,
              Test-AddressBook,
              Backup-CardDAV,
              Get-CardDAVContacts,
              Get-CardDAVContact,
              Add-CardDAVContact,
              Update-CardDAVContact,
              Remove-CardDAVContact,
              Find-CardDAVContact,
              Test-CardDAVContact,
              Get-CardDAVStatistics,
              Invoke-CardDAV

