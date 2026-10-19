#Requires -Version 5.1
<#
    Pester tests for lib/AdTools/AdTools.psm1.

    These run on Linux under pwsh 7 in CI (no live AD). The ActiveDirectory
    cmdlets do not exist there, so BeforeAll defines parameter-compatible stub
    functions; Pester then mocks those with -ModuleName AdTools so the module
    under test resolves them.

    No credentials, hosts, or DNs are committed. Mocked objects use a
    placeholder lab domain.
#>

# The AD cmdlet stubs below declare the real parameter surface so Pester's
# -ParameterFilter can assert on it; their bodies are intentionally empty.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'AD stub parameters exist for Pester -ParameterFilter; bodies are empty by design.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = 'Remove-ADGroupMember stub declares SupportsShouldProcess so the module can call it with -Confirm:$false.')]
param()

BeforeAll {
    # --- ActiveDirectory cmdlet stubs (PS 5.1 + PS 7 compatible) -------------
    # Defined in the global scope so the AdTools module can resolve them when
    # Pester injects mocks via -ModuleName.
    function global:Get-ADDomain {
        [CmdletBinding()]
        param()
    }

    function global:Get-ADOrganizationalUnit {
        [CmdletBinding()]
        param(
            [string]$Filter,
            [string]$SearchBase,
            [string]$SearchScope
        )
    }

    function global:New-ADOrganizationalUnit {
        [CmdletBinding()]
        param(
            [string]$Name,
            [string]$Path,
            [bool]$ProtectedFromAccidentalDeletion
        )
    }

    function global:Get-ADGroup {
        [CmdletBinding()]
        param(
            [string]$Filter,
            [string]$SearchBase,
            [string]$SearchScope
        )
    }

    function global:New-ADGroup {
        [CmdletBinding()]
        param(
            [string]$Name,
            [string]$Path,
            [string]$GroupScope,
            [string]$GroupCategory
        )
    }

    function global:Get-ADUser {
        [CmdletBinding()]
        param(
            [string]$Identity,
            [string[]]$Properties
        )
    }

    function global:New-ADUser {
        [CmdletBinding()]
        param(
            [string]$Name,
            [string]$SamAccountName,
            [string]$UserPrincipalName,
            [string]$GivenName,
            [string]$Surname,
            [string]$DisplayName,
            [string]$Path,
            [securestring]$AccountPassword,
            [bool]$Enabled,
            [bool]$ChangePasswordAtLogon
        )
    }

    function global:Disable-ADAccount {
        [CmdletBinding()]
        param([string]$Identity)
    }

    function global:Add-ADGroupMember {
        [CmdletBinding()]
        param(
            [string]$Identity,
            [string[]]$Members
        )
    }

    function global:Remove-ADGroupMember {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param(
            [string]$Identity,
            [string[]]$Members
        )
    }

    # Move-ADObject is stubbed so tests can assert it is NEVER called (archive
    # = disable only).
    function global:Move-ADObject {
        [CmdletBinding()]
        param(
            [string]$Identity,
            [string]$TargetPath
        )
    }

    Import-Module "$PSScriptRoot/../lib/AdTools/AdTools.psd1" -Force
}

AfterAll {
    Remove-Module AdTools -Force -ErrorAction SilentlyContinue
    foreach ($cmd in @(
            'Get-ADDomain', 'Get-ADOrganizationalUnit', 'New-ADOrganizationalUnit',
            'Get-ADGroup', 'New-ADGroup', 'Get-ADUser', 'New-ADUser',
            'Disable-ADAccount', 'Add-ADGroupMember', 'Remove-ADGroupMember',
            'Move-ADObject'
        )) {
        Remove-Item -Path "function:global:$cmd" -ErrorAction SilentlyContinue
    }
}

