@{
    RootModule = 'AdTools.psm1'
    ModuleVersion = '0.1.0'
    GUID = '6f1b7c4e-2d5a-4c9e-9f3b-8a1d2e6f0c7b'
    Author = 'richpea'
    CompanyName = 'Groupement Menil'
    Copyright = '(c) Groupement Menil. Lab use only.'
    Description = 'AD Tools domain logic for the interactive OU/user/group manager. Windows PowerShell 5.1.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
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
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('ActiveDirectory', 'Lab', 'PS5.1')
            ProjectUri = ''
        }
    }
}
