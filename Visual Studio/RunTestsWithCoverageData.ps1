﻿# Note: this script is based on the Microsoft-linked sample at forums.msdn.com regarding ".NET 3.5 Code Coverage"

$ErrorActionPreference = "Stop"

function CopyInstrumentedAssemblyToTestBinFolders(
    [string] $assemblyPath = $(Throw "Value cannot be null: assemblyPath"),    
    [string[]] $testBinFolders = $(Throw "Value cannot be null: testBinFolders"))
{
    $testBinFolders |
        ForEach-Object {
            Write-Debug ("Copying assembly (" + $assemblyPath `
                + ") to folder (" + $_ + ")...")

            Copy-Item $assemblyPath $_
        }
}

function GetAssemblyFolders(
    [string[]] $assemblyPaths = $(Throw "Value cannot be null: assemblyPaths"))
{
    [string[]] $folders = @()
    
    $assemblyPaths |
        ForEach-Object {
            [string] $folder = (Get-Item $_).DirectoryName

            $folders += $folder
        }

    return $folders
}

function InstrumentAssembly(
    [string] $assemblyPath = $(Throw "Value cannot be null: assemblyPath"))
{
    [string] $vsinstr = "${env:ProgramFiles(x86)}" `
        + "\Microsoft Visual Studio 10.0\Team Tools\Performance Tools\x64\VSInstr.exe"

    & $vsinstr "$assemblyPath" /coverage
}

function RunTests(
    [string[]] $assemblyPaths = $(Throw "Value cannot be null: assemblyPaths"),
    [string] $testSettingsPath)
{
    [string] $mstest = "${env:ProgramFiles(x86)}" `
        + "\Microsoft Visual Studio 10.0\Common7\IDE\MSTest.exe"

    [string[]] $parameters = @("/nologo")

    $assemblyPaths |
        ForEach-Object {
            $parameters += ('/testcontainer:"' + $_ + '"')
        }
    
    If ([string]::IsNullOrEmpty($testSettingsPath) -eq $false)
    {
        $parameters += ('/testsettings:"' + $testSettingsPath + '"')
    }

    Write-Debug "Running tests..."
	Write-Host "Parameters: $parameters"
    & $mstest $parameters
}

function SignAssembly(
    [string] $assemblyPath = $(Throw "Value cannot be null: assemblyPath"))
{
    Write-Debug ("Signing assembly (" + $assemblyPath + ")...")

    [string] $sn = "${env:ProgramFiles(x86)}" `
        + "\Microsoft SDKs\Windows\v7.0A\Bin\NETFX 4.0 Tools\sn.exe"
        
    & $sn -q -Ra "$assemblyPath" "..\ApplicationPages\ProjKey.snk"
}

function ToggleCodeCoverageProfiling(
    [bool] $enable)
{
    [string] $vsperfcmd = "${env:ProgramFiles(x86)}" `
        + "\Microsoft Visual Studio 10.0\Team Tools\Performance Tools\x64\VSPerfCmd.exe"

    If ($enable -eq $true)
    {
        Write-Debug "Starting code coverage profiler..."

        & $vsperfcmd /START:COVERAGE /OUTPUT:Proj.CoverageReport
    }
    Else
    {
        Write-Debug "Stopping code coverage profiler..."

        & $vsperfcmd /SHUTDOWN
    }
}

function UpdateGacAssemblyIfNecessary(
    [string] $assemblyPath = $(Throw "Value cannot be null: assemblyPath"))
{
    [string] $baseName = (Get-Item $assemblyPath).BaseName

    Write-Debug ("Checking if assembly (" + $baseName + ") is in the GAC...")

    [string] $gacutil = "${env:ProgramFiles(x86)}" `
        + "\Microsoft SDKs\Windows\v7.0A\Bin\gacutil.exe"

    [string] $numberOfItemsInGac = & $gacutil -l $baseName |
        Select-String "^Number of items =" |
            ForEach { $_.Line.Split("=")[1].Trim() }
            
    If ($numberOfItemsInGac -eq "0")
    {
        Write-Debug ("The assembly (" + $baseName + ") was not found in the GAC.")
    }
    ElseIf ($numberOfItemsInGac -eq "1")
    {
        Write-Debug ("Updating GAC assembly (" + $baseName + ")...")

        & $gacutil /if $assemblyPath
    }
    Else
    {
        Throw "Unexpected number of items in the GAC: " + $numberOfItemsInGac
    }
}

function Main
{
    [string] $testSettingsPath = Get-Item "..\build.testsettings"

    [string[]] $assembliesToInstrument =
    @(
        Get-Item "..\*\Proj*.dll"
    )
    
    [string[]] $testAssemblies =
    @(
        Get-Item "..\*\bin\Debug\*Tests.Unit*.dll"
    )

    [string[]] $testBinFolders = GetAssemblyFolders($testAssemblies)

    $assembliesToInstrument |
        ForEach-Object {
            InstrumentAssembly $_
            
            SignAssembly $_

            CopyInstrumentedAssemblyToTestBinFolders $_ $testBinFolders

            UpdateGacAssemblyIfNecessary $_
			
        }
    
    ToggleCodeCoverageProfiling $true

    RunTests $testAssemblies $testSettingsPath

    ToggleCodeCoverageProfiling $false
}

Main
