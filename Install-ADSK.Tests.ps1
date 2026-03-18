$WhatIfPreference = $false

BeforeAll {
    $sutPath = Join-Path -Path $PSScriptRoot -ChildPath 'Install-ADSK.ps1'

    if (-not (Get-Command -Name Set-InstallContext -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Set-InstallContext' -Value {
            param(
                [hashtable]$Context
            )
        }
    }

    if (-not (Get-Command -Name Write-InstallLog -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Write-InstallLog' -Value {
            param(
                [string]$Text,
                [switch]$Fail,
                [switch]$Info
            )
        }
    }

    if (-not (Get-Command -Name Set-AutodeskUpdate -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Set-AutodeskUpdate' -Value {
            param(
                [switch]$ShowOnly
            )
        }
    }

    if (-not (Get-Command -Name Install-CIDEONTool -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Install-CIDEONTool' -Value {
            param(
                [switch]$VaultToolboxStandard,
                [switch]$VaultToolboxPro,
                [switch]$VaultToolboxObserver,
                [switch]$VaultToolboxClassification
            )
        }
    }

    if (-not (Get-Command -Name Uninstall-Program -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Uninstall-Program' -Value {
            param(
                [string]$Publisher,
                [string]$DisplayName,
                [string]$FilterOperator
            )
        }
    }

    if (-not (Get-Command -Name Invoke-DeploymentWorkflow -ErrorAction SilentlyContinue)) {
        Set-Item -Path 'function:global:Invoke-DeploymentWorkflow' -Value {
            param(
                [scriptblock]$ModeHandler
            )
        }
    }

    @(
        'Copy-WIM',
        'Mount-WIM',
        'Install-AutodeskDeployment',
        'Install-Update',
        'Disable-VaultExtension',
        'Copy-Local',
        'Set-InventorProjectFile'
    ) | ForEach-Object {
        if (-not (Get-Command -Name $_ -ErrorAction SilentlyContinue)) {
            Set-Item -Path ('function:global:{0}' -f $_) -Value {
                param()
            }
        }
    }

    function Invoke-Sut {
        param(
            [Parameter(Mandatory)]
            [string]$Wim,
            [Parameter(Mandatory)]
            [ValidateSet('Install', 'Update', 'Uninstall')]
            [string]$Mode,
            [string]$Path = $PSScriptRoot,
            [string]$ModuleVersionPin
        )

        $invokeParams = @{
            WIM   = $Wim
            Mode  = $Mode
            Path  = $Path
            Quiet = $true
        }

        if (-not [string]::IsNullOrWhiteSpace($ModuleVersionPin)) {
            $invokeParams.ModuleVersionPin = $ModuleVersionPin
        }

        & $sutPath @invokeParams
    }
}

