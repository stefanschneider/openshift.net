function Cleanup-Directory($directory)
{
    if (Test-Path -Path $directory)
    {
        Write-Verbose "Directory '${directory}' exists, cleaning it up."
        takeown /f $directory /r >> c:\openshift\setup_logs\dir_cleanups.log
        $userDomain = [Environment]::UserDomainName
        $userName = [Environment]::UserName
        Start-Process -Wait -NoNewWindow -PassThru 'icacls' """${directory}"" /grant ""${userDomain}\${userName}"":F /t" >> c:\openshift\setup_logs\dir_cleanups.log
        Remove-Item -Path $directory -Force -Recurse >> c:\openshift\setup_logs\dir_cleanups.log
    }
}

function Setup-MCollective($installLocation, $cygwinInstallLocation, $rubyDir)
{
    $mcollectiveSetupScript = (Join-Path $currentDir '..\mcollective\setup-mcollective.ps1')
    $mcollectiveSetupCommand = "-File ${mcollectiveSetupScript} -installLocation ${installLocation} -cygwinInstallLocation ${cygwinInstallLocation}"

    Run-RubyCommand $rubyDir "powershell ${mcollectiveSetupCommand}" $rubyDir
}

function Configure-MCollective($userActivemqServer, $userActivemqPort, $userActivemqUser, $userActivemqPassword, $mcollectiveInstallDir, $binDir, $rubyDir, $pskPlugin)
{
    $mcollectiveSetupScript = (Join-Path $currentDir '..\mcollective\configure-mcollective.ps1')

    $arguments = "-File ${mcollectiveSetupScript} -userActivemqServer ${userActivemqServer} -userActivemqPort ${userActivemqPort} -userActivemqUser ${userActivemqUser} -userActivemqPassword ${userActivemqPassword} -mcollectivePath ${mcollectiveInstallDir} -binDir ${binDir} -pskPlugin ${pskPlugin}"

    Run-RubyCommand $rubyDir "powershell ${arguments}" $mcollectiveInstallDir
}

function Setup-SSHD($cygwinDir, $listenAddress, $port)
{
    Cleanup-Directory $cygwinDir

    $sshdSetupScript = (Join-Path $currentDir '..\sshd\setup-sshd.ps1')

    $arguments = "-File ${sshdSetupScript} -cygwinDir ${cygwinDir} -listenAddress ${listenAddress} -port ${port}"
    $sshdSetupProcess = Start-Process -Wait -PassThru -NoNewWindow 'powershell' $arguments

    if ($sshdSetupProcess.ExitCode -ne 0)
    {
        Write-Error 'SSHD setup failed. Please check installation logs.'
        exit 1
    }
    else
    {
        Write-Host "[OK] SSHD installed successfully."
    }
}

function Setup-OOAliases($binLocation, $cygwinDir)
{
    $ooBinDir = "c:\openshift\oo-bin"
    Cleanup-Directory $ooBinDir
    Write-Host "Setting bash aliases for oo-* commands in '${ooBinDir}' ..."
    Write-Verbose "Creating oo-bin directory '${ooBinDir}' ..."
    New-Item -path $ooBinDir -type directory -Force | Out-Null

	$nodeCommands = @("gear", "oo-accept-node", "oo-admin-cartridge", "oo-admin-ctl-gears")
	$ooCmdPath = (Join-Path $binLocation 'oo-cmd.exe').Replace("\", "/")
	foreach($nodeCommand in $nodeCommands)
	{
		$aliasPath = (Join-Path $ooBinDir $nodeCommand.ToLower())
		"${ooCmdPath} ${nodeCommand} `$@" | Out-File -Encoding Ascii -Force -FilePath $aliasPath
        $aliasUnixPath = & $cygpath $aliasPath
        & $chmod +x $aliasUnixPath
	}
	
	$ooDiagnosticsAlias = (Join-Path $ooBinDir 'oo-diagnostics')
	$ooDiagnosticsPath = (Join-Path $binLocation 'oo-diagnostics.exe').Replace("\", "/")
	"c:/windows/system32/cmd.exe /c ${ooDiagnosticsPath} `$@" | Out-File -Encoding Ascii -Force -FilePath $ooDiagnosticsAlias
	 $aliasUnixDiagnosticsPath = & $cygpath $ooDiagnosticsAlias
	 & $chmod +x $aliasUnixDiagnosticsPath

    Write-Host "Setting up oo-ssh ..."
    $ooSSHScriptPath = (Join-Path $ooBinDir "oo-ssh")
    Write-Template (Join-Path $currentDir "oo-ssh.template") $ooSSHScriptPath @{}
    & $chmod +x $ooSSHScriptPath

    Write-Host "Setting up bash profile for admin user ..."
    $ooBinDirCyg = & $cygpath $ooBinDir

    $bashProfileFile = (Join-Path $cygwinDir 'admin_home\.bash_profile')
    [System.IO.File]::WriteAllText($bashProfileFile, "export PATH=`$PATH:${ooBinDirCyg}")
}

function Setup-GAC($binLocation)
{	
	$executables = $("MsSQLSysGenerator.exe", "oo-cmd.exe", "oo-trap-user.exe")
	foreach($exe in $executables)
	{		
		$exePath = Join-Path $binLocation $exe
		& C:\Windows\Microsoft.NET\Framework64\v4.0.30319\ngen.exe install $exePath 
	}
}

function Setup-GlobalEnv($binLocation)
{
    $ooBinDir = "c:\openshift\oo-bin"
    $envDir = "c:\openshift\env"
    Cleanup-Directory $envDir
    Write-Host "Setting up global gear environment variables in '${envDir}' ..."
    Write-Verbose "Creating env directory '${envDir}' ..."
    New-Item -path $envDir -type directory -Force | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $envDir 'OPENSHIFT_BROKER_HOST'), $brokerHost)
    [System.IO.File]::WriteAllText((Join-Path $envDir 'OPENSHIFT_CLOUD_DOMAIN'), $cloudDomain)
    [System.IO.File]::WriteAllText((Join-Path $envDir 'OPENSHIFT_CARTRIDGE_SDK_POWERSHELL'), (Join-Path $binLocation 'cartridge_sdk\powershell\sdk.ps1'))
	[System.IO.File]::WriteAllText((Join-Path $envDir 'OPENSHIFT_CARTRIDGE_SDK_BASH'), (Join-Path $binLocation 'cartridge_sdk\bash\sdk'))

    $pathEnvEntries =@('/usr/local/bin',
        '/usr/bin',
        (& $cygpath ([environment]::getfolderpath("system"))),
        (& $cygpath ([environment]::getfolderpath("windows"))),
        (& $cygpath (join-Path ([environment]::getfolderpath("system")) 'wbem')),
        (& $cygpath (join-Path ([environment]::getfolderpath("system")) 'windowspowershell\v1.0')),
        (& $cygpath $ooBinDir),
        (& $cygpath (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\100\Tools\ClientSetup').Path))

    [System.IO.File]::WriteAllText((Join-Path $envDir 'PATH'), [string]::Join(":", $pathEnvEntries))
}

function Setup-Ruby($rubyDownloadLocation, $rubyInstallLocation)
{
    Write-Host "Downloading ruby setup package from '${rubyDownloadLocation}'"
    $rubySetupPackage = Join-Path $env:TEMP "ruby-setup.exe"
    if ((Test-Path $rubySetupPackage) -eq $true)
    {
        Write-Verbose "Removing existing ruby setup package from temp dir."
        rm $rubySetupPackage -Force > $null
    }

    if ([string]::IsNullOrWhiteSpace($env:osiProxy))
    {
        Invoke-WebRequest $rubyDownloadLocation -OutFile $rubySetupPackage
    }
    else
    {
        Invoke-WebRequest $rubyDownloadLocation -OutFile $rubySetupPackage -Proxy $env:osiProxy
    }

    Write-Verbose "Ruby install package downloaded to '${rubySetupPackage}'"

    Cleanup-Directory $rubyInstallLocation

    Write-Host "Installing ruby to '${rubyInstallLocation}' ..."
    $rubySetupProcess = Start-Process -Wait -PassThru -NoNewWindow $rubySetupPackage "/verysilent /dir=""${rubyInstallLocation}"""

    if ($rubySetupProcess.ExitCode -ne 0)
    {
        Write-Error 'Ruby setup failed. Please check installation logs.'
        exit 1
    }
    else
    {
        Write-Host "[OK] Ruby installed successfully."
    }
}

function Get-UpdatedPrivilegeRule($iniDictionary, $privilege, $itemToAdd)
{
    $privilegeRightsKey = 'Privilege Rights'

    if ($iniDictionary.ContainsKey($privilegeRightsKey) -eq $false)
    {
        Write-Error "Could not find key '${privilegeRightsKey}' in the secedit output."
        exit 1
    }

    $existingValues = @()

    if ($iniDictionary[$privilegeRightsKey].ContainsKey($privilege) -eq $true)
    {
        $existingValues = $iniDictionary[$privilegeRightsKey][$privilege].Split(',')
    }

    return [string]::Join(',', $existingValues + $itemToAdd)
}

function Setup-Privileges()
{
    $serviceAccount = 'openshift_service'
    $outFile = 'c:\openshift\secedit_symlink_out.inf'
    $inFile = 'c:\openshift\secedit_symlink.inf'

    $sceditProcess = Start-Process -Wait -PassThru -NoNewWindow 'secedit.exe' "/export /cfg ${outFile}"

    $sceditContent = Get-IniContent $outFile


    Write-Host 'Setting up symlink privileges ...'
    $objUser = New-Object System.Security.Principal.NTAccount('Everyone')
    $strSID = $objUser.Translate([System.Security.Principal.SecurityIdentifier])
    $userSID = $strSID.Value

    Write-Template (Join-Path $currentDir "secedit_symlink.template") $inFile @{
        seCreateSymbolicLinkPrivilege = Get-UpdatedPrivilegeRule $sceditContent 'SeCreateSymbolicLinkPrivilege' "*${userSID}"
        seTcbPrivilege = Get-UpdatedPrivilegeRule $sceditContent 'SeTcbPrivilege' "${serviceAccount},administrator"
        seCreateTokenPrivilege = Get-UpdatedPrivilegeRule $sceditContent 'SeCreateTokenPrivilege' "${serviceAccount},administrator"
        seServiceLogonRight = Get-UpdatedPrivilegeRule $sceditContent 'SeServiceLogonRight' "${serviceAccount},administrator"
        seAssignPrimaryTokenPrivilege = Get-UpdatedPrivilegeRule $sceditContent 'SeAssignPrimaryTokenPrivilege' "${serviceAccount},administrator"
    }

    $sceditProcess = Start-Process -Wait -PassThru -NoNewWindow 'secedit.exe' "/configure /db secedit.sdb /cfg  ${inFile}"

    if ($sceditProcess.ExitCode -ne 0)
    {
        Write-Error "Error setting up symlink privileges. Please check install logs."
        exit 1
    }
    else
    {
        Write-Host "[OK] Symlink privileges were setup successfully."
    }

    Remove-Item -Force -Path $inFile
    Remove-Item -Force -Path $outFile
}
