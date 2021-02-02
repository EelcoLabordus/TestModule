#requires -Modules @{ ModuleName="AzSK"; ModuleVersion="4.15.0" }
#requires -Modules @{ ModuleName="Pester"; ModuleVersion="4.10.1" }
<#
.SYNOPSIS
Pester test for validating ARM template meets best-practices

.DESCRIPTION
This Pester test will validate one or more ARM templates in the specified
file path to validate that they meet the best practices.

.PARAMETER TemplatePath
The full path to the ARM template to check. This may be a path with
wild cards to check multiple files.

.PARAMETER Severity
An array of severity values that will count as failed tests. Any violation
found in the ARM template that matches a severity in this list will cause
the Pester test to count as failed. Defaults to 'High' and 'Medium'.

.PARAMETER SkipControlsFromFile
The path to a controls file that can be use to suppress rules.

.PARAMETER ParameterFilePath
This is the location of the parameter file for testing.

.INPUTS
  None

.OUTPUTS
  None

.LINK
  None

.NOTES
  Version:          1.0.0
  Author:           Eelco Labordus
  Change Log
  Link:             https://github.com/Azure/arm-ttk/tree/master/arm-ttk
  Source:           https://gist.github.com/PlagueHO/1af35ee65a2276ca90b3a8a5b224a5d4
    
    
#>
[CmdletBinding()]
param (
    [Parameter(
        Mandatory = $true,
        HelpMessage = "Please specified the required location to the arm file?")]
    [System.String]$TemplatePath,

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Please specified the severity of the tests?")]
    [System.String[]]$Severity = @('High', 'Medium'),

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Please specified the file that contain the exclusions?")]
    [System.String]$SkipControlsFromFile,

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Please specified the parameter of the ARM template?")]
    [System.String]$ParameterFilePath
)

#Default required parameters needed for testing
$Parameters = @{
    ARMTemplatePath       = $TemplatePath
    DoNotOpenOutputFolder = $true
}

#Addd the exclusion file if specified.
if ($SkipControlsFromFile) {
    $Parameters.add("SkipControls", $SkipControlsFromFile)
}

#Add the parameter file to the checks if found.
if ($ParameterFilePath) {
    $Parameters.add("ParameterFilePath", $ParameterFilePath)
}

#Run the trest with the specified parameters
$resultPath = Get-AzSKARMTemplateSecurityStatus @Parameters

Describe 'ARM template best practices' -Tag 'AzSK' {
    Context 'When AzSK module is installed and run on all files in the Templates folder' {

        #Check if file is scanned and results are generated
        $FileValidate = Get-ChildItem -Path $resultPath -Filter 'ARMCheckerResults_*.csv' -ErrorAction SilentlyContinue | sort-object -property lastwritetime
        If ($FileValidate) {
            $resultFile = (Get-ChildItem -Path $resultPath -Filter 'ARMCheckerResults_*.csv')[0].FullName

            #Publish result file to log from devops
            foreach ($file in $resultFile) {
                Write-host "##vso[task.uploadfile]$resultFile"
            }

            #Check if the export file a CSV file is so we can process it in the tests.
            It 'Should produce a valid CSV results file' {
                $resultFile | Should -Not -BeNullOrEmpty
                Test-Path -Path $resultFile | Should -Be $true
                $script:resultsContent = Get-Content -Path $resultFile | ConvertFrom-Csv
            }
        }

        #Checking if there where any checks that could be done on the files. If no could have been done it will specified a error like "No controls have been evaluated for ARM Template"
        $PowerShellValidate = Get-ChildItem -Path $resultPath -Filter 'PowerShellOutput.LOG' -ErrorAction SilentlyContinue
        if ($PowerShellValidate) {
            $PowerShellResults = (Get-ChildItem -Path $resultPath -Filter 'PowerShellOutput.LOG')[0].FullName

            $Nocontrols = Select-String -Path $PowerShellResults -Pattern "No controls have been evaluated for ARM Template"
    
            if ($Nocontrols -ne $null) {
                It "Skipped test" {
                    Set-ItResult -Skipped -Because "No controls have been evaluated for ARM Template!"
                }
            }
        }
    }

    #Loop through the results to display all tests and results.
    Context 'All AzSK checks for this file.' {
        $FileValidate = Get-ChildItem -Path $resultPath -Filter 'ARMCheckerResults_*.csv' -ErrorAction SilentlyContinue | sort-object -property lastwritetime
        If ($FileValidate) {
            $resultFile = (Get-ChildItem -Path $resultPath -Filter 'ARMCheckerResults_*.csv')[0].FullName

            $script:resultsContent = Get-Content -Path $resultFile | ConvertFrom-Csv
            #looping through all tests
            foreach ($results in $resultsContent) {
                It "$($results.ControlId) should pass." {
                    $results.Status  | Should -Not -Be 'Failed'
                }
                

            }
        }
    }
}