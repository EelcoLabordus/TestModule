#requires -modules InvokeBuild

<#
.SYNOPSIS
  This script contains the tasks for building the PowerShell module

.DESCRIPTION
  This script contains the tasks for building the PowerShell module

.PARAMETER Configuration
  What is the release pipeline for (Debug or Release)

.PARAMETER ADOPat
  What is the ADO personal accesses token.

.PARAMETER acceptableCodeCoveragePercent
  What is the percentage of code it needs to cover.

.PARAMETER ModuleName
  What is the Module name of this release

.PARAMETER MajorVersionNumber
  This number will be used to specified the major release number.

.INPUTS
  None

.OUTPUTS
  None

.LINK
None

.NOTES

.EXAMPLE
#>

Param (
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateSet('Debug', 'Release')]
    [String]
    $Configuration = 'Debug',
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $SourceLocation,
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ADOPat,
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $acceptableCodeCoveragePercent,
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [String]
    $ModuleName,
    [Parameter(ValueFromPipelineByPropertyName = $true)]
    [ValidateNotNullOrEmpty()]
    [Int]
    $MajorVersionNumber
)

Set-StrictMode -Version Latest

# Synopsis: Default task
task . Clean, Build


# Install build dependencies
Enter-Build {

    # Installing PSDepend for dependency management
    if (-not (Get-Module -Name PSDepend -ListAvailable)) {
        Install-Module PSDepend -Force
    }
    Import-Module PSDepend

    # Installing dependencies
    Write-Output -InputObject "  Invoke-PSDepend -Force"
    Invoke-PSDepend -Force

    # Setting build script variables
    Write-Output -InputObject "  Setting build script variables"
    $script:moduleSourcePath = Join-Path -Path $BuildRoot -ChildPath $ModuleName
    $script:moduleManifestPath = Join-Path -Path $moduleSourcePath -ChildPath "$ModuleName.psd1"
    $script:nuspecPath = Join-Path -Path $moduleSourcePath -ChildPath "$ModuleName.nuspec"
    $script:buildOutputPath = Join-Path -Path $BuildRoot -ChildPath 'build'
    $script:Imports = ( 'private', 'public', 'classes' )

    if ($env:TF_BUILD) {
        $TestOutputDir = "$($env:System_DefaultWorkingDirectory)\Results"
    }

    If (test-path -Path $moduleManifestPath) {
        Write-Output -InputObject "  PowerShell Module found, start prepping for module build."

        # Setting base module version and using it if building locally
        $script:newModuleVersion = New-Object -TypeName 'System.Version' -ArgumentList (0, 0, 1)

        # Setting the list of functions ot be exported by module
        $script:functionsToExport = (Test-ModuleManifest $moduleManifestPath).ExportedFunctions
    }
}

