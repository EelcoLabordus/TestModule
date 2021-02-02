#requires -Modules @{ ModuleName="Pester"; ModuleVersion="4.10.1" }
<#
.SYNOPSIS
  This script will test ARM files using TTK best practices from the Azure repository.

.DESCRIPTION
  This script will test ARM files on best practices from the Azure repository. 
  It will pass back these results so that it can be used for reporting.

.PARAMETER TemplatePath
  This is the path the ARM template is located.

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

.EXAMPLE
  .\Invoke-TestARMTTK.ps1 -TemplatePath "c:\test\test.json"

#>

#region --------------------------[ Initialisations ]-----------------------

#requires -Version 5.1

[CmdletBinding()]
[OutputType()]
param (
  [Parameter(
    Mandatory = $true,
    HelpMessage = "Please specified the required location to the arm file?")]
  [String]$TemplatePath,

  [Parameter(      
    Mandatory = $false,
    HelpMessage = "Please specified the required Resource Group Tags?")]
  $SkipControls
)
BEGIN {

  #endregion -----------------------[ Initialisations ]-----------------------

  #region --------------------------[ Declarations ]--------------------------
  # Setting Default variable.

  $Parameters = @{
    TemplatePath = $TemplatePath
    Pester       = $true
  }

  if ($SkipControls) {
    $Parameters.add("Skip", $SkipControls)
  }

  #endregion -----------------------[ Declarations ]--------------------------

  #region --------------------------[ Functions ]-----------------------------
  #endregion -----------------------[ Functions ]-----------------------------

  #region ---------------------[ Pre Pipeline Execution ]---------------------

  #endregion ------------------[ Pre Pipeline Execution ]---------------------
}

PROCESS {
  #region -----------------------[ Pipeline Execution ]-----------------------
  Test-AzTemplate @Parameters
  #endregion --------------------[ Pipeline Execution ]-----------------------
}

END {
  #region ---------------------[ Post Pipeline Execution ]--------------------

  Write-Verbose "Exit function $($MyInvocation.MyCommand.Name)"
  #endregion ------------------[ Post Pipeline Execution ]--------------------
}