Describe 'Install-ADSK.ps1' -Tag 'Unit' {
    BeforeEach {
        $WhatIfPreference = $false

        Mock -CommandName Invoke-RestMethod -MockWith {
            throw 'GitHub API not reachable in unit test.'
        }

        Mock -CommandName Get-AuthenticodeSignature -MockWith {
            [PSCustomObject]@{
                Status = [System.Management.Automation.SignatureStatus]::Valid
            }
        }

        Mock -CommandName Import-Module -MockWith {}
        Mock -CommandName Set-InstallContext -MockWith {}
        Mock -CommandName Write-InstallLog -MockWith {}

        Mock -CommandName Copy-WIM -MockWith {}
        Mock -CommandName Mount-WIM -MockWith {}
        Mock -CommandName Install-AutodeskDeployment -MockWith {}
        Mock -CommandName Set-AutodeskUpdate -MockWith {}
        Mock -CommandName Install-Update -MockWith {}
        Mock -CommandName Install-CIDEONTool -MockWith {}
        Mock -CommandName Disable-VaultExtension -MockWith {}
        Mock -CommandName Copy-Local -MockWith {}
        Mock -CommandName Set-InventorProjectFile -MockWith {}
        Mock -CommandName Uninstall-Program -MockWith {
            param(
                [string]$Publisher,
                [string]$DisplayName,
                [string]$FilterOperator
            )
        }

        Mock -CommandName Invoke-DeploymentWorkflow -MockWith {
            param($ModeHandler)
            & $ModeHandler
        }
    }

    Context 'WIM parameter normalization' {
        It 'removes .wim suffix before passing context to module' {
            Invoke-Sut -Wim 'PDC_2026.wim' -Mode 'Install'

            Should -Invoke Set-InstallContext -Times 1 -Exactly
        }
    }

    Context 'Parameter validation' {
        It 'throws when ModuleVersionPin has invalid format' {
            { Invoke-Sut -Wim 'PDC_2026' -Mode 'Install' -ModuleVersionPin 'abc' } | Should -Throw
        }
    }

    Context 'Module loading fallback behavior' {
        It 'loads module from remote release assets when API and downloads succeed' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'CIDEON.AutodeskDeployment.psm1'
                            browser_download_url = 'https://example.invalid/CIDEON.AutodeskDeployment.psm1'
                        },
                        [pscustomobject]@{
                            name                 = 'CIDEON-CodeSigning.cer'
                            browser_download_url = 'https://example.invalid/CIDEON-CodeSigning.cer'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-WebRequest -MockWith {}

            Mock -CommandName New-Object -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'THUMBPRINT-UNIT-TEST'
                }
            } -ParameterFilter {
                $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Certificate2'
            }

            Mock -CommandName New-Object -MockWith {
                $store = [pscustomobject]@{ Certificates = @() }
                $store | Add-Member -MemberType ScriptMethod -Name Open -Value {
                    param([object]$flags)
                } -Force
                $store | Add-Member -MemberType ScriptMethod -Name Add -Value {
                    param([object]$certificate)
                    $this.Certificates = @($this.Certificates + $certificate)
                } -Force
                $store | Add-Member -MemberType ScriptMethod -Name Close -Value {
                } -Force
                $store
            } -ParameterFilter {
                $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Store'
            }

            Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'

            Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -match 'CIDEON[\\/]+Autodesk-Deployments[\\/]+CIDEON\.AutodeskDeployment\.psm1$' -and $Force -eq $true
            }
        }

        It 'throws when the module release asset is missing and no local fallback exists' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'CIDEON-CodeSigning.cer'
                            browser_download_url = 'https://example.invalid/CIDEON-CodeSigning.cer'
                        }
                    )
                }
            }

            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -like '*CIDEON.AutodeskDeployment.psm1'
            }

            {
                Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'
            } | Should -Throw '*Release asset ''CIDEON.AutodeskDeployment.psm1'' not found*'
        }

        It 'throws when the downloaded remote module signature is invalid and no local fallback exists' {
            Mock -CommandName Invoke-RestMethod -MockWith {
                [pscustomobject]@{
                    assets = @(
                        [pscustomobject]@{
                            name                 = 'CIDEON.AutodeskDeployment.psm1'
                            browser_download_url = 'https://example.invalid/CIDEON.AutodeskDeployment.psm1'
                        },
                        [pscustomobject]@{
                            name                 = 'CIDEON-CodeSigning.cer'
                            browser_download_url = 'https://example.invalid/CIDEON-CodeSigning.cer'
                        }
                    )
                }
            }

            Mock -CommandName Invoke-WebRequest -MockWith {}

            Mock -CommandName New-Object -MockWith {
                [pscustomobject]@{
                    Thumbprint = 'THUMBPRINT-UNIT-TEST'
                }
            } -ParameterFilter {
                $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Certificate2'
            }

            Mock -CommandName New-Object -MockWith {
                $store = [pscustomobject]@{ Certificates = @() }
                $store | Add-Member -MemberType ScriptMethod -Name Open -Value {
                    param([object]$flags)
                } -Force
                $store | Add-Member -MemberType ScriptMethod -Name Add -Value {
                    param([object]$certificate)
                    $this.Certificates = @($this.Certificates + $certificate)
                } -Force
                $store | Add-Member -MemberType ScriptMethod -Name Close -Value {
                } -Force
                $store
            } -ParameterFilter {
                $TypeName -eq 'System.Security.Cryptography.X509Certificates.X509Store'
            }

            Mock -CommandName Get-AuthenticodeSignature -MockWith {
                [PSCustomObject]@{
                    Status = [System.Management.Automation.SignatureStatus]::NotTrusted
                }
            }

            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -like '*CIDEON.AutodeskDeployment.psm1'
            }

            {
                Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'
            } | Should -Throw '*Module signature is invalid. Status: NotTrusted*'
        }

        It 'throws when remote loading fails and no local fallback module exists' {
            Mock -CommandName Test-Path -MockWith { $false } -ParameterFilter {
                $Path -like '*CIDEON.AutodeskDeployment.psm1'
            }

            {
                Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'
            } | Should -Throw '*Failed to load module from remote and no local fallback found*'
        }

        It 'imports local fallback module when remote loading fails but local module is present' {
            Mock -CommandName Test-Path -MockWith { $true } -ParameterFilter {
                $Path -like '*CIDEON.AutodeskDeployment.psm1'
            }

            Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'

            Should -Invoke Import-Module -Times 1 -Exactly -ParameterFilter {
                $Name -like '*CIDEON.AutodeskDeployment.psm1' -and $Force -eq $true
            }
        }
    }

    Context 'Workflow mode: Install' {
        It 'runs installation steps including tools, update and local copy' {
            Invoke-Sut -Wim 'PDC_2026' -Mode 'Install'

            Should -Invoke Copy-WIM -Times 1 -Exactly
            Should -Invoke Mount-WIM -Times 1 -Exactly
            Should -Invoke Install-AutodeskDeployment -Times 1 -Exactly
            Should -Invoke Set-AutodeskUpdate -Times 1 -Exactly
            Should -Invoke Install-Update -Times 1 -Exactly
            Should -Invoke Install-CIDEONTool -Times 1 -Exactly
            Should -Invoke Disable-VaultExtension -Times 1 -Exactly
            Should -Invoke Copy-Local -Times 1 -Exactly
            Should -Invoke Set-InventorProjectFile -Times 1 -Exactly
            Should -Invoke Uninstall-Program -Times 0 -Exactly
        }
    }

    Context 'Workflow mode: Update' {
        It 'mounts deployment and only applies update/local copy operations' {
            Invoke-Sut -Wim 'PDC_2026' -Mode 'Update'

            Should -Invoke Mount-WIM -Times 1 -Exactly
            Should -Invoke Install-Update -Times 1 -Exactly
            Should -Invoke Copy-Local -Times 1 -Exactly
            Should -Invoke Copy-WIM -Times 0 -Exactly
            Should -Invoke Install-AutodeskDeployment -Times 0 -Exactly
            Should -Invoke Install-CIDEONTool -Times 0 -Exactly
            Should -Invoke Uninstall-Program -Times 0 -Exactly
        }
    }

    Context 'Workflow mode: Uninstall' {
        It 'starts uninstall routine and skips install/update actions' {
            Invoke-Sut -Wim 'PDC_2026' -Mode 'Uninstall'

            Should -Invoke Uninstall-Program -Times 1

            Should -Invoke Copy-WIM -Times 0 -Exactly
            Should -Invoke Mount-WIM -Times 0 -Exactly
            Should -Invoke Install-Update -Times 0 -Exactly
        }
    }
}
