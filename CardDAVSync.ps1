<#
============================================================================

SMK Corporate Directory Sync

Version 1.0

Main synchronization script

============================================================================
#>

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"

$Root = Split-Path $MyInvocation.MyCommand.Path

#------------------------------------------------------------------------------
# Load configuration
#------------------------------------------------------------------------------

. "$Root\Config.ps1"

#------------------------------------------------------------------------------
# Load modules
#------------------------------------------------------------------------------

Import-Module "$Root\Modules\Logging.psm1" -Force
Import-Module "$Root\Modules\Utils.psm1" -Force
Import-Module "$Root\Modules\AD.psm1" -Force
Import-Module "$Root\Modules\VCard.psm1" -Force
Import-Module "$Root\Modules\CardDAV.psm1" -Force

Initialize-Logger

Write-Banner "SMK Corporate Directory Sync"

Write-Log "Version : $($Config.Version)"
Write-Log "Server  : $($Config.Server)"
Write-Log "Book    : $($Config.AddressBook)"

function Get-ContactKey {

    param($Contact)

    if ($null -eq $Contact) {
        return ""
    }

    foreach ($PropertyName in @("Guid", "Uid", "Mail")) {

        if ($Contact.PSObject.Properties.Name -contains $PropertyName) {

            $Value = [string]$Contact.$PropertyName

            if (-not [string]::IsNullOrWhiteSpace($Value)) {
                return $Value.Trim().ToLower()
            }

        }

    }

    return ""

}

#------------------------------------------------------------------------------
# Statistics
#------------------------------------------------------------------------------

$Stats=[pscustomobject]@{

    Created=0

    Updated=0

    Deleted=0

    Skipped=0

    Errors=0

}

try{

    Initialize-CardDAV

    if(-not(Test-CardDAV))
    {
        throw "Cannot connect to CardDAV."
    }

    Backup-CardDAV

    Write-Host ""

    $ADUsers=@(Get-DirectoryUsers)

    Write-Log "Users found : $($ADUsers.Count)"

    Write-Host ""
    Write-Log "Reading CardDAV..."

    $RemoteContacts = @(Get-CardDAVContacts)

    Write-Log "Contacts found : $($RemoteContacts.Count)"

    #
    # Create lookup table
    #

    $Remote=@{}

    foreach($Item in $RemoteContacts){

    $RemoteKey = Get-ContactKey $Item

    if([string]::IsNullOrWhiteSpace($RemoteKey)){
        continue
    }

    $Remote[$RemoteKey] = $Item

    }

    #
    # Create / Update
    #

    foreach($User in $ADUsers){

        if([string]::IsNullOrWhiteSpace($User.Mail))
        {
            continue
        }

        $ContactKey = Get-ContactKey $User

        if([string]::IsNullOrWhiteSpace($ContactKey))
        {
            Write-Log "Skip without key: $($User.DisplayName)" "WARN"

            $Stats.Skipped++

            continue
        }

        if($Remote.ContainsKey($ContactKey)){

            $Existing=$Remote[$ContactKey]

            if($Existing.PSObject.Properties.Name -contains "NeedsEncodingUpgrade" -and $Existing.NeedsEncodingUpgrade)
            {

                Write-Log "Upgrade encoding: $($User.DisplayName)"

                Update-CardDAVContact `
                    -User $User `
                    -Remote $Existing

                $Stats.Updated++

                continue

            }

            if($Existing.Hash -eq (Get-ContactHash $User))
            {

                Write-Log "Skip : $($User.DisplayName)"

                $Stats.Skipped++

            }
            else{

                Update-CardDAVContact `
                    -User $User `
                    -Remote $Existing

                $Stats.Updated++

            }

        }
        else{

            Add-CardDAVContact $User

            $Stats.Created++

        }

    }

    #
    # Delete removed users
    #

    foreach($Contact in $RemoteContacts){

        $RemoteKey = Get-ContactKey $Contact

        if([string]::IsNullOrWhiteSpace($RemoteKey))
        {
            continue
        }

        if((@($ADUsers | ForEach-Object { Get-ContactKey $_ })) -contains $RemoteKey)
        {
            continue
        }

        Remove-CardDAVContact $Contact

        $Stats.Deleted++

    }

}
catch{

    $Stats.Errors++

    Write-Exception $_.Exception

}
finally{

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

    Close-CardDAV

}


