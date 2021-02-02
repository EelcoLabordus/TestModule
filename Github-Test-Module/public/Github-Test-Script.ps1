function Github-Test-Script
{
<#
.SYNOPSIS
  This is a test script.

.DESCRIPTION
  This is a test script.

.PARAMETER 

.INPUTS
  None

.OUTPUTS
  None

.LINK
  None

.NOTES
  Version:         0.0.1
  Author:          Eelco Labordus
  Company:         ......
  Change Log

.EXAMPLE
  .\Github-Test-Script

#>

  #region --------------------------[ Initialisations ]-----------------------

  #requires -Version 5.1

  [CmdletBinding()]
  [OutputType()]
  param
  ()

  BEGIN
  {

  #endregion -----------------------[ Initialisations ]-----------------------

    #region --------------------------[ Declarations ]--------------------------
    # Setting Default variable.
    #endregion -----------------------[ Declarations ]--------------------------

    #region --------------------------[ Functions ]-----------------------------
    #endregion -----------------------[ Functions ]-----------------------------

    #region ---------------------[ Pre Pipeline Execution ]---------------------

    #endregion ------------------[ Pre Pipeline Execution ]---------------------
  }

  PROCESS
  {
    #region -----------------------[ Pipeline Execution ]-----------------------

    #endregion --------------------[ Pipeline Execution ]-----------------------
  }

  END
  {
    #region ---------------------[ Post Pipeline Execution ]--------------------

    Write-Verbose "Exit function $($MyInvocation.MyCommand.Name)"
    #endregion ------------------[ Post Pipeline Execution ]--------------------
  }
}
