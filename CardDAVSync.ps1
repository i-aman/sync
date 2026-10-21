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

function Get-ContactMailKey {

    param($Contact)

    if ($null -eq $Contact -or
        $Contact.PSObject.Properties.Name -notcontains "Mail" -or
        [string]::IsNullOrWhiteSpace($Contact.Mail)) {
        return ""
    }

    return ([string]$Contact.Mail).Trim().ToLower()

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
    $RemoteByMail=@{}

    foreach($Item in $RemoteContacts){

    $RemoteKey = Get-ContactKey $Item

    if(-not [string]::IsNullOrWhiteSpace($RemoteKey)){
        $Remote[$RemoteKey] = $Item
    }

    $MailKey = Get-ContactMailKey $Item

    if(-not [string]::IsNullOrWhiteSpace($MailKey)){
        if(-not $RemoteByMail.ContainsKey($MailKey)){
            $RemoteByMail[$MailKey] = @()
        }

        $RemoteByMail[$MailKey] += $Item
    }

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

        $Existing = $null

        if($Remote.ContainsKey($ContactKey)){
            $Existing = $Remote[$ContactKey]
        }
        else{
            $MailKey = Get-ContactMailKey $User

            if(-not [string]::IsNullOrWhiteSpace($MailKey) -and
               $RemoteByMail.ContainsKey($MailKey)){

                $MailMatches = @($RemoteByMail[$MailKey])

                if($MailMatches.Count -eq 1){
                    $Existing = $MailMatches[0]
                    Write-Log "Matching existing contact by e-mail: $($User.DisplayName)" "WARN"
                }
                elseif($MailMatches.Count -gt 1){
                    $UidMatches = @(
                        $MailMatches | Where-Object {
                            $_.Uid -and
                            ([string]$_.Uid).Trim().ToLower() -eq $ContactKey
                        }
                    )

                    if($UidMatches.Count -eq 1){
                        $Existing = $UidMatches[0]
                    }
                    else{
                        Write-Log "Ambiguous CardDAV duplicates for e-mail: $MailKey. Skipping contact." "WARN"
                        $Stats.Skipped++
                        continue
                    }
                }
            }
        }

        if($null -ne $Existing){

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
    # Remove duplicate remote contacts when a unique AD user and canonical card are known
    #

    $UsersByMail=@{}

    foreach($User in $ADUsers){
        $MailKey = Get-ContactMailKey $User

        if([string]::IsNullOrWhiteSpace($MailKey)){
            continue
        }

        if(-not $UsersByMail.ContainsKey($MailKey)){
            $UsersByMail[$MailKey] = @()
        }

        $UsersByMail[$MailKey] += $User
    }

    $DeletedHrefs=@{}

    foreach($MailKey in $UsersByMail.Keys){
        if($UsersByMail[$MailKey].Count -ne 1){
            continue
        }

        $User = $UsersByMail[$MailKey][0]
        $MailMatches = @(
            $RemoteContacts | Where-Object {
                (Get-ContactMailKey $_) -eq $MailKey
            }
        )

        if($MailMatches.Count -le 1){
            continue
        }

        $ContactKey = Get-ContactKey $User
        $UidMatches = @(
            $MailMatches | Where-Object {
                $_.Uid -and
                ([string]$_.Uid).Trim().ToLower() -eq $ContactKey
            }
        )

        $Canonical = $null

        if($UidMatches.Count -eq 1){
            $Canonical = $UidMatches[0]
        }
        elseif($UidMatches.Count -gt 1){
            $HashMatches = @(
                $UidMatches | Where-Object {
                    $_.Hash -eq (Get-ContactHash $User)
                }
            )

            if($HashMatches.Count -eq 1){
                $Canonical = $HashMatches[0]
            }
        }
        else{
            $HashMatches = @(
                $MailMatches | Where-Object {
                    $_.Hash -eq (Get-ContactHash $User)
                }
            )

            if($HashMatches.Count -eq 1){
                $Canonical = $HashMatches[0]
            }
        }

        if($null -eq $Canonical){
            Write-Log "Cannot safely identify canonical CardDAV contact for e-mail: $MailKey. Leaving duplicates unchanged." "WARN"
            continue
        }

        foreach($Contact in $MailMatches){
            if($Contact.Href -eq $Canonical.Href){
                continue
            }

            Remove-CardDAVContact $Contact
            $DeletedHrefs[$Contact.Href] = $true
            $Stats.Deleted++
        }
    }

    #
    # Delete removed users
    #

    $ADContactKeys=@{}

    foreach($User in $ADUsers){
        $UserKey = Get-ContactKey $User
        $MailKey = Get-ContactMailKey $User

        if(-not [string]::IsNullOrWhiteSpace($UserKey)){
            $ADContactKeys[$UserKey] = $true
        }

        if(-not [string]::IsNullOrWhiteSpace($MailKey)){
            $ADContactKeys["mail:$MailKey"] = $true
        }
    }

    foreach($Contact in $RemoteContacts){

        if($DeletedHrefs.ContainsKey($Contact.Href)){
            continue
        }

        $RemoteKey = Get-ContactKey $Contact
        $MailKey = Get-ContactMailKey $Contact

        if(((-not [string]::IsNullOrWhiteSpace($RemoteKey)) -and
            $ADContactKeys.ContainsKey($RemoteKey)) -or
           ((-not [string]::IsNullOrWhiteSpace($MailKey)) -and
            $ADContactKeys.ContainsKey("mail:$MailKey"))){
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

