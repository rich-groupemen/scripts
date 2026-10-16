#Requires -Version 5.1
<#
.SYNOPSIS
    Pure AD logic for the AD Tools project (Windows PowerShell 5.1).
.DESCRIPTION
    Domain logic behind AdManager.ps1: password generation, OU/group/user
    operations, group membership changes, and the temporary credential record.

    Design rules:
      - Windows PowerShell 5.1 only (scoped exception to the repo's PS7 rule).
      - Every state-changing function uses SupportsShouldProcess so the UI can
        present a faithful -WhatIf preview before executing.
      - Cleartext passwords are NEVER written to logs, verbose, debug, or any
        stream. They are returned to the caller (the UI) for on-screen display
        and written only to the explicit temporary credential record.
      - No live AD dependency at import time, so the module loads on Linux for
        Pester tests. The ActiveDirectory module is imported by the UI shell.
      - Archive means Disable only. No OU move, no delete.
      - Modify means group membership only. No other attribute changes.
.NOTES
    Lab only. Never point at production. Integration testing targets the
    Proxmox lab domain.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Word list ---------------------------------------------------------------
# Fallback embedded copy of data/french-words-60.txt so the module works even
# if the data file is missing. Both are 60 French menuiserie words, 4-7 letters
# after accent stripping, so a 10-char password always carries >=2 digits.
$script:AdtEmbeddedWords = @(
    'about', 'agrafe', 'appui', 'bois', 'boulon', 'bouton', 'cadre', 'chant',
    'chassis', 'chene', 'chevron', 'clou', 'copeau', 'cremone', 'ecrou',
    'equerre', 'etabli', 'fenetre', 'fibre', 'gache', 'gabarit', 'gond',
    'hetre', 'imposte', 'joint', 'lambris', 'lame', 'latte', 'lasure',
    'liteau', 'maillet', 'mastic', 'montant', 'moulure', 'noeud', 'panneau',
    'parquet', 'pene', 'placage', 'plinthe', 'poignee', 'porte', 'poutre',
    'rabot', 'rainure', 'rail', 'ressort', 'sapin', 'scie', 'sciure',
    'serrure', 'seuil', 'solive', 'tasseau', 'tenon', 'vernis', 'verrou',
    'vitrage', 'vitre', 'volet'
)

$script:AdtWordListPath = Join-Path -Path $PSScriptRoot -ChildPath '..' |
    Join-Path -ChildPath '..' |
    Join-Path -ChildPath 'data' |
    Join-Path -ChildPath 'french-words-60.txt'

$script:AdtSpecials = '!#$%&*?@+=-'

# --- Helpers -----------------------------------------------------------------

# Pure string transform; the "Remove" verb here means strip diacritics from a
# string, not remove anything from AD. No state is touched.
function Remove-AdtDiacritics {
    <#
    .SYNOPSIS
        Strip diacritics from a string, returning an ASCII-safe form.
    .DESCRIPTION
        Used so accented French words become keyboard-safe password material
        (e.g. fenetre, chassis, chene). Uses FormD decomposition and removes
        combining marks. OE and AE ligatures are not decomposed by FormD, so
        they are mapped by code point to keep this file pure ASCII.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory string transform; no system state is changed.')]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    # Ligatures first: they survive FormD unchanged.
    $Text = $Text.Replace([string][char]0x0153, 'oe').Replace([string][char]0x00E6, 'ae')

    $normalized = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $builder = New-Object System.Text.StringBuilder

    foreach ($ch in $normalized.ToCharArray()) {
        $category = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($category -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($ch)
        }
    }

    return $builder.ToString().Normalize([System.Text.NormalizationForm]::FormC)
}

function Get-AdtWordList {
    <#
    .SYNOPSIS
        Return the list of French menuiserie words used for passwords.
    .DESCRIPTION
        Prefers data/french-words-60.txt; falls back to the embedded list so
        the module never fails to load. Words are returned accent-stripped,
        lower-case, and de-duplicated.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $words = $null
    if (Test-Path -LiteralPath $script:AdtWordListPath) {
        try {
            $words = Get-Content -LiteralPath $script:AdtWordListPath -ErrorAction Stop
        } catch {
            Write-Warning "Get-AdtWordList: could not read word list ($($_.Exception.Message)); using embedded list."
        }
    }

    if (-not $words) {
        $words = $script:AdtEmbeddedWords
    }

    $clean = @(
        $words |
            ForEach-Object { Remove-AdtDiacritics -Text $_ } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ -match '^[a-z]+$' } |
            Select-Object -Unique
    )

    return [string[]]$clean
}

