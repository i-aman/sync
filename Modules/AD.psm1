<#
============================================================================

SMK Corporate Directory Sync

Active Directory Module

Version : 1.0.0

============================================================================
#>

Set-StrictMode -Version Latest

Import-Module ActiveDirectory -ErrorAction Stop

# Проверка подключения

function Test-ADConnection {

    try {

        Get-ADDomain | Out-Null

        Write-Log "Connected to Active Directory." "SUCCESS"

        return $true

    }

    catch {

        Write-Exception $_.Exception

        return $false

    }

}

# Получение пользователей

function Get-ADContacts {

    $Config = $Global:Config

    Write-Log "Reading Active Directory..."

    $Properties = @(
        @($Config.Properties) + @(
            "displayName",
            "givenName",
            "middleName",
            "sn",
            "department",
            "title",
            "company",
            "mail",
            "telephoneNumber",
            "mobile",
            "wWWHomePage"
        ) | Select-Object -Unique
    )

    $Users = Get-ADUser `
        -LDAPFilter $Config.LDAPFilter `
        -SearchBase $Config.SearchBase `
        -Properties $Properties

    $RawUsers = @($Users)

    Write-Log "AD objects found : $($RawUsers.Count)"

    $Result = @()

    $SkippedWithoutName = 0

    foreach($User in $RawUsers)
    {

        if([string]::IsNullOrWhiteSpace($User.DisplayName) -and
           [string]::IsNullOrWhiteSpace($User.GivenName) -and
           [string]::IsNullOrWhiteSpace($User.Surname))
        {
            $SkippedWithoutName++

            continue
        }

        $Result += ConvertTo-ContactObject $User

    }

    Write-Log "$($Result.Count) users loaded."

    if($SkippedWithoutName -gt 0)
    {
        Write-Log "Skipped without name : $SkippedWithoutName" "WARN"
    }

    Write-Log "Users with mail    : $((@($Result | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Mail) })).Count)"

    Write-Log "Users without mail : $((@($Result | Where-Object { [string]::IsNullOrWhiteSpace($_.Mail) })).Count)" "WARN"

    return $Result

}

# Преобразование пользователя

function ConvertTo-ContactObject {

    param(

        [Microsoft.ActiveDirectory.Management.ADUser]$User

    )

    $DisplayName = ConvertTo-NormalizedString $User.DisplayName
    $GivenName = ConvertTo-NormalizedString $User.GivenName
    $Surname = ConvertTo-NormalizedString $User.Surname
    $MiddleName = ConvertTo-NormalizedString $User.MiddleName

    if([string]::IsNullOrWhiteSpace($MiddleName) -and
       -not [string]::IsNullOrWhiteSpace($DisplayName) -and
       -not [string]::IsNullOrWhiteSpace($GivenName) -and
       -not [string]::IsNullOrWhiteSpace($Surname))
    {
        $NameParts = @($DisplayName -split '\s+')

        if($NameParts.Count -eq 3 -and
           $NameParts[0] -eq $Surname -and
           $NameParts[1] -eq $GivenName)
        {
            $MiddleName = $NameParts[2]
            Write-Log "Middle name inferred from DisplayName because AD middleName is empty: $DisplayName" "WARN"
        }
    }

    return [PSCustomObject]@{

        DisplayName = $DisplayName

        GivenName = $GivenName

        MiddleName = $MiddleName

        Surname = $Surname

        Department = ConvertTo-NormalizedString $User.Department

        Title = ConvertTo-NormalizedString $User.Title

        Company = ConvertTo-NormalizedString $User.Company

        Mail = ConvertTo-NormalizedEmail $User.Mail

        OfficePhone = ConvertTo-NormalizedString $User.telephoneNumber

        MobilePhone = ConvertTo-NormalizedString $User.mobile

        WebPage = ConvertTo-NormalizedString $User.wWWHomePage

        Hash = ""

        Guid = $User.ObjectGUID.ToString()

        DistinguishedName = $User.DistinguishedName

    }

}

# Сортировка

function Get-SortedContacts {

    param($Contacts)

    return $Contacts |

        Sort-Object DisplayName

}

# Поиск дублей 

function Find-DuplicateEmails {

    param($Users)

    $Duplicates = @()

    $Users |

        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Mail) } |

        Group-Object Mail |

        Where-Object Count -gt 1 |

        ForEach-Object {

            $Duplicates += $_

        }

    return $Duplicates

}

# Проверка пользователей

function Get-ValidContacts {

    param($Users)

    $Valid = @()

    foreach($User in $Users)
    {

        if((-not [string]::IsNullOrWhiteSpace($User.Mail)) -and !(Test-Mail $User.Mail))
        {
            Write-Log "Invalid e-mail : $($User.DisplayName)" "WARN"

            continue
        }

        $User.Hash = Get-ContactHash $User

        $Valid += $User

    }

    return $Valid

}

# Статистика AD

function Get-ADStatistics {

    param($Users)

    $SafeUsers = @($Users)

    return [PSCustomObject]@{

        Users = $SafeUsers.Count

        Departments = ($SafeUsers.Department |

            Sort-Object -Unique).Count

        Companies = ($SafeUsers.Company |

            Sort-Object -Unique).Count

    }

}

# Вывод статистики

function Show-ADStatistics {

    param($Statistics)

    Write-Separator

    Write-Host "Active Directory"

    Write-Separator

    Write-Log "Users       : $($Statistics.Users)"

    Write-Log "Departments : $($Statistics.Departments)"

    Write-Log "Companies   : $($Statistics.Companies)"

}

# main function

function Get-DirectoryUsers {

    if(!(Test-ADConnection))
    {
        throw "Cannot connect to Active Directory."
    }

    $Users = @(Get-ADContacts)

    $Users = @(Get-ValidContacts $Users)

    $Users = @(Get-SortedContacts $Users)

    $Duplicates = @(Find-DuplicateEmails $Users)

    if($Duplicates.Count -gt 0)
    {

        Write-Log "Duplicate e-mail addresses found." "WARN"

        foreach($Item in $Duplicates)
        {

            Write-Log ("{0} ({1})" -f $Item.Name, $Item.Count) "WARN"

        }

    }

    Show-ADStatistics (

        Get-ADStatistics $Users

    )

    return $Users

}

# export

Export-ModuleMember -Function Get-DirectoryUsers

Export-ModuleMember -Function Get-ADContacts

Export-ModuleMember -Function Test-ADConnection

Export-ModuleMember -Function Get-ValidContacts

Export-ModuleMember -Function ConvertTo-ContactObject