Describe 'Remove-AdtDiacritics' {
    It 'strips common French accents' {
        Remove-AdtDiacritics -Text 'fenêtre' | Should -Be 'fenetre'
    }

    It 'strips circumflex and cedilla' {
        Remove-AdtDiacritics -Text 'châssis' | Should -Be 'chassis'
        Remove-AdtDiacritics -Text 'gâche' | Should -Be 'gache'
    }

    It 'maps the OE ligature to oe' {
        Remove-AdtDiacritics -Text 'nœud' | Should -Be 'noeud'
    }

    It 'returns an empty string unchanged' {
        Remove-AdtDiacritics -Text '' | Should -Be ''
    }
}

Describe 'Get-AdtWordList' {
    It 'returns exactly 60 words' {
        @(Get-AdtWordList).Count | Should -Be 60
    }

    It 'returns only 4-7 letter lowercase ASCII words' {
        foreach ($w in Get-AdtWordList) {
            $w | Should -Match '^[a-z]{4,7}$'
        }
    }

    It 'contains no duplicates' {
        $words = @(Get-AdtWordList)
        ($words | Select-Object -Unique).Count | Should -Be $words.Count
    }
}

Describe 'New-AdtPassword' {
    BeforeEach {
        $script:random = New-Object System.Random 42
        $script:wordList = @('porte', 'vitre', 'chassis', 'bois')
    }

    It 'generates a 10-character password' {
        $p = New-AdtPassword -Random $script:random -WordList $script:wordList
        $p.Length | Should -Be 10
        $p.Password.Length | Should -Be 10
    }

    It 'uses the format Word + digits + trailing special' {
        $p = New-AdtPassword -Random $script:random -WordList $script:wordList
        $p.Password | Should -Match '^[A-Z][a-z]+\d+[!#$%&*?@+=-]$'
    }

    It 'always has at least 2 digits' {
        foreach ($seed in 1..25) {
            $p = New-AdtPassword -Random (New-Object System.Random $seed) -WordList $script:wordList
            ($p.Password -replace '[^\d]', '').Length | Should -BeGreaterOrEqual 2
        }
    }

    It 'is deterministic for a given seed' {
        $a = New-AdtPassword -Random (New-Object System.Random 7) -WordList $script:wordList
        $b = New-AdtPassword -Random (New-Object System.Random 7) -WordList $script:wordList
        $a.Password | Should -Be $b.Password
    }

    It 'produces different passwords for different seeds' {
        $a = New-AdtPassword -Random (New-Object System.Random 1) -WordList $script:wordList
        $b = New-AdtPassword -Random (New-Object System.Random 2) -WordList $script:wordList
        $a.Password | Should -Not -Be $b.Password
    }

    It 'uses only the provided word list' {
        $p = New-AdtPassword -Random $script:random -WordList $script:wordList
        $p.Word | Should -BeIn $script:wordList
    }

    It 'throws when the word list is empty' {
        { New-AdtPassword -WordList @() } | Should -Throw
    }
}

Describe 'New-AdtOU' {
    BeforeEach {
        Mock -ModuleName AdTools New-ADOrganizationalUnit { }
    }

    It 'creates the OU when not using -WhatIf' {
        $r = New-AdtOU -Name 'Atelier' -ParentPath 'DC=lab,DC=example'
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AdTools New-ADOrganizationalUnit -Times 1 -Exactly
    }

    It 'does not create the OU with -WhatIf' {
        $r = New-AdtOU -Name 'Atelier' -ParentPath 'DC=lab,DC=example' -WhatIf
        $r.Success | Should -BeFalse
        Should -Not -Invoke -ModuleName AdTools New-ADOrganizationalUnit
    }
}

Describe 'New-AdtGroup' {
    BeforeEach {
        Mock -ModuleName AdTools New-ADGroup { }
    }

    It 'creates a Global Security group by default' {
        $r = New-AdtGroup -Name 'Menuiserie' -Path 'OU=Atelier,DC=lab,DC=example'
        $r.Success | Should -BeTrue
        $r.GroupScope | Should -Be 'Global'
        $r.GroupCategory | Should -Be 'Security'
        Should -Invoke -ModuleName AdTools New-ADGroup -Times 1 -Exactly -ParameterFilter {
            $GroupScope -eq 'Global' -and $GroupCategory -eq 'Security'
        }
    }

    It 'does not create the group with -WhatIf' {
        $r = New-AdtGroup -Name 'Menuiserie' -Path 'OU=Atelier,DC=lab,DC=example' -WhatIf
        $r.Success | Should -BeFalse
        Should -Not -Invoke -ModuleName AdTools New-ADGroup
    }
}

