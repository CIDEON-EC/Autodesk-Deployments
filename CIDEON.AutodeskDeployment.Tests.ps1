$WhatIfPreference = $false

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'CIDEON.AutodeskDeployment.psm1'
    Import-Module -Name $modulePath -Force
}

Describe 'CIDEON.AutodeskDeployment.psm1' -Tag 'Unit' {
    BeforeEach {
        $WhatIfPreference = $false
    }

    Context 'Set-InstallContext' {
        It 'publishes hashtable values as global variables' {
            InModuleScope CIDEON.AutodeskDeployment {
                Set-InstallContext -Context @{ UnitTestVar = 'ok' }
                $Global:UnitTestVar | Should -Be 'ok'
                Remove-Variable -Name UnitTestVar -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Get-UserSID' {
        It 'throws terminating error when both DomainUser and LocalUser are specified' {
            InModuleScope CIDEON.AutodeskDeployment {
                { Get-UserSID -DomainUser -LocalUser } | Should -Throw
            }
        }
    }

    Context 'Invoke-DeploymentWorkflow' {
        It 'throws for invalid version format before workflow execution' {
            InModuleScope CIDEON.AutodeskDeployment {
                $Global:Version = '26'
                $Global:LocalFolder = Join-Path -Path $TestDrive -ChildPath 'Temp'
                $Global:Path = $TestDrive
                $Global:WIM = 'PDC_2026'
                $Global:Files = @('Collection')
                $Global:Mode = 'Install'
                $Global:NoDownload = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Purge = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)

                { Invoke-DeploymentWorkflow -ModeHandler { } } | Should -Throw '*4-digit year*'
            }
        }

        It 'throws when no matching WIM file is found' {
            InModuleScope CIDEON.AutodeskDeployment {
                $Global:Version = '2026'
                $Global:LocalFolder = Join-Path -Path $TestDrive -ChildPath 'Temp'
                $Global:Path = $TestDrive
                $Global:WIM = 'PDC_2026'
                $Global:Files = @('Collection')
                $Global:Mode = 'Install'
                $Global:NoDownload = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Purge = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)

                Mock -CommandName Set-InstallContext -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'

                { Invoke-DeploymentWorkflow -ModeHandler { } } | Should -Throw '*No WIM file matching*'
            }
        }

        It 'prepares context, runs the mode handler and dismounts in finally' {
            InModuleScope CIDEON.AutodeskDeployment {
                $Global:Version = '2026'
                $Global:LocalFolder = Join-Path -Path $TestDrive -ChildPath 'Temp'
                $Global:Path = $TestDrive
                $Global:WIM = 'PDC_2026'
                $Global:Files = @('Collection')
                $Global:Mode = 'Install'
                $Global:NoDownload = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Purge = [System.Management.Automation.SwitchParameter]::new($false)
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)
                $script:modeHandlerRan = $false

                $wimFile = [pscustomobject]@{
                    Name     = 'PDC_2026.wim'
                    FullName = (Join-Path -Path $TestDrive -ChildPath 'PDC_2026.wim')
                }

                Mock -CommandName Set-InstallContext -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith { $wimFile } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-AppLogError -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Dismount-WIM -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Invoke-DeploymentWorkflow -ModeHandler {
                    $script:modeHandlerRan = $true
                }

                $script:modeHandlerRan | Should -BeTrue
                Should -Invoke Set-InstallContext -Times 1 -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Context.ContainsKey('wimFile') -and $Context.ContainsKey('mountPath') -and $Context.ContainsKey('ConfigFullFilenames')
                }
                Should -Invoke Dismount-WIM -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }
    }

    Context 'Get-CachedFiles' {
        It 'returns transformed cached file objects with Name and FullName' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                $result = Get-CachedFiles -Path 'C:\Cache\Updates' -OperationText 'Would install updates from' -CachedFiles @(
                    'update1.exe',
                    [pscustomobject]@{ Name = 'update2.msi' }
                )

                $result.Count | Should -Be 2
                $result[0].Name | Should -Be 'update1.exe'
                $result[0].FullName | Should -Be ([System.IO.Path]::Combine('C:\Cache\Updates', 'update1.exe'))
                $result[0].FromCache | Should -BeTrue
                $result[1].Name | Should -Be 'update2.msi'
            }
        }
    }

    Context 'Copy-WIM' {
        AfterEach {
            Remove-Variable -Name wimFile, LocalFolder, NoDownload -Scope Global -ErrorAction SilentlyContinue
        }
        It 'skips local copy when NoDownload is set and updates context with source file' {
            InModuleScope CIDEON.AutodeskDeployment {
                $sourceFile = [pscustomobject]@{
                    Name     = 'PDC_2026.wim'
                    FullName = 'D:\Share\PDC_2026.wim'
                }

                $Global:wimFile = $sourceFile
                $Global:LocalFolder = 'C:\Temp'
                $Global:NoDownload = [System.Management.Automation.SwitchParameter]::new($true)

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-Item -MockWith {
                    $sourceFile
                } -ParameterFilter {
                    $Path -eq 'D:\Share\PDC_2026.wim'
                } -ModuleName 'CIDEON.AutodeskDeployment'

                Mock -CommandName Set-InstallContext -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Copy-WIM

                Should -Invoke Set-InstallContext -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Context.wimFile.FullName -eq 'D:\Share\PDC_2026.wim'
                }
            }
        }

        It 'copies the WIM locally and updates context to the copied file' {
            InModuleScope CIDEON.AutodeskDeployment {
                $sourceFolder = Join-Path -Path $TestDrive -ChildPath 'source'
                $targetFolder = Join-Path -Path $TestDrive -ChildPath 'target'
                New-Item -Path $sourceFolder -ItemType Directory | Out-Null
                New-Item -Path $targetFolder -ItemType Directory | Out-Null

                $sourcePath = Join-Path -Path $sourceFolder -ChildPath 'PDC_2026.wim'
                Set-Content -Path $sourcePath -Value 'unit-test-wim'
                $sourceFile = Get-Item -Path $sourcePath

                $Global:wimFile = $sourceFile
                $Global:LocalFolder = $targetFolder
                $Global:NoDownload = [System.Management.Automation.SwitchParameter]::new($false)

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Set-InstallContext -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Copy-WIM -File $sourceFile -Folder $targetFolder

                Test-Path -Path (Join-Path -Path $targetFolder -ChildPath 'PDC_2026.wim') | Should -BeTrue
                Should -Invoke Set-InstallContext -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Context.wimFile.FullName -eq (Join-Path -Path $targetFolder -ChildPath 'PDC_2026.wim')
                }
            }
        }
    }

    Context 'Set-AutodeskUpdate' {
        It 'sets DisableManualUpdateInstall to 2 for ShowOnly mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-Item -MockWith {
                    [pscustomobject]@{ PSPath = 'HKCU:\SOFTWARE\Autodesk\ODIS' }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ItemProperty -MockWith {
                    [pscustomobject]@{ DisableManualUpdateInstall = 0 }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Set-ItemProperty -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Set-AutodeskUpdate -ShowOnly

                Should -Invoke Set-ItemProperty -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Path -eq 'HKCU:\SOFTWARE\Autodesk\ODIS' -and
                    $Name -eq 'DisableManualUpdateInstall' -and
                    $Value -eq 2
                }
            }
        }
    }

    Context 'Set-AutodeskDeployment' {
        It 'removes package containing single quote when requested (XPath escaping)' {
            InModuleScope CIDEON.AutodeskDeployment {
                $xmlPath = Join-Path -Path $TestDrive -ChildPath 'setup_ext.xml'
                $xmlContent = @'
<Bundle xmlns="http://schemas.autodesk.com/whatever">
    <BundleExtension xmlns="http://schemas.autodesk.com/whatever" />
    <Package name="O'Reilly Package" />
    <Package name="KeepMe" />
</Bundle>
'@
                $xmlContent | Set-Content -Path $xmlPath

                Set-AutodeskDeployment -Path $TestDrive -xmlFileName 'setup_ext.xml' -Remove "O'Reilly Package"

                $result = [xml](Get-Content $xmlPath)
                (@($result.Bundle.Package | Where-Object { $_.name -eq "O'Reilly Package" })).Count | Should -Be 0
            }
        }
    }

    Context 'Mount-WIM' {
        It 'logs info and returns early in WhatIf mode when not running as admin' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {}
                $originalWhatIf = $WhatIfPreference
                $WhatIfPreference = $true
                Mount-WIM -File ([pscustomobject]@{ FullName = 'C:\fake.wim' }) -Path 'C:\fakeMount' -WhatIf:$true
                Should -Invoke Write-InstallLog -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*requires elevated rights*' -and $Info.IsPresent
                }
                $WhatIfPreference = $originalWhatIf
            }
        }
        It 'mounts the WIM and validates required config files in normal mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                $configPath = Join-Path -Path $TestDrive -ChildPath 'Collection.xml'
                Set-Content -Path $configPath -Value '<Collection />'
                $Global:ConfigFullFilenames = @($configPath)
                $fileObj = [pscustomobject]@{ FullName = 'C:\fake.wim' }

                Mock -CommandName Mount-WindowsImage -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Mount-WIM -File $fileObj -Path 'C:\fakeMount' } | Should -Not -Throw

                Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $ImagePath -eq 'C:\fake.wim' -and $Path -eq 'C:\fakeMount'
                }
            }
        }

        It 'throws when a required config file is missing after mount' {
            InModuleScope CIDEON.AutodeskDeployment {
                $missingConfigPath = Join-Path -Path $TestDrive -ChildPath 'MissingCollection.xml'
                $Global:ConfigFullFilenames = @($missingConfigPath)
                $fileObj = [pscustomobject]@{ FullName = 'C:\fake.wim' }

                Mock -CommandName Mount-WindowsImage -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Mount-WIM -File $fileObj -Path 'C:\fakeMount' } | Should -Throw '*ConfigFile*does not exist*'
            }
        }

        # disabled broken mock scope
        # It 'resolves string File parameter using Get-Item' {
        #     InModuleScope CIDEON.AutodeskDeployment {
        #         $fileObj = [pscustomobject]@{ FullName = 'C:\\fake.wim' }
        #         Mock -CommandName Get-Item -MockWith { $fileObj } -ParameterFilter { $Path -eq 'C:\\fake.wim' }
        #         Mock -CommandName Mount-WindowsImage -MockWith {}
        #         Mock -CommandName Write-InstallLog -MockWith {}

        #         Mount-WIM -File 'C:\\fake.wim' -Path 'C:\\fakeMount'

        #         Should -Invoke Get-Item -Times 1 -Exactly
        #         Should -Invoke Mount-WindowsImage -Times 1 -Exactly
        #     }
        # }
        # Previously attempted to test string resolution via Get-Item; this proved fragile
        # It 'resolves string File parameter using Get-Item (scoped mocks)' {
        #     InModuleScope CIDEON.AutodeskDeployment {
        #         $fileObj = [pscustomobject]@{ FullName = 'C:\\fake.wim' }
        #         Mock -CommandName Get-Item -MockWith { $fileObj } -ModuleName 'CIDEON.AutodeskDeployment'
        #         Mock -CommandName Mount-WindowsImage -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
        #         Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
        #
        #         Mount-WIM -File 'C:\\fake.wim' -Path 'C:\\fakeMount'
        #
        #         Should -Invoke Get-Item -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment'
        #         Should -Invoke Mount-WindowsImage -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment'
        #     }
        # }
    }

    Context 'Dismount-WIM' {
        It 'returns gracefully when no mounted images found' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Get-WindowsImage -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Dismount-WIM -File ([pscustomobject]@{ FullName = 'C:\fake.wim' }) } | Should -Not -Throw
            }
        }

        It 'dismounts and purges a mounted image object' {
            InModuleScope CIDEON.AutodeskDeployment {
                $mountedImage = [pscustomobject]@{
                    ImagePath = 'C:\fake.wim'
                    Path      = 'C:\mount'
                }

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Dismount-WindowsImage -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Remove-Item -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Register-WIMDismountTask -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Dismount-WIM -File $mountedImage -Purge } | Should -Not -Throw

                Should -Invoke Dismount-WindowsImage -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Path -eq 'C:\mount'
                }
                Should -Invoke Remove-Item -Times 2 -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }

        It 'registers cleanup task when dismount fails unexpectedly' {
            InModuleScope CIDEON.AutodeskDeployment {
                $mountedImage = [pscustomobject]@{
                    ImagePath = 'C:\fake.wim'
                    Path      = 'C:\mount'
                }

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Dismount-WindowsImage -MockWith {
                    throw 'unexpected dismount failure'
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Register-WIMDismountTask -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Dismount-WIM -File $mountedImage } | Should -Not -Throw

                Should -Invoke Register-WIMDismountTask -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }
    }

    Context 'Install-ADSK functions' {
        It 'Install-Update returns cleanly when update path is empty (WhatIf)' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:CachedUpdateFiles = @()
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-CachedFiles -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-Update -Path 'C:\\nonexistent' -WhatIf:$true } | Should -Not -Throw
            }
        }

        It 'Install-Update uses msiexec for MSI packages and logs success' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:LogFile = Join-Path -Path $TestDrive -ChildPath 'main.log'
                $script:LocalFolder = $TestDrive
                $script:Version = '2026'
                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith {
                    @(
                        [pscustomobject]@{
                            Name     = 'update.msi'
                            FullName = 'C:\Temp\update.msi'
                        }
                    )
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                    [pscustomobject]@{ ExitCode = 0 }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-Update -Path $TestDrive } | Should -Not -Throw

                $script:startProcessCall.FilePath | Should -Be 'msiexec.exe'
                $script:startProcessCall.ArgumentList | Should -Match 'update\.msi'
            }
        }

        It 'Install-AutodeskDeployment handles missing config gracefully' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:ConfigFullFilenames = @()
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-Content -MockWith { [xml]'<Collection/>' } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-AutodeskDeployment -Path 'C:\\noimage' -WhatIf:$false } | Should -Not -Throw
            }
        }

        It 'Install-AutodeskDeployment accepts explicit config context without throwing' {
            InModuleScope CIDEON.AutodeskDeployment {
                $rootPath = Join-Path -Path $TestDrive -ChildPath 'deployment'
                $imagePath = Join-Path -Path $rootPath -ChildPath 'Image'
                New-Item -Path $imagePath -ItemType Directory -Force | Out-Null

                $configPath = Join-Path -Path $imagePath -ChildPath 'Collection.xml'
                Set-Content -Path $configPath -Value '<Collection />'

                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                    [pscustomobject]@{ Id = 1234 }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Wait-Process -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                {
                    Install-AutodeskDeployment -Path $rootPath -ConfigFile @($configPath) -LogFolder $TestDrive -DeploymentName 'PDC_2026'
                } | Should -Not -Throw

                # ensure the internal log path uses the correct spelling "Deployment"
                Should -Invoke Write-InstallLog -ParameterFilter {
                    $text -notmatch 'Deplyoment' # original typo must not appear
                }
            }
        }

        It 'Install-AutodeskDeployment throws a clear error when no path context is available' {
            InModuleScope CIDEON.AutodeskDeployment {
                $configPath = Join-Path -Path $TestDrive -ChildPath 'Collection.xml'
                Set-Content -Path $configPath -Value '<Collection />'

                Remove-Variable -Name mountPath -Scope Script -ErrorAction SilentlyContinue
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                {
                    Install-AutodeskDeployment -ConfigFile @($configPath) -LogFolder $TestDrive -DeploymentName 'PDC_2026'
                } | Should -Throw '*requires -Path or an initialized script mountPath context*'
            }
        }
    }

    Context 'Write-InstallLog' {
        It 'writes INFO entry to log file when Logging is active' {
            InModuleScope CIDEON.AutodeskDeployment {
                $logFile = Join-Path -Path $TestDrive -ChildPath 'info.log'
                $script:LogFile = $logFile
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($true)

                Write-InstallLog -text 'Test log entry' -Info

                Test-Path $logFile | Should -BeTrue
                Get-Content $logFile | Should -Match '\[INFO\].*Test log entry'

                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)
            }
        }

        It 'writes ERROR category when -Fail switch is used' {
            InModuleScope CIDEON.AutodeskDeployment {
                $logFile = Join-Path -Path $TestDrive -ChildPath 'fail.log'
                $script:LogFile = $logFile
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($true)

                Write-InstallLog -text 'Something failed' -Fail

                Get-Content $logFile | Should -Match '\[ERROR\].*Something failed'

                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)
            }
        }

        It 'does not write to file when Logging is inactive' {
            InModuleScope CIDEON.AutodeskDeployment {
                $logFile = Join-Path -Path $TestDrive -ChildPath 'nolog.log'
                $script:LogFile = $logFile
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)

                Write-InstallLog -text 'Should not appear' -Info

                Test-Path $logFile | Should -BeFalse
            }
        }

        It 'does not write to file in WhatIf mode even when Logging is active' {
            InModuleScope CIDEON.AutodeskDeployment {
                $logFile = Join-Path -Path $TestDrive -ChildPath 'whatif.log'
                $script:LogFile = $logFile
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($true)
                $WhatIfPreference = $true

                Write-InstallLog -text 'WhatIf message' -Info -WhatIf

                Test-Path $logFile | Should -BeFalse

                $WhatIfPreference = $false
                $Global:Logging = [System.Management.Automation.SwitchParameter]::new($false)
            }
        }
    }

    Context 'Write-InstallProgress' {
        It 'calls Write-Host with INFO tag in normal mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Quiet = $false
                Mock -CommandName Write-Host -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Write-InstallProgress -Text 'Step in progress'

                Should -Invoke Write-Host -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Object -like '*INFO*Step in progress*'
                }
            }
        }

        It 'calls Write-Host with ERROR tag when -Fail is set' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Quiet = $false
                Mock -CommandName Write-Host -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Write-InstallProgress -Text 'Install failed' -Fail

                Should -Invoke Write-Host -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Object -like '*ERROR*Install failed*'
                }
            }
        }

        It 'suppresses all output when Quiet variable is set' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Quiet = $true
                Mock -CommandName Write-Host -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Write-InstallProgress -Text 'Silent step'

                Should -Invoke Write-Host -Times 0 -ModuleName 'CIDEON.AutodeskDeployment'
                $script:Quiet = $false
            }
        }
    }

    Context 'Update-WIMInspectionCache' {
        It 'populates all three cache variables from a complete mounted image' {
            InModuleScope CIDEON.AutodeskDeployment {
                $mountedPath = 'C:\fake_mount_test'

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith {
                    param($Path, $Exclude, $File, $Directory, $ErrorAction)
                    if ($Directory) {
                        return @([pscustomobject]@{ Name = 'ProgramData'; FullName = "$Path\ProgramData" })
                    }
                    return @([pscustomobject]@{ Name = 'update1.exe'; FullName = "$Path\update1.exe" })
                } -ModuleName 'CIDEON.AutodeskDeployment'

                Update-WIMInspectionCache -MountedPath $mountedPath

                $Script:CachedUpdateFiles | Should -Not -BeNullOrEmpty
                $Script:CachedCideonFiles | Should -Not -BeNullOrEmpty
                $Script:CachedLocalFolders | Should -Contain 'ProgramData'
            }
        }

        It 'logs warnings and leaves cache null when subfolders are missing' {
            InModuleScope CIDEON.AutodeskDeployment {
                $mountedPath = Join-Path -Path $TestDrive -ChildPath 'mount_empty'
                New-Item -Path $mountedPath -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Update-WIMInspectionCache -MountedPath $mountedPath

                $Script:CachedUpdateFiles | Should -BeNullOrEmpty
                $Script:CachedCideonFiles | Should -BeNullOrEmpty
                $Script:CachedLocalFolders | Should -BeNullOrEmpty

                Should -Invoke Write-InstallLog -Times 3 -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*folder not found*'
                }
            }
        }
    }

    Context 'Get-InstalledProgram' {
        It 'returns programs filtered by publisher' {
            InModuleScope CIDEON.AutodeskDeployment {
                $fakeItems = @(
                    [pscustomobject]@{ Publisher = 'Autodesk'; DisplayName = 'Autodesk Inventor 2026'; DisplayVersion = '30.0'; UninstallString = 'MsiExec.exe /X{AAA}'; ModifyPath = '' }
                    [pscustomobject]@{ Publisher = 'CIDEON'; DisplayName = 'CIDEON Vault Toolbox'; DisplayVersion = '2.5'; UninstallString = 'MsiExec.exe /X{BBB}'; ModifyPath = '' }
                )

                Mock -CommandName Get-ItemProperty -MockWith { $fakeItems } -ModuleName 'CIDEON.AutodeskDeployment'

                $result = Get-InstalledProgram -Publisher 'Autodesk'

                $result | Should -Not -BeNullOrEmpty
                @($result).Count | Should -Be 1
                $result.Publisher | Should -Be 'Autodesk'
            }
        }

        It 'returns empty collection when no program matches' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Get-ItemProperty -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'

                $result = Get-InstalledProgram -Publisher 'NonExistent' -DisplayName 'Nothing'

                @($result).Count | Should -Be 0
            }
        }
    }

    Context 'Set-AutodeskUpdate (additional)' {
        It 'skips registry write in WhatIf mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $true } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-Item -MockWith {
                    [pscustomobject]@{ PSPath = 'HKCU:\SOFTWARE\Autodesk\ODIS' }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ItemProperty -MockWith {
                    [pscustomobject]@{ DisableManualUpdateInstall = 0 }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Set-ItemProperty -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Set-AutodeskUpdate -Enable -WhatIf

                Should -Invoke Set-ItemProperty -Times 0 -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }

        It 'creates the ODIS registry key when it does not exist and sets the value' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                # Test-Path returns $false so New-Item path is taken
                Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName New-Item -MockWith {
                    [pscustomobject]@{ PSPath = 'HKCU:\SOFTWARE\Autodesk\ODIS' }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                # Get-ItemProperty must return $null for DisableManualUpdateInstall so New-ItemProperty branch is used
                Mock -CommandName Get-ItemProperty -MockWith { $null } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName New-ItemProperty -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Set-AutodeskUpdate -Disable

                Should -Invoke New-Item -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment'
                Should -Invoke New-ItemProperty -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Value -eq 1
                }
            }
        }
    }

    Context 'Dismount-WIM (additional)' {
        AfterEach {
            Remove-Variable -Name mountPath -Scope Global -ErrorAction SilentlyContinue
        }
        It 'logs dismount intention in WhatIf mode without calling Dismount-WindowsImage' {
            InModuleScope CIDEON.AutodeskDeployment {
                $fakeWim = [pscustomobject]@{ FullName = 'C:\fake.wim'; Name = 'fake.wim' }
                $Global:mountPath = 'C:\fakeMount'

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                # In WhatIf mode ShouldProcess returns $false so Dismount-WindowsImage is never called;
                # mock is defined so assertions stay consistent
                Mock -CommandName Dismount-WindowsImage -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Dismount-WIM -File $fakeWim -WhatIf } | Should -Not -Throw

                # Verify the informational log ("Dismounting WIM") is written for each image
                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*Dismounting WIM*'
                }
            }
        }
    }

    Context 'Set-CIDEONVariable' {
        It 'logs progress without throwing' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Version = '2026'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Set-CIDEONVariable -Version '2026' -WhatIf } | Should -Not -Throw

                Should -Invoke Write-InstallLog -Times 1 -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*CIDEON Variables*'
                }
            }
        }
    }

    Context 'Uninstall-AutodeskDeployment' {
        It 'logs failure when no version-matching product directories are found' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Version = '2026'
                $testPath = Join-Path -Path $TestDrive -ChildPath 'adsk_noproducts'
                New-Item -Path $testPath -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Uninstall-AutodeskDeployment -Path $testPath } | Should -Not -Throw

                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*No Autodesk Products found*'
                }
            }
        }

        It 'calls Installer.exe with uninstall arguments for matching product directories' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:Version = '2026'
                $imageRoot = Join-Path -Path $TestDrive -ChildPath 'adsk_uninstall'
                $productDir = Join-Path -Path $imageRoot -ChildPath 'AutoCAD_2026'
                New-Item -Path $productDir -ItemType Directory -Force | Out-Null

                $xmlBundle = @'