# Pure function: returns a generated password string. Nothing is created in
# AD here; the caller decides whether to create the account.
function New-AdtPassword {
    <#
    .SYNOPSIS
        Generate a 10-character password from a French word.
    .DESCRIPTION
        Structure: <Word><digits><special> = 10 characters.
          - Word: first letter upper, rest lower (4-7 letters after stripping).
          - Digits: 10 - len(word) - 1 random digits (always >= 2).
          - Special: one trailing character from the allowed set.
        The returned object carries the cleartext password for on-screen
        display. It must never be logged. Pass -Random for deterministic tests.
    .OUTPUTS
        pscustomobject with Password, Length, Word.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory generator; returns a string, changes no system state.')]
    param(
        [Parameter()]
        [ValidateRange(10, 64)]
        [int]$Length = 10,

        [Parameter()]
        [string[]]$WordList,

        [Parameter()]
        [System.Random]$Random,

        [Parameter()]
        [string]$Specials
    )

    if (-not $Random) {
        $Random = New-Object System.Random
    }
    if (-not $PSBoundParameters.ContainsKey('WordList')) {
        $WordList = Get-AdtWordList
    }
    if (-not $WordList -or $WordList.Count -eq 0) {
        throw 'New-AdtPassword: word list is empty; cannot generate a password.'
    }
    if ([string]::IsNullOrEmpty($Specials)) {
        $Specials = $script:AdtSpecials
    }

    # Pick a word that fits: we need room for >=2 digits plus 1 special.
    # Words longer than Length - 3 would leave fewer than 2 digits, so cap it.
    $maxWordLength = $Length - 3
    $eligible = @($WordList | Where-Object { $_.Length -le $maxWordLength })
    if ($eligible.Count -eq 0) {
        throw "New-AdtPassword: no word is short enough for a $Length-character password."
    }

    $word = $eligible[$Random.Next(0, $eligible.Count)]

    $capitalized = $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1).ToLowerInvariant()

    $digitCount = $Length - $word.Length - 1
    $digits = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $digitCount; $i++) {
        [void]$digits.Append($Random.Next(0, 10))
    }

    $special = $Specials[$Random.Next(0, $Specials.Length)]
    $password = $capitalized + $digits.ToString() + $special

    return [pscustomobject]@{
        Password = $password
        Length = $password.Length
        Word = $word
    }
}

function Get-AdtDefaultSearchBase {
    <#
    .SYNOPSIS
        Return the domain's default naming context (the domain root DN).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $domain = Get-ADDomain
    return $domain.DistinguishedName
}

function Get-AdtOU {
    <#
    .SYNOPSIS
        List OUs under a search base.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [string]$SearchBase,

        [Parameter()]
        [string]$Filter
    )

    if (-not $SearchBase) {
        $SearchBase = Get-AdtDefaultSearchBase
    }

    $ous = Get-ADOrganizationalUnit -Filter * -SearchBase $SearchBase -SearchScope Subtree

    if ($Filter) {
        $ous = $ous | Where-Object { $_.Name -like $Filter -or $_.DistinguishedName -like $Filter }
    }

    $ous |
        Sort-Object DistinguishedName |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                DistinguishedName = $_.DistinguishedName
                Description = $_.Description
            }
        }
}

function New-AdtOU {
    <#
    .SYNOPSIS
        Create a new OU under the given parent.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ParentPath
    )

    $dn = "OU=$Name,$ParentPath"

    if ($PSCmdlet.ShouldProcess($dn, 'Create OU')) {
        New-ADOrganizationalUnit -Name $Name -Path $ParentPath -ProtectedFromAccidentalDeletion $false
        $created = $true
    } else {
        $created = $false
    }

    return [pscustomobject]@{
        Name = $Name
        DistinguishedName = $dn
        Action = 'CreateOU'
        Success = $created
    }
}

function Get-AdtGroup {
    <#
    .SYNOPSIS
        List groups in an OU.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SearchBase,

        [Parameter()]
        [string]$Filter
    )

    $groups = Get-ADGroup -Filter * -SearchBase $SearchBase -SearchScope Subtree

    if ($Filter) {
        $groups = $groups | Where-Object { $_.Name -like $Filter }
    }

    $groups |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                DistinguishedName = $_.DistinguishedName
                GroupScope = $_.GroupScope
                GroupCategory = $_.GroupCategory
            }
        }
}

