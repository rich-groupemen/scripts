#Requires -Version 7
# Pester tests for bin/greet.ps1.
#
# Run: make test-ps

BeforeAll {
    # Dot-source the script's functions by invoking with known input is not
    # possible for a script; instead test the observable behavior via pwsh.
    $script:scriptPath = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'bin', 'greet.ps1'
}

Describe 'greet.ps1' {
    It 'greets with the default name' {
        $output = & $scriptPath 6>&1 | Out-String
        $output | Should -Match 'Hello, World!'
    }

    It 'greets the given name' {
        $output = & $scriptPath -Name Pester 6>&1 | Out-String
        $output | Should -Match 'Hello, Pester!'
    }

    It 'uppercases with -Shout' {
        $output = & $scriptPath -Name Pester -Shout 6>&1 | Out-String
        $output | Should -Match 'HELLO, PESTER!'
    }
}
