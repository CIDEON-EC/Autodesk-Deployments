BeforeAll {
    $script:sutPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'New-DeploymentImage.ps1'
}

# The VHDX creation itself needs administrator rights, diskpart and a real disk; these tests cover the checks that run before.
Describe 'New-DeploymentImage.ps1' -Tag 'Unit' {
    It 'throws when the source folder does not exist' {
        { & $sutPath -Source (Join-Path -Path $TestDrive -ChildPath 'missing') } | Should -Throw '*Source folder not found*'
    }

    It 'refuses a network share as target' {
        $source = Join-Path -Path $TestDrive -ChildPath 'PDC_2027'
        New-Item -Path (Join-Path -Path $source -ChildPath 'Image') -ItemType Directory -Force | Out-Null

        { & $sutPath -Source $source -VhdxPath '\\server\share\PDC_2027.vhdx' } | Should -Throw '*local drive*'
    }
}