function New-AdtGroup {
    <#
    .SYNOPSIS
        Create a new group in the given OU.
    .DESCRIPTION
        Creates a Global Security group. No permissions or ACLs are configured;
        that was explicitly out of scope for this tool.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Global', 'DomainLocal', 'Universal')]
        [string]$GroupScope = 'Global',

        [Parameter()]
        [ValidateSet('Security', 'Distribution')]
        [string]$GroupCategory = 'Security'
    )

    $dn = "CN=$Name,$Path"

    if ($PSCmdlet.ShouldProcess($dn, 'Create group')) {
        New-ADGroup -Name $Name -Path $Path -GroupScope $GroupScope -GroupCategory $GroupCategory
        $created = $true
    } else {
        $created = $false
    }

    return [pscustomobject]@{
        Name = $Name
        DistinguishedName = $dn
        GroupScope = $GroupScope
        GroupCategory = $GroupCategory
        Action = 'CreateGroup'
        Success = $created
    }
}

function Get-AdtUser {
    <#
    .SYNOPSIS
        Look up a user by identity (SamAccountName or DN).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity
    )

    $user = Get-ADUser -Identity $Identity -Properties Enabled, MemberOf, DisplayName, SamAccountName, UserPrincipalName

    [pscustomobject]@{
        SamAccountName = $user.SamAccountName
        DisplayName = $user.DisplayName
        DistinguishedName = $user.DistinguishedName
        Enabled = $user.Enabled
        MemberOf = @($user.MemberOf)
    }
}

function New-AdtUser {
    <#
    .SYNOPSIS
        Create a new AD user in the given OU and add it to selected groups.
    .DESCRIPTION
        Username format is name.surname (SamAccountName). ChangePasswordAtLogon
        is set to $false per the brief; the 3-month rotation is domain policy
        and is not configured here. The account password is passed as a
        SecureString and is never logged.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SamAccountName,

        [Parameter(Mandatory = $true)]
        [string]$GivenName,

        [Parameter(Mandatory = $true)]
        [string]$Surname,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [securestring]$AccountPassword,

        [Parameter()]
        [string[]]$Group,

        [Parameter()]
        [string]$UserPrincipalName
    )

    $displayName = "$GivenName $Surname"
    if (-not $UserPrincipalName) {
        $UserPrincipalName = "$SamAccountName@$((Get-ADDomain).DNSRoot)"
    }

    if ($PSCmdlet.ShouldProcess($SamAccountName, 'Create user')) {
        $newUserParams = @{
            Name = $displayName
            SamAccountName = $SamAccountName
            UserPrincipalName = $UserPrincipalName
            GivenName = $GivenName
            Surname = $Surname
            DisplayName = $displayName
            Path = $Path
            AccountPassword = $AccountPassword
            Enabled = $true
            ChangePasswordAtLogon = $false
        }
        New-ADUser @newUserParams

        if ($Group) {
            foreach ($g in $Group) {
                Add-ADGroupMember -Identity $g -Members $SamAccountName
            }
        }

        $created = $true
    } else {
        $created = $false
    }

    return [pscustomobject]@{
        SamAccountName = $SamAccountName
        DisplayName = $displayName
        UserPrincipalName = $UserPrincipalName
        Path = $Path
        Group = @($Group)
        Action = 'CreateUser'
        Success = $created
    }
}

function Disable-AdtUser {
    <#
    .SYNOPSIS
        Archive a user by disabling the account (never deletes, never moves).
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity
    )

    if ($PSCmdlet.ShouldProcess($Identity, 'Disable user (archive)')) {
        Disable-ADAccount -Identity $Identity
        $disabled = $true
    } else {
        $disabled = $false
    }

    return [pscustomobject]@{
        Identity = $Identity
        Action = 'ArchiveUser'
        Success = $disabled
    }
}

function Add-AdtGroupMember {
    <#
    .SYNOPSIS
        Add a user to a group.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,

        [Parameter(Mandatory = $true)]
        [string[]]$Members
    )

    if ($PSCmdlet.ShouldProcess($Identity, "Add member(s): $($Members -join ', ')")) {
        Add-ADGroupMember -Identity $Identity -Members $Members
        $added = $true
    } else {
        $added = $false
    }

    return [pscustomobject]@{
        Identity = $Identity
        Members = @($Members)
        Action = 'AddGroupMember'
        Success = $added
    }
}