# Synopsis: Analyze the project with PSScriptAnalyzer
task Analyze {
    # Get-ChildItem parameters
    $Params = @{
        Path    = $moduleSourcePath
        Recurse = $true
        Include = "*.PSSATests.*"
    }

    $TestFiles = Get-ChildItem @Params

    # Pester parameters
    $Params = @{
        Path     = $TestFiles
        PassThru = $true
    }

    # Additional parameters on Azure Pipelines agents to generate test results
    if ($env:TF_BUILD) {
        Write-Output -InputObject "  Azure Pipelines agents detected, adding parameters."
        if (-not (Test-Path -Path $TestOutputDir -ErrorAction SilentlyContinue)) {
            New-Item -Path $TestOutputDir -ItemType Directory
        }
        $Timestamp = Get-date -UFormat "%Y%m%d-%H%M%S"
        $PSVersion = $PSVersionTable.PSVersion.Major
        $TestResultFile = "TEST-AnalysisResults_PS$PSVersion`_$TimeStamp.xml"
        $Params.Add("OutputFile", "$TestOutputDir\$TestResultFile")
        $Params.Add("OutputFormat", "NUnitXml")
    }

    if (-not(Test-Path -Path "$TestOutputDir\$TestResultFile" -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "  Result file not found!"
    }

    # Invoke all tests
    $TestResults = Invoke-Pester @Params
    if ($TestResults.FailedCount -gt 0) {
        $TestResults | Format-List
        throw "One or more PSScriptAnalyzer rules have been violated. Build cannot continue!"
    }
}

# Synopsis: Test the project with Pester tests
task Test {
    # Get-ChildItem parameters
    $Params = @{
        Path    = $moduleSourcePath
        Recurse = $true
        Include = "*.Tests.*"
    }

    $TestFiles = Get-ChildItem @Params

    # Pester parameters
    $Params = @{
        Path     = $TestFiles
        PassThru = $true
    }

    # Additional parameters on Azure Pipelines agents to generate test results
    if ($env:TF_BUILD) {
        Write-Output -InputObject "  Azure Pipelines agents detected, adding parameters."
        if (-not (Test-Path -Path $TestOutputDir -ErrorAction SilentlyContinue)) {
            New-Item -Path $TestOutputDir -ItemType Directory
        }
        $Timestamp = Get-date -UFormat "%Y%m%d-%H%M%S"
        $PSVersion = $PSVersionTable.PSVersion.Major
        $TestResultFile = "TEST-TestResultFile_PS$PSVersion`_$TimeStamp.xml"
        $Params.Add("OutputFile", "$TestOutputDir\$TestResultFile")
        $Params.Add("OutputFormat", "NUnitXml")
    }

    if (-not(Test-Path -Path "$TestOutputDir\$TestResultFile" -ErrorAction SilentlyContinue)) {
        Write-Warning -Message "  Result file not found!"
    }

    # Invoke all tests
    $TestResults = Invoke-Pester @Params
    if ($TestResults.FailedCount -gt 0) {
        $TestResults | Format-List
        throw "One or more Pester tests have failed. Build cannot continue!"
    }
}

task TestARMTTK {
    Write-Output -InputObject "  Start with testing using ARM-TTK."

    # Get-ChildItem parameters
    $Params = @{
        Path    = $moduleSourcePath
        Recurse = $true
        Include = "*.json*"
        Exclude = "*parameters*"
    }

    $TestFiles = Get-ChildItem @Params

    if ($TestFiles) {
        Write-Output -InputObject "  ARM files detected. Start ARM check."

        if (-not (Test-Path "$BuildRoot\Invoke-TestARMTTK.ps1")) {
            throw "File : Invoke-TestARMTTK.ps1 cannot be found!"
        }

        #Declare parameter for results
        [int]$TestFailed = 0

        #Installing ARM-TTK
        if ((Test-Path $env:BUILD_ARTIFACTSTAGINGDIRECTORY\arm-ttk\arm-ttk) -eq $false) {
            Write-Output -InputObject "  Clone https://github.com/Azure/arm-ttk.git."
            git clone https://github.com/Azure/arm-ttk.git --quiet $env:BUILD_ARTIFACTSTAGINGDIRECTORY\arm-ttk
        }
        import-module $env:BUILD_ARTIFACTSTAGINGDIRECTORY\arm-ttk\arm-ttk

        #Install required Pester Module
        Write-Output -InputObject "  Install required Pester Module."
        try {
            Remove-Module Pester -ErrorAction SilentlyContinue
            Import-Module Pester -RequiredVersion 4.10.1 -ErrorAction Stop
        }
        catch {
            $errorMessage = $error[0]
            if ($errorMessage -like "*no valid module file was found*") {
                Install-Module Pester -AllowClobber -RequiredVersion 4.10.1 -Force -SkipPublisherCheck -AcceptLicense
                Import-Module Pester -RequiredVersion 4.10.1 -ErrorAction Stop
            }
            else {
                Write-Error -Message $errorMessage
            }
        }  

        foreach ($TestFile in $TestFiles) {
            #Check if files need to be skipped!
            $ARMTTKSkipFiles = @()
            if (Get-ChildItem -Path "$($TestFile.DirectoryName)\ARMTTKSkipFiles.csv" -ErrorAction SilentlyContinue) {
                $ARMTTKSkipFiles = Get-Content -Path "$($TestFile.DirectoryName)\ARMTTKSkipFiles.csv"
                Write-Output -InputObject "  ARMTTKSkipFiles file found start excluding files."
            }
            If (-not($ARMTTKSkipFiles.Contains($TestFile.PSChildName))) {
                Write-Output -InputObject "  Start file: $($TestFile.PSChildName) for ARM checking!"

                $Parameters = @{
                    TemplatePath = $TestFile
                }

                #AzSSkipControlsFromFile
                if (Get-ChildItem -Path "$($TestFile.DirectoryName)\$($TestFile.BaseName).ARMTTKSkipControls.csv" -ErrorAction SilentlyContinue) {
                    Write-Output -InputObject "  SkipControls found add value to parameter."
                    $SkipControls = Get-Content -Path "$($TestFile.DirectoryName)\$($TestFile.BaseName).ARMTTKSkipControls.csv"
                    $Parameters.add("SkipControls", $SkipControls)
                }

                # Additional parameters on Azure Pipelines agents to generate test results
                if ($env:TF_BUILD) {
                    Write-Output -InputObject "  Azure Pipelines agents detected, adding parameters."
                    if (-not (Test-Path -Path $TestOutputDir -ErrorAction SilentlyContinue)) {
                        Write-Output -InputObject "  Creating path for testing report: $TestOutputDir"
                        New-Item -Path $TestOutputDir -ItemType Directory
                    }

                    $Timestamp = Get-date -UFormat "%Y%m%d-%H%M%S"
                    $TestResultFile = "TEST-ARMTTK_$($TestFile.BaseName)_$TimeStamp.xml"

                    $TestResults = Invoke-Pester `
                        -Script @{ Path = "$BuildRoot\Invoke-TestARMTTK.ps1"; Parameters = $parameters } `
                        -OutputFormat NUnitXml `
                        -OutputFile "$TestOutputDir\$TestResultFile" `
                        -PassThru
 
                    if (-not(Test-Path -Path "$TestOutputDir\$TestResultFile" -ErrorAction SilentlyContinue)) {
                        Write-Warning -Message "  Result file not found!"
                    }
                }
                else {
                    # Invoke all tests
                    $TestResults = Invoke-Pester -PassThru -Script @{ 
                        Path       = "$BuildRoot\Invoke-TestARMTTK.ps1"; 
                        Parameters = $parameters
                    }

                }
                #Setting counter to execute all tests and fail if one test failed
                if ($TestResults.FailedCount -gt 0) {
                    $TestFailed++
                }
            }
            else {
                Write-Output -InputObject "  Warning : $($TestFile.BaseName) skipped for checking!" 
            }
        }

        #Running trough all scripts and failed check in the end.
        if ($TestFailed -gt 0) {
            throw "One or more Pester tests have failed. Build cannot continue!"
        }
    }
    else {
        Write-Output -InputObject "  No ARM files detected. Skipping check."
    }
}

task TestARMAZSK {
    Write-Output -InputObject "  Start with testing using ARMAZSK."

    # Get-ChildItem parameters
    $Params = @{
        Path    = $moduleSourcePath
        Recurse = $true
        Include = "*.json*"
        Exclude = "*parameters*"
    }

    #Declare parameter for results
    [int]$TestFailed = 0

    $TestFiles = Get-ChildItem @Params

    if ($TestFiles) {
        Write-Output -InputObject "  ARM files detected. Start ARM check."

        if (-not (Test-Path "$BuildRoot\Invoke-TestARMAZSK.ps1")) {
            throw "File : Invoke-TestARMAZSK.ps1 cannot be found!"
        }

        Write-Output -InputObject "  Installing module AzSK."
        Install-Module -Name AzSK -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop

        foreach ($TestFile in $TestFiles) {
            #Check if files need to be skipped!
            $AzSSkipFiles = @()
            if (Get-ChildItem -Path "$($TestFile.DirectoryName)\AzSSkipFiles.csv" -ErrorAction SilentlyContinue) {
                $AzSSkipFiles = Get-Content -Path "$($TestFile.DirectoryName)\AzSSkipFiles.csv"
                Write-Output -InputObject "  AzSSkipFiles file found start excluding files."
                Write-Output -InputObject "  AzSSkipFiles: $AzSSkipFiles"
            }
            If (-not($AzSSkipFiles.Contains($TestFile.PSChildName))) {
                Write-Output -InputObject "  Start file: $($TestFile.PSChildName) for ARM checking!"

                $Parameters = @{
                    TemplatePath = $TestFile
                }

                #Check if there is a Severity file present and add it to the check.
                $Severity = Get-Content -Path "$($TestFile.DirectoryName)\$($TestFile.BaseName).Severity.txt" -ErrorAction SilentlyContinue
                If ($Severity) {
                    Write-Output -InputObject "  Severity found add value to parameter."
                    $Parameters.add("Severity", $Severity)
                }

                #AzSSkipControlsFromFile
                if (Get-ChildItem -Path "$($TestFile.DirectoryName)\$($TestFile.BaseName).AzSSkipControlsFromFile.csv" -ErrorAction SilentlyContinue) {
                    Write-Output -InputObject "  SkipControlsFromFile found add value to parameter."
                    $Parameters.add("SkipControlsFromFile", "$($TestFile.DirectoryName)\$($TestFile.BaseName).AzSSkipControlsFromFile.csv")
                }

                #Parameter File
                if (Get-ChildItem -Path "$($TestFile.DirectoryName)\$($TestFile.BaseName).parameters.json" -ErrorAction SilentlyContinue) {
                    Write-Output -InputObject "  Parameter File found add value to parameter."
                    $Parameters.add("ParameterFilePath", "$($TestFile.DirectoryName)\$($TestFile.BaseName).parameters.json")
                }

                # Additional parameters on Azure Pipelines agents to generate test results
                if ($env:TF_BUILD) {
                    Write-Output -InputObject "  Azure Pipelines agents detected, adding parameters."
                    if (-not (Test-Path -Path $TestOutputDir -ErrorAction SilentlyContinue)) {
                        Write-Output -InputObject "  Creating path for testing report: $TestOutputDir"
                        New-Item -Path $TestOutputDir -ItemType Directory
                    }
                    $Timestamp = Get-date -UFormat "%Y%m%d-%H%M%S"
                    $TestResultFile = "TEST-ARMAZSK_$($TestFile.BaseName)_$TimeStamp.xml"

                    $TestResults = Invoke-Pester `
                        -Script @{ Path = "$BuildRoot\Invoke-TestARMAZSK.ps1"; Parameters = $parameters } `
                        -OutputFormat NUnitXml `
                        -OutputFile "$TestOutputDir\$TestResultFile" `
                        -PassThru
                    
                    if (-not(Test-Path -Path "$TestOutputDir\$TestResultFile" -ErrorAction SilentlyContinue)) {
                        Write-Warning -Message "  Result file not found!"
                    }
                }
                else {
                    # Invoke all tests
                    $TestResults = Invoke-Pester -PassThru -Script @{ 
                        Path       = "$BuildRoot\Invoke-TestARMAZSK.ps1"; 
                        Parameters = $parameters
                    }

                }

                #Setting counter to execute all tests and fail if one test failed
                if ($TestResults.FailedCount -gt 0) {
                    $TestFailed++
                }
            }
            else {
                Write-Output -InputObject "  Warning : $($TestFile.BaseName) skipped for checking!" 
            }
        }
        
        #Running trough all scripts and failed check in the end.
        if ($TestFailed -gt 0) {
            throw "One or more Pester tests have failed. Build cannot continue!"
        }
    }
    else {
        Write-Output -InputObject "  No ARM files detected. Skipping check."
        
    }
}


# Synopsis: Verify the code coverage by tests
task CodeCoverage {

    $path = $moduleSourcePath
    $files = Get-ChildItem $path -Recurse -Include '*.ps1', '*.psm1' -Exclude '*.Tests.ps1', '*.PSSATests.ps1'

    $Params = @{
        Path         = $path
        CodeCoverage = $files
        PassThru     = $true
        Show         = 'Summary'
    }

    # Additional parameters on Azure Pipelines agents to generate code coverage report
    if ($env:TF_BUILD) {
        if (-not (Test-Path -Path $TestOutputDir -ErrorAction SilentlyContinue)) {
            New-Item -Path $TestOutputDir -ItemType Directory
        }
        $Timestamp = Get-date -UFormat "%Y%m%d-%H%M%S"
        $PSVersion = $PSVersionTable.PSVersion.Major
        $TestResultFile = "CodeCoverageResults_PS$PSVersion`_$TimeStamp.xml"
        $Params.Add("CodeCoverageOutputFile", "$TestOutputDir\$TestResultFile")

        Write-Output -InputObject "CodeCoverageOutputFile root path is : $TestOutputDir\$TestResultFile"
    }

    $result = Invoke-Pester @Params

    If ( $result.CodeCoverage ) {
        $codeCoverage = $result.CodeCoverage
        $commandsFound = $codeCoverage.NumberOfCommandsAnalyzed

        # To prevent any "Attempted to divide by zero" exceptions
        If ( $commandsFound -ne 0 ) {
            $commandsExercised = $codeCoverage.NumberOfCommandsExecuted
            [System.Double]$actualCodeCoveragePercent = [Math]::Round(($commandsExercised / $commandsFound) * 100, 2)
        }
        Else {
            [System.Double]$actualCodeCoveragePercent = 0
        }
    }

    # Fail the task if the code coverage results are not acceptable
    if ($actualCodeCoveragePercent -lt $acceptableCodeCoveragePercent) {
        throw "The overall code coverage by Pester tests is $actualCodeCoveragePercent% which is less than quality gate of $acceptableCodeCoveragePercent%. Pester ModuleVersion is: $((Get-Module -Name Pester -ListAvailable).Version)."
    }
}

# Synopsis: Generate a new module version if creating a release build
task GenerateNewModuleVersion -If ($Configuration -eq 'Release') {
    # Using the current NuGet package version from the feed as a version base when building via Azure DevOps pipeline

    # Define package repository name
    $repositoryName = $ModuleName + '-repository'
    $feedUsername = $ADOPat
    # Create credentials
    $password = ConvertTo-SecureString -String $ADOPat -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential ($feedUsername, $password)

    # Register a target PSRepository
    try {
        Write-Output -InputObject "  Register custom packages provider."
        Register-PackageSource -ProviderName 'PowerShellGet' -Name $repositoryName -Location $SourceLocation -Credential $Credential

    }
    catch {
        throw "Cannot register '$repositoryName' repository with source location '$SourceLocation'!"
    }

    # Define variable for existing package
    $existingPackage = $null

    try {
        # Look for the module package in the repository
        $existingPackage = Find-Module -Name $ModuleName -Credential $credential
    }
    # In no existing module package was found, the base module version defined in the script will be used
    catch {
        Write-Warning "No existing package for '$ModuleName' module was found in '$repositoryName' repository!"
    }

    # If existing module package was found, try to install the module
    if ($existingPackage) {
        Write-Output -InputObject "  Module [$ModuleName] detected."
        # Get the largest module version
        # $currentModuleVersion = (Get-Module -Name $ModuleName -ListAvailable | Measure-Object -Property 'Version' -Maximum).Maximum
        $currentModuleVersion = New-Object -TypeName 'System.Version' -ArgumentList ($existingPackage.Version)
        Write-Output -InputObject "  Module version [$currentModuleVersion]."

        # Set module version base numbers
        [int]$Major = $currentModuleVersion.Major
        [int]$Minor = $currentModuleVersion.Minor
        [int]$Build = $currentModuleVersion.Build

        try {
            # Install the existing module from the repository
            Write-Output -InputObject "  Installing Module [$ModuleName]."
            Install-Module -Name $ModuleName -RequiredVersion $existingPackage.Version -Credential $credential -Force
        }
        catch {
            throw "Cannot import module '$ModuleName'!"
        }

        # Get the count of exported module functions
        $existingFunctionsCount = (Get-Command -Module $ModuleName | Where-Object -Property Version -EQ $existingPackage.Version | Measure-Object).Count
        Write-Output -InputObject " Module commands are [$existingFunctionsCount]."
        
        # Check if new public functions were added in the current build
        [int]$sourceFunctionsCount = (Get-ChildItem -Path "$moduleSourcePath\Public\*.ps1" -Exclude "*.Tests.*" | Measure-Object).Count
        Write-Output -InputObject " PowerShell functions are [$sourceFunctionsCount]."

        [int]$newFunctionsCount = [System.Math]::Abs($sourceFunctionsCount - $existingFunctionsCount)
        Write-Output -InputObject " Different between is [$newFunctionsCount]."

        # Increase the minor number if any new public functions have been added
        if ($newFunctionsCount -gt 0) {
            Write-Output -InputObject " Increase the minor number if any new public functions have been added."
            [int]$Minor = $Minor + 1
            [int]$Build = 0
        }
        # If not, just increase the build number
        else {
            Write-Output -InputObject " Increase the build number."
            [int]$Build = $Build + 1
        }

        # If Major release number is specified then it will be used.
        if ($MajorVersionNumber) {
            Write-Output -InputObject " Major versioning number has been specified [$MajorVersionNumber]."
            If ($MajorVersionNumber -ge [int]$Major) {
                If ($MajorVersionNumber -gt [int]$Major) {
                    Write-Output -InputObject " Major versioning number is higher [$MajorVersionNumber] than current number [$Major]. Updating version and setting Minor and Build number to 0"
                    [int]$Major = $MajorVersionNumber
                    [int]$Minor = 0
                    [int]$Build = 0
                }
            }
            else {
                Throw "Version number specified [$MajorVersionNumber] is smaller then version released [$Major]."
            } 
        }

        # Update the module version object
        Write-Output -InputObject " Update new versioning number with [$Major.$Minor.$Build]"
        $Script:newModuleVersion = New-Object -TypeName 'System.Version' -ArgumentList ($Major, $Minor, $Build)
    }
}

# Synopsis: Generate list of functions to be exported by module
task GenerateListOfFunctionsToExport {
    # Set exported functions by finding functions exported by *.psm1 file via Export-ModuleMember
    $params = @{
        Force    = $true
        Passthru = $true
        Name     = (Resolve-Path (Get-ChildItem -Path $moduleSourcePath -Filter '*.psm1')).Path
    }
    $PowerShell = [Powershell]::Create()
    [void]$PowerShell.AddScript(
        {
            Param ($Force, $Passthru, $Name)
            $module = Import-Module -Name $Name -PassThru:$Passthru -Force:$Force
            $module | Where-Object { $_.Path -notin $module.Scripts }
        }
    ).AddParameters($Params)
    $module = $PowerShell.Invoke()
    $Script:functionsToExport = $module.ExportedFunctions.Keys
}

# Synopsis: Update the module manifest with module version and functions to export
task UpdateModuleManifest GenerateNewModuleVersion, GenerateListOfFunctionsToExport, {
    # Update-ModuleManifest parameters
    $Params = @{
        Path              = $moduleManifestPath
        ModuleVersion     = $newModuleVersion
        FunctionsToExport = $functionsToExport
    }

    # Update the manifest file
    Update-ModuleManifest @Params
}

# Synopsis: Update the NuGet package specification with module version
task UpdatePackageSpecification GenerateNewModuleVersion, {
    # Load the specification into XML object
    $xml = New-Object -TypeName 'XML'
    $xml.Load($nuspecPath)

    # Update package version
    $metadata = Select-XML -Xml $xml -XPath '//package/metadata'
    $metadata.Node.Version = $newModuleVersion

    # Save XML object back to the specification file
    $xml.Save($nuspecPath)
}

# Synopsis: Build the project
task Build UpdateModuleManifest, UpdatePackageSpecification, {
    # Warning on local builds
    if ($Configuration -eq 'Debug') {
        Write-Warning "Creating a debug build. Use it for test purpose only!"
    }

    # Create versioned output folder
    $moduleOutputPath = Join-Path -Path $buildOutputPath -ChildPath $ModuleName -AdditionalChildPath $newModuleVersion
    if (-not (Test-Path $moduleOutputPath)) {
        New-Item -Path $moduleOutputPath -ItemType Directory
    }

    # Copy-Item parameters
    $Params = @{
        Path        = "$moduleSourcePath\*"
        Destination = $moduleOutputPath
        Exclude     = "*.Tests.*", "*.PSSATests.*"
        Recurse     = $true
        Force       = $true
    }

    # Copy module files to the target build folder
    Copy-Item @Params

    #Populating the PSM1 file
    [System.Text.StringBuilder]$stringbuilder = [System.Text.StringBuilder]::new()    
    foreach ($folder in $imports ) {
        [void]$stringbuilder.AppendLine( "Write-Verbose 'Importing from [$moduleSourcePath\$folder]'" )
        if (Test-Path "$moduleSourcePath\$folder") {
            $fileList = Get-ChildItem "$moduleSourcePath\$folder\*.ps1" | Where-Object Name -NotLike '*.Tests.ps1'
            foreach ($file in $fileList) {
                $shortName = $file.fullname.replace($PSScriptRoot, '')
                Write-Output -InputObject "  Importing [.$shortName]"
                [void]$stringbuilder.AppendLine( "# .$shortName" ) 
                [void]$stringbuilder.AppendLine( [System.IO.File]::ReadAllText($file.fullname) )
            }
        }
    }
    $script:ModulePath = Join-Path -Path $moduleOutputPath -ChildPath "$ModuleName.psm1"
    Write-Output -InputObject "  Creating module [$ModulePath]"
    Set-Content -Path  $ModulePath -Value $stringbuilder.ToString()

    #Cleaning up output folders
    foreach ($folder in $imports ) {
        if (Test-Path "$moduleOutputPath\$folder") {
            Write-Output -InputObject "  Removing [$moduleOutputPath\$folder]"
            Remove-Item –Path "$moduleOutputPath\$folder" –Recurse
        }
    }

}

# Synopsis: Creating the help files for the module
task BuildingHelpFiles {

    $path = $moduleSourcePath
    $Modules = get-childitem -path $path -Filter *.psd1 -Verbose

    Write-Output -InputObject "Modules: $Modules"

    foreach ($Module in $Modules) {

        #Remove the module from OS
        Write-Output -InputObject "Start processing the following module : $($Module.Name)"
        Get-Module $Module.Name | Uninstall-Module -Force -ErrorAction SilentlyContinue

        #Install module from repo
        Import-Module -Name $Module.FullName -Verbose

        #Retrieve version number of module
        $moduleversion = Get-Module -ListAvailable $Module.FullName
        write-output -InputObject "$($Module.Name) has version : $($moduleversion.Version.ToString())"

        #Construction file paths

        if (-not (Test-Path -Path $buildOutputPath -ErrorAction SilentlyContinue)) {
            New-Item -Path $buildOutputPath -ItemType Directory
        }

        $RootPath = "$buildOutputPath\Help"
        If (!(test-path $RootPath)) {
            New-Item -ItemType Directory -Force -Path $RootPath
        }

        $RootModulePath = "$RootPath\$($Module.BaseName)"
        If (!(test-path $RootModulePath)) {
            New-Item -ItemType Directory -Force -Path $RootModulePath
        }

        $Modulepath = "$RootModulePath\$($moduleversion.Version.ToString())"
        If (test-path $Modulepath) {
            Remove-Item –path $Modulepath –recurse
        }
        New-Item -ItemType Directory -Force -Path $Modulepath

        #Constructing new markdown files
        $parameters = @{
            Module                = $Module.BaseName
            OutputFolder          = $Modulepath
            AlphabeticParamsOrder = $true
            WithModulePage        = $true
            ExcludeDontShow       = $true
            Force                 = $true
        }
        New-MarkdownHelp @parameters

        #Creating index files for module
        Copy-Item -Path "$Modulepath\$($Module.BaseName).md" -Destination "$Modulepath\index.md" -Force

        #Create New version specific Markdown file
        $ModuleInfo = Get-Module $Module.BaseName

        "---" |  Out-File -FilePath "$Modulepath\index.md" -Force
        "name : $($ModuleInfo.Version.ToString())" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "order : 1000 # higher has more priority" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "---" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "# PowerShell Module $($ModuleInfo.Name) home page" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "PowerShell Module $($ModuleInfo.Name)" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Attribute Name  |Value  |" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|---------|---------|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Name|$($ModuleInfo.Name)|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Version|$($ModuleInfo.Version.ToString())|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Description|$($ModuleInfo.Description)|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Copyright|$($ModuleInfo.Copyright)|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        
        #Function help within module
        "## Functions" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "the following functions are exported within this module:" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|Function Name  |Synopsis  |" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        "|---------|---------|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        
        $Functions = $ModuleInfo.ExportedFunctions
        Foreach ($Function in $Functions.Keys) {
            $FunctionsHelp = Get-Help -Name $Function -Full
            "|$($FunctionsHelp.Name)|$($FunctionsHelp.Synopsis)|" |  Out-File -FilePath "$Modulepath\index.md" -Append -Force
        }

        #Createing header for indexing services
        $Files = Get-ChildItem -Path $Modulepath -File -Recurse
        $Counter = 1

        Write-Output -InputObject "Start processing the MD files to include header."
        Foreach ($File in $Files) {
            [System.Collections.ArrayList]$files = Get-Content -Path $File.FullName

            ($files | Select-String -Pattern '----')
            $index = ($files.IndexOf('----') + 2)

            # Checking correct name, index is not correct
            if ($($File.BaseName) -eq "index") {
                $line1 = "Name : $($Module.Name)"
            }
            else {
                $line1 = "Name : $($File.BaseName)"
            }

            #Added counter for ordering the files
            $Order = $Counter * 100
            $line2 = "Order : $Order"
            $Counter ++

            #Writing files
            $insert = @($line1, $line2)
            $files.Insert($index, $insert)
            $files | Out-File $File.FullName

        }
    }
}

# Synopsis: Clean up the target build directory
task Clean {
    if (Test-Path $buildOutputPath) {
        Remove-Item –Path $buildOutputPath –Recurse
    }
}