Configuration powershell7 {
    Import-DscResource -ModuleName 'PSDscResources' -ModuleVersion 2.12.0.0

    Node localhost {
        MsiPackage PowerShell7MsiPackage {
            Path      = 'https://github.com/PowerShell/PowerShell/releases/download/v7.4.5/PowerShell-7.4.5-win-x64.msi'
            ProductId = '{C1593F76-F694-448E-AD35-82DDD6203975}'
            Ensure    = 'Present'
        }
    }
}

powershell7