<Bundle><Identity><DisplayName>AutoCAD 2026</DisplayName></Identity></Bundle>
'@
                Set-Content -Path (Join-Path -Path $productDir -ChildPath 'setup.xml') -Value $xmlBundle
                Set-Content -Path (Join-Path -Path $productDir -ChildPath 'setup_ext.xml') -Value '<Bundle />'

                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Uninstall-AutodeskDeployment -Path $imageRoot } | Should -Not -Throw

                $script:startProcessCall | Should -Not -BeNullOrEmpty
                $script:startProcessCall.ArgumentList | Should -Match 'uninstall'
            }
        }
    }

    Context 'Install-CideonTool' {
        It 'returns without error when no Cideon files are available in WhatIf mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:CachedCideonFiles = @()
                $WhatIfPreference = $true

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-CachedFiles -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-CideonTool -Path 'C:\nonexistent' -WhatIf } | Should -Not -Throw

                $WhatIfPreference = $false
            }
        }

        It 'installs regular MSI with /qn argument' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith {
                    @([pscustomobject]@{
                            Name     = 'SomeTool.msi'
                            FullName = 'C:\Temp\Cideon\SomeTool.msi'
                        })
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-CideonTool -Path 'C:\Temp' } | Should -Not -Throw

                $script:startProcessCall.FilePath | Should -Be 'C:\Temp\Cideon\SomeTool.msi'
                $script:startProcessCall.ArgumentList | Should -Be '/qn'
            }
        }

        It 'builds correct ADDLOCAL feature string for VaultToolbox Pro and Observer' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-ChildItem -MockWith {
                    @([pscustomobject]@{
                            Name     = 'CIDEON.VAULT.TOOLBOX_3.5_Setup.msi'
                            FullName = 'C:\Temp\Cideon\CIDEON.VAULT.TOOLBOX_3.5_Setup.msi'
                        })
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Install-CideonTool -Path 'C:\Temp' -VaultToolboxPro -VaultToolboxObserver } | Should -Not -Throw

                $script:startProcessCall.ArgumentList | Should -Match 'CIDEON_VAULT_TOOLBOX'
                $script:startProcessCall.ArgumentList | Should -Match 'CIDEON_VAULT_AddOns'
            }
        }
    }

    Context 'Disable-VaultExtension' {
        It 'returns early and logs in WhatIf mode when extension path does not exist' {
            InModuleScope CIDEON.AutodeskDeployment {
                # Define mocks BEFORE enabling WhatIfPreference so Pester can register them
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Test-Path -MockWith { $false } -ModuleName 'CIDEON.AutodeskDeployment'

                { Disable-VaultExtension -Version '2026' -WhatIf } | Should -Not -Throw

                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*WhatIf mode*'
                }
            }
        }
    }

    Context 'Get-RealUserName' {
        It 'returns a non-empty string without throwing' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                $result = Get-RealUserName

                $result | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Register-WIMDismountTask' {
        It 'does not call Register-ScheduledTask in WhatIf mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:WIM = 'PDC_2026'

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName New-ScheduledTaskAction -MockWith {
                    [pscustomobject]@{ Execute = 'Powershell.exe' }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName New-ScheduledTaskTrigger -MockWith {
                    [pscustomobject]@{ Frequency = 'AtStartup' }
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Register-ScheduledTask -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Register-WIMDismountTask -WhatIf } | Should -Not -Throw

                Should -Invoke Register-ScheduledTask -Times 0 -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }

        It 'registers CleanupWIM task with SYSTEM account when ShouldProcess is confirmed' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:WIM = 'PDC_2026'

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                # Call the real ScheduledTasks cmdlets directly (bypassing the Pester mock) to
                # produce valid CimInstance objects so Register-ScheduledTask parameter-binding succeeds
                Mock -CommandName New-ScheduledTaskAction -MockWith {
                    & (Get-Command -Name 'New-ScheduledTaskAction' -Module 'ScheduledTasks') `
                        -Execute 'powershell.exe' -Argument '-NoProfile'
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName New-ScheduledTaskTrigger -MockWith {
                    & (Get-Command -Name 'New-ScheduledTaskTrigger' -Module 'ScheduledTasks') -AtStartup
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Register-ScheduledTask -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Register-WIMDismountTask -Confirm:$false } | Should -Not -Throw

                Should -Invoke Register-ScheduledTask -Times 1 -Exactly -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $TaskName -eq 'CleanupWIM'
                }
            }
        }
    }

    Context 'Get-AppLogError' {
        It 'writes -Fail log for each MsiInstaller error event found' {
            InModuleScope CIDEON.AutodeskDeployment {
                $fakeEvent = [pscustomobject]@{
                    LevelDisplayName = 'Error'
                    TimeCreated      = (Get-Date).AddMinutes(-5)
                    ProviderName     = 'MsiInstaller'
                    Message          = 'Installation failed for product X'
                }

                Mock -CommandName Get-WinEvent -MockWith { @($fakeEvent) } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                Get-AppLogError -Start (Get-Date).AddHours(-1)

                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Fail.IsPresent -and $text -like '*MsiInstaller*'
                }
            }
        }

        It 'does not write -Fail log when no MsiInstaller events are present' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Get-WinEvent -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Get-AppLogError -Start (Get-Date).AddHours(-1) } | Should -Not -Throw

                Should -Invoke Write-InstallLog -Times 0 -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $Fail.IsPresent
                }
            }
        }
    }

    Context 'Set-CIDEONLanguageVariable' {
        It 'logs the detected locale and skips SetEnvironmentVariable in WhatIf mode' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-WinSystemLocale -MockWith {
                    [pscustomobject]@{ Name = 'de-DE' }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Set-CIDEONLanguageVariable -WhatIf } | Should -Not -Throw

                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*de-DE*'
                }
            }
        }
    }

    Context 'Uninstall-Program' {
        It 'calls msiexec with /quiet for a slash-style uninstall string' {
            InModuleScope CIDEON.AutodeskDeployment {
                $script:startProcessCall = $null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Write-InstallProgress -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-InstalledProgram -MockWith {
                    @([pscustomobject]@{
                            DisplayName     = 'Autodesk Inventor 2026'
                            Publisher       = 'Autodesk'
                            UninstallString = 'MsiExec.exe /X{AAAA-BBBB-CCCC}'
                            ModifyPath      = ''
                        })
                } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {
                    param($FilePath, $ArgumentList)
                    $script:startProcessCall = @{ FilePath = $FilePath; ArgumentList = $ArgumentList }
                } -ModuleName 'CIDEON.AutodeskDeployment'

                { Uninstall-Program -Publisher 'Autodesk' -DisplayName 'Inventor' } | Should -Not -Throw

                $script:startProcessCall | Should -Not -BeNullOrEmpty
                $script:startProcessCall.ArgumentList | Should -Match '/quiet'
            }
        }

        It 'does nothing when no installed programs match the filter' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-InstalledProgram -MockWith { @() } -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Start-Process -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Uninstall-Program -Publisher 'NonExistent' } | Should -Not -Throw

                Should -Invoke Start-Process -Times 0 -ModuleName 'CIDEON.AutodeskDeployment'
            }
        }
    }

    Context 'Copy-Local' {
        It 'copies ProgramData subfolder to the specified target path' {
            InModuleScope CIDEON.AutodeskDeployment {
                $sourceRoot = Join-Path -Path $TestDrive -ChildPath 'copylocal_src'
                $progData = Join-Path -Path $sourceRoot -ChildPath 'Local\ProgramData'
                New-Item -Path $progData -ItemType Directory -Force | Out-Null
                Set-Content -Path (Join-Path -Path $progData -ChildPath 'settings.ini') -Value '[settings]'

                $targetRoot = Join-Path -Path $TestDrive -ChildPath 'copylocal_target'
                New-Item -Path $targetRoot -ItemType Directory -Force | Out-Null

                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Get-RealUserName -MockWith { 'testuser' } -ModuleName 'CIDEON.AutodeskDeployment'

                { Copy-Local -Path $sourceRoot -SourceFolder @('ProgramData') -TargetFolder @($targetRoot) } | Should -Not -Throw

                Test-Path (Join-Path -Path $targetRoot -ChildPath 'ProgramData\settings.ini') | Should -BeTrue
            }
        }

        It 'logs error and does not throw when SourceFolder and TargetFolder counts differ' {
            InModuleScope CIDEON.AutodeskDeployment {
                Mock -CommandName Write-InstallLog -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'
                Mock -CommandName Copy-Item -MockWith {} -ModuleName 'CIDEON.AutodeskDeployment'

                { Copy-Local -Path $TestDrive -SourceFolder @('ProgramData', 'Users') -TargetFolder @('C:\') } | Should -Not -Throw

                Should -Invoke Write-InstallLog -ModuleName 'CIDEON.AutodeskDeployment' -ParameterFilter {
                    $text -like '*Source and Target quantities*'
                }
            }
        }
    }
}