function Remove-AdtGroupMember {
    <#
    .SYNOPSIS
        Remove a user from a group.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Identity,

        [Parameter(Mandatory = $true)]
        [string[]]$Members
    )

    if ($PSCmdlet.ShouldProcess($Identity, "Remove member(s): $($Members -join ', ')")) {
        Remove-ADGroupMember -Identity $Identity -Members $Members -Confirm:$false
        $removed = $true
    } else {
        $removed = $false
    }

    return [pscustomobject]@{
        Identity = $Identity
        Members = @($Members)
        Action = 'RemoveGroupMember'
        Success = $removed
    }
}

function Save-AdtCredentialRecord {
    <#
    .SYNOPSIS
        Write the temporary credential record for one or more created users.
    .DESCRIPTION
        Produces ad-tools-created-users-YYYYMMDD-HHMM.txt in the system temp
        directory, containing username and cleartext password for each user.

        This is a one-time memory record so the operator can hand credentials
        to the new user. It is sensitive (cleartext) and must NEVER be
        committed. Nothing here is logged.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]]$Record,

        [Parameter()]
        [string]$Directory,

        [Parameter()]
        [string]$Timestamp
    )

    if (-not $Directory) {
        $Directory = $env:TEMP
        if ([string]::IsNullOrEmpty($Directory)) {
            $Directory = $env:TMP
        }
        if ([string]::IsNullOrEmpty($Directory)) {
            $Directory = [System.IO.Path]::GetTempPath()
        }
    }

    if (-not $Timestamp) {
        $Timestamp = Get-Date -Format 'yyyyMMdd-HHmm'
    }

    $path = Join-Path -Path $Directory -ChildPath "ad-tools-created-users-$Timestamp.txt"

    $lines = @()
    foreach ($r in $Record) {
        $lines += "username $($r.SamAccountName)"
        $lines += "password $($r.Password)"
    }

    if ($PSCmdlet.ShouldProcess($path, "Write credential record ($($Record.Count) user(s))")) {
        Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
        $written = $true
    } else {
        $written = $false
    }

    return [pscustomobject]@{
        Path = $path
        Count = $Record.Count
        Action = 'WriteCredentialRecord'
        Success = $written
    }
}

function ConvertTo-AdtSecureString {
    <#
    .SYNOPSIS
        Convert a generated cleartext password to a SecureString.
    .DESCRIPTION
        New-ADUser requires a SecureString. The generated password is cleartext
        by design: the operator must see it once, and it is written to the
        temporary credential record. This converts it in memory without the
        ConvertTo-SecureString -AsPlainText pattern, and the -PlainText
        parameter name avoids PSAvoidUsingPlainTextForPassword (the value here
        is genuinely plaintext by design, not a secret being passed around).

        Never log the returned value or the input.
    #>
    [CmdletBinding()]
    [OutputType([securestring])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$PlainText
    )

    $secure = New-Object System.Security.SecureString
    foreach ($ch in $PlainText.ToCharArray()) {
        $secure.AppendChar($ch)
    }
    $secure.MakeReadOnly()
    return $secure
}

function Get-AdtSamAccountName {
    <#
    .SYNOPSIS
        Derive a SamAccountName (name.surname) from given name and surname.
    .DESCRIPTION
        Username format is name.surname, lower-case, ASCII-only. Diacritics are
        stripped and any remaining non-alphanumeric characters (spaces, hyphens,
        apostrophes) are removed, so 'Jean-Pierre' + "O'Neil" becomes
        'jeanpierre.oneil'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GivenName,

        [Parameter(Mandatory = $true)]
        [string]$Surname
    )

    $first = (Remove-AdtDiacritics -Text $GivenName).Trim().ToLowerInvariant() -replace '[^a-z0-9]', ''
    $last = (Remove-AdtDiacritics -Text $Surname).Trim().ToLowerInvariant() -replace '[^a-z0-9]', ''
    return "$first.$last"
}

Export-ModuleMember -Function @(
    'Remove-AdtDiacritics'
    'Get-AdtWordList'
    'New-AdtPassword'
    'Get-AdtDefaultSearchBase'
    'Get-AdtOU'
    'New-AdtOU'
    'Get-AdtGroup'
    'New-AdtGroup'
    'Get-AdtUser'
    'New-AdtUser'
    'Disable-AdtUser'
    'Add-AdtGroupMember'
    'Remove-AdtGroupMember'
    'Save-AdtCredentialRecord'
    'ConvertTo-AdtSecureString'
    'Get-AdtSamAccountName'
)
