Configuration deployRoboShadow {
    Import-DscResource -ModuleName 'PSDscResources' -ModuleVersion 2.12.0.0

    Node localhost {
        MsiPackage RoboShadowAgentMsiPackage {
            Path      = 'https://cdn.roboshadow.com/GetAgent/RoboShadowAgent-x64.msi'
            ProductId = '{DD2C070F-CBDD-4CF4-9816-E5A73F97BF84}'
            Arguments = '/qb /norestart ORGANISATION_ID=3a86c72c-1611-4b72-b68f-15e3f829f792'
            Ensure    = 'Present'
        }
    }
}

deployRoboShadow