Describe 'New-AdtUser' {
    BeforeEach {
        Mock -ModuleName AdTools Get-ADDomain { [pscustomobject]@{ DNSRoot = 'lab.example'; DistinguishedName = 'DC=lab,DC=example' } }
        Mock -ModuleName AdTools New-ADUser { }
        Mock -ModuleName AdTools Add-ADGroupMember { }
    }

    It 'creates the user with ChangePasswordAtLogon set to false' {
        $pw = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        $r = New-AdtUser -SamAccountName 'richard.pearsall' -GivenName 'richard' `
            -Surname 'pearsall' -Path 'OU=Atelier,DC=lab,DC=example' -AccountPassword $pw
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AdTools New-ADUser -Times 1 -Exactly -ParameterFilter {
            $SamAccountName -eq 'richard.pearsall' -and $ChangePasswordAtLogon -eq $false -and $Enabled -eq $true
        }
    }

    It 'adds the user to each requested group' {
        $pw = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        New-AdtUser -SamAccountName 'richard.pearsall' -GivenName 'richard' `
            -Surname 'pearsall' -Path 'OU=Atelier,DC=lab,DC=example' -AccountPassword $pw `
            -Group @('Menuiserie', 'Vitrage')
        Should -Invoke -ModuleName AdTools Add-ADGroupMember -Times 2 -Exactly
    }

    It 'does not create the user with -WhatIf' {
        $pw = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        $r = New-AdtUser -SamAccountName 'richard.pearsall' -GivenName 'richard' `
            -Surname 'pearsall' -Path 'OU=Atelier,DC=lab,DC=example' -AccountPassword $pw -WhatIf
        $r.Success | Should -BeFalse
        Should -Not -Invoke -ModuleName AdTools New-ADUser
        Should -Not -Invoke -ModuleName AdTools Add-ADGroupMember
    }
}

Describe 'Disable-AdtUser (archive = disable only)' {
    BeforeEach {
        Mock -ModuleName AdTools Disable-ADAccount { }
        Mock -ModuleName AdTools Move-ADObject { }
    }

    It 'disables the account' {
        $r = Disable-AdtUser -Identity 'richard.pearsall'
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AdTools Disable-ADAccount -Times 1 -Exactly
    }

    It 'never moves the user to an archive OU' {
        Disable-AdtUser -Identity 'richard.pearsall'
        Should -Not -Invoke -ModuleName AdTools Move-ADObject
    }

    It 'does not disable with -WhatIf' {
        $r = Disable-AdtUser -Identity 'richard.pearsall' -WhatIf
        $r.Success | Should -BeFalse
        Should -Not -Invoke -ModuleName AdTools Disable-ADAccount
    }
}

Describe 'Group membership changes' {
    BeforeEach {
        Mock -ModuleName AdTools Add-ADGroupMember { }
        Mock -ModuleName AdTools Remove-ADGroupMember { }
    }

    It 'adds a user to a group' {
        $r = Add-AdtGroupMember -Identity 'Menuiserie' -Members 'richard.pearsall'
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AdTools Add-ADGroupMember -Times 1 -Exactly
    }

    It 'removes a user from a group' {
        $r = Remove-AdtGroupMember -Identity 'Menuiserie' -Members 'richard.pearsall'
        $r.Success | Should -BeTrue
        Should -Invoke -ModuleName AdTools Remove-ADGroupMember -Times 1 -Exactly
    }

    It 'does not change membership with -WhatIf' {
        Add-AdtGroupMember -Identity 'Menuiserie' -Members 'richard.pearsall' -WhatIf
        Remove-AdtGroupMember -Identity 'Menuiserie' -Members 'richard.pearsall' -WhatIf
        Should -Not -Invoke -ModuleName AdTools Add-ADGroupMember
        Should -Not -Invoke -ModuleName AdTools Remove-ADGroupMember
    }
}

