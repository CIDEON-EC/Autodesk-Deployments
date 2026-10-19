$WhatIfPreference = $false

BeforeAll {
    $sutPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Copy-Local.ps1'
    $global:CopyLocalTrustedThumbprint = '53D03841EC43C1C545F56919F9A6AEF0C7D2E783'

    # Stubs so Pester can mock module functions and the script-local store helper
    @('Set-InstallContext', 'Copy-Local', 'Add-CertificateToStoreIfMissing') | ForEach-Object {
        if (-not (Get-Command -Name $_ -ErrorAction SilentlyContinue)) {
            Set-Item -Path ('function:global:{0}' -f $_) -Value { param() }
        }
    }

    function Invoke-Sut {
        & $sutPath -Path $TestDrive
    }

    function New-SignatureResult {
        param(
            [System.Management.Automation.SignatureStatus]$Status = 'Valid',
            [string]$Thumbprint = $global:CopyLocalTrustedThumbprint
        )

        [pscustomobject]@{
            Status            = $Status
            StatusMessage     = $null
            SignerCertificate = [pscustomobject]@{ Thumbprint = $Thumbprint }
        }
    }
}

AfterAll {
    Remove-Item -Path 'function:global:Add-CertificateToStoreIfMissing' -ErrorAction SilentlyContinue
    Remove-Variable -Name CopyLocalTrustedThumbprint -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Copy-Local.ps1 module loader' -Tag 'Unit' {
    BeforeEach {
        $WhatIfPreference = $false

        Mock -CommandName Invoke-RestMethod -MockWith {
            [pscustomobject]@{
                assets = @(
                    [pscustomobject]@{ name = 'CIDEON.AutodeskDeployment.psm1'; browser_download_url = 'https://example.invalid/CIDEON.AutodeskDeployment.psm1' },
                    [pscustomobject]@{ name = 'CIDEON-CodeSigning.cer'; browser_download_url = 'https://example.invalid/CIDEON-CodeSigning.cer' }
                )
            }
        }
        Mock -CommandName Invoke-WebRequest -MockWith {}
        Mock -CommandName New-Object -MockWith {
            [pscustomobject]@{ Thumbprint = $global:CopyLocalTrustedThumbprint; Subject = 'CN=CIDEON-EC Code Signing' }
        } -ParameterFilter { $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Certificate2' }
        Mock -CommandName Add-CertificateToStoreIfMissing -MockWith {}
        Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult }
        Mock -CommandName Import-Module -MockWith {}
        Mock -CommandName Set-InstallContext -MockWith {}
        Mock -CommandName Copy-Local -MockWith {}
        Mock -CommandName Write-Warning -MockWith {}
        # No local fallback unless a test enables it
        Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter { $Path -like '*CIDEON.AutodeskDeployment.psm1' }
    }

    It 'imports the downloaded module when the certificate is pinned and the signature is Valid' {
        Invoke-Sut

        Should -Invoke Add-CertificateToStoreIfMissing -Times 1 -Exactly
        Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
            $Name -match 'CIDEON[\\/]+Autodesk-Deployments[\\/]+CIDEON\.AutodeskDeployment\.psm1$' -and $Force -eq $true
        }
        Should -Invoke Copy-Local -Times 1 -Exactly
    }

    It 'rejects a downloaded certificate whose thumbprint is not pinned before adding it to the store' {
        Mock -CommandName New-Object -MockWith {
            [pscustomobject]@{ Thumbprint = '0000000000000000000000000000000000000000'; Subject = 'CN=Unexpected Code Signing' }
        } -ParameterFilter { $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Certificate2' }

        { Invoke-Sut } | Should -Throw '*certificate thumbprint*is not trusted*'

        Should -Invoke Add-CertificateToStoreIfMissing -Times 0 -Exactly
        Should -Invoke Import-Module -Times 0 -Exactly
    }

    It 'rejects a module whose signer thumbprint is not pinned' {
        Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult -Thumbprint 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' }

        { Invoke-Sut } | Should -Throw '*Module signer thumbprint*is not trusted*'

        Should -Invoke Import-Module -Times 0 -Exactly
    }

    It 'rejects a HashMismatch signature even when the certificate store is not writable' {
        Mock -CommandName Add-CertificateToStoreIfMissing -MockWith { throw 'Access denied' }
        Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult -Status HashMismatch }

        { Invoke-Sut } | Should -Throw '*Module signature is invalid. Status: HashMismatch*'

        Should -Invoke Import-Module -Times 0 -Exactly
    }

    It 'rejects a NotTrusted chain when the certificate store is writable' {
        Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult -Status NotTrusted }

        { Invoke-Sut } | Should -Throw '*Module signature is invalid. Status: NotTrusted*'
    }

    It 'imports a pinned module with a NotTrusted chain when the certificate store is not writable' {
        Mock -CommandName Add-CertificateToStoreIfMissing -MockWith { throw 'Access denied' }
        Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult -Status NotTrusted }

        Invoke-Sut

        Should -Invoke Write-Warning -Times 1 -Exactly
        Should -Invoke Import-Module -Times 1 -Exactly
    }

    Context 'Local fallback' {
        BeforeEach {
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'GitHub API not reachable in unit test.' }
            Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter { $Path -like '*CIDEON.AutodeskDeployment.psm1' }
        }

        It 'imports the local fallback module when its signer is pinned' {
            Invoke-Sut

            Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -eq (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'CIDEON.AutodeskDeployment.psm1')
            }
        }

        It 'rejects the local fallback module when its signer is not pinned' {
            Mock -CommandName Get-AuthenticodeSignature -MockWith { New-SignatureResult -Thumbprint 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF' }

            { Invoke-Sut } | Should -Throw '*fallback module*is also unusable*Module signer thumbprint*is not trusted*'

            Should -Invoke Import-Module -Times 0 -Exactly
        }

        It 'throws when no local fallback module exists' {
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter { $Path -like '*CIDEON.AutodeskDeployment.psm1' }

            { Invoke-Sut } | Should -Throw '*Remote module loading failed*no local fallback found*'
        }
    }
}
