$currentDir = split-path $SCRIPT:MyInvocation.MyCommand.Path -parent
Import-Module (Join-Path $currentDir '..\common\openshift-common.psd1') -DisableNameChecking


$status = Invoke-Expression "OO-Broker-Auth-Key-Add -WithAppUuid $json.'--with-app-uuid' -WithAppName $json.'--with-app-name' -WithContainerUuid $json.'--with-container-uuid' -WithContainerName $json.'--with-container-name' -WithNamespace $json.'--with-namespace' -WithRequestId $json.'--with-request-id' -CartName $json.'--cart-name' -ComponentName $json.'--component-name' -WithSoftwareVersion $json.'--with-software-version' -CartridgeVendor $json.'--cartridge-vendor' -WithIv $json.'--with-iv' -WithToken $json.'--with-token'"
write-Output $status.Output
exit $status.ExitCode