Describe 'Save-AdtCredentialRecord' {
    BeforeEach {
        $script:tempDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "adt-test-$([System.Guid]::NewGuid().ToString('N'))"
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:tempDir) {
            Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'writes a file named ad-tools-created-users-YYYYMMDD-HHMM.txt' {
        $records = @(
            [pscustomobject]@{ SamAccountName = 'richard.pearsall'; Password = 'Porte8402!' }
        )
        $r = Save-AdtCredentialRecord -Record $records -Directory $script:tempDir -Timestamp '20261016-0930'
        $r.Success | Should -BeTrue
        Split-Path -Path $r.Path -Leaf | Should -Be 'ad-tools-created-users-20261016-0930.txt'
        Test-Path -LiteralPath $r.Path | Should -BeTrue
    }

    It 'records username and password for each user' {
        $records = @(
            [pscustomobject]@{ SamAccountName = 'richard.pearsall'; Password = 'Porte8402!' },
            [pscustomobject]@{ SamAccountName = 'marie.durand'; Password = 'Vitre5517#' }
        )
        $r = Save-AdtCredentialRecord -Record $records -Directory $script:tempDir -Timestamp '20261016-0930'
        $content = Get-Content -LiteralPath $r.Path
        $content | Should -Contain 'username richard.pearsall'
        $content | Should -Contain 'password Porte8402!'
        $content | Should -Contain 'username marie.durand'
        $content | Should -Contain 'password Vitre5517#'
        $r.Count | Should -Be 2
    }

    It 'does not write the file with -WhatIf' {
        $records = @(
            [pscustomobject]@{ SamAccountName = 'richard.pearsall'; Password = 'Porte8402!' }
        )
        $r = Save-AdtCredentialRecord -Record $records -Directory $script:tempDir -Timestamp '20261016-0930' -WhatIf
        $r.Success | Should -BeFalse
        Test-Path -LiteralPath $r.Path | Should -BeFalse
    }

    It 'defaults the record directory to the operator Documents folder' {
        $records = @(
            [pscustomobject]@{ SamAccountName = 'richard.pearsall'; Password = 'Porte8402!' }
        )
        $documents = [System.Environment]::GetFolderPath(
            [System.Environment+SpecialFolder]::MyDocuments)

        # -WhatIf so the assertion does not litter the real Documents folder.
        $r = Save-AdtCredentialRecord -Record $records -Timestamp '20261016-0930' -WhatIf

        Split-Path -Path $r.Path -Parent | Should -Be $documents
        $r.Success | Should -BeFalse
    }
}

Describe 'ConvertTo-AdtSecureString' {
    It 'returns a SecureString' {
        $secure = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        $secure | Should -BeOfType [securestring]
    }

    It 'round-trips the original value' {
        $secure = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $plain | Should -Be 'Porte8402!'
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    It 'returns a read-only SecureString' {
        $secure = ConvertTo-AdtSecureString -PlainText 'Porte8402!'
        $secure.IsReadOnly() | Should -BeTrue
    }
}

Describe 'Get-AdtSamAccountName' {
    It 'joins given name and surname with a dot' {
        Get-AdtSamAccountName -GivenName 'Richard' -Surname 'Pearsall' | Should -Be 'richard.pearsall'
    }

    It 'strips diacritics and lowercases' {
        Get-AdtSamAccountName -GivenName 'René' -Surname 'Chêne' | Should -Be 'rene.chene'
    }

    It 'removes spaces, hyphens and apostrophes' {
        Get-AdtSamAccountName -GivenName 'Jean-Pierre' -Surname "O'Neil" | Should -Be 'jeanpierre.oneil'
    }

    It 'handles a multi-part surname' {
        Get-AdtSamAccountName -GivenName 'Marie' -Surname 'de la Croix' | Should -Be 'marie.delacroix'
    }
}
