<#
===========================================================================

SMK Corporate Directory Sync
Configuration file

Version : 1.0.0

===========================================================================

Изменяйте только значения параметров.
Структуру файла не изменять.

===========================================================================
#>

Set-StrictMode -Version Latest

$Global:Config = @{

    ########################################################################
    # Product
    ########################################################################

    Product = "SMK Corporate Directory Sync"

    Version = "1.0.0"

    Company = "SMK"

    ########################################################################
    # Nextcloud
    ########################################################################

    Server = "https://cloud.smk.local"

    AddressBook = "cmk"

    Username = "svc_carddav"

    Password = "bp9i6-RrmKC-amH4o-m6qs3-B6FBd"

    UserId = "svc_carddav"

    LogRoot = "F:\Logs"

    ArchiveRoot = "F:\Archive"

    ########################################################################
    # CardDAV
    ########################################################################

    CardDAVUri = "/remote.php/dav/addressbooks/users/svc_carddav/cmk"

    Timeout = 60

    IgnoreCertificateErrors = $false

    ########################################################################
    # Active Directory
    ########################################################################

    SearchBase = "OU=OU_USERS,DC=smk,DC=local"

    LDAPFilter = "(&(objectCategory=person)(objectClass=user))"

    Properties = @(
        "displayName",
        "givenName",
        "sn",
        "department",
        "title",
        "company",
        "mail"
    )

    ########################################################################
    # Synchronization
    ########################################################################

    DryRun = $false

    DeleteMissingContacts = $false

    UpdateExistingContacts = $true

    CreateMissingContacts = $true

    ########################################################################
    # Logging
    ########################################################################

    LogPath = "F:\Logs"

    LogRetentionDays = 90

    LogLevel = "INFO"

    ########################################################################
    # Archive
    ########################################################################

    ArchivePath = "F:\Archive"

    KeepArchivesDays = 180

    ########################################################################
    # State
    ########################################################################

    StateFile = ".\Data\State.json"

    ########################################################################
    # Performance
    ########################################################################

    RetryCount = 3

    RetryDelay = 5

    ParallelProcessing = $false

    ########################################################################
    # vCard
    ########################################################################

    Organization = "SMK"

    VCardVersion = "3.0"

}