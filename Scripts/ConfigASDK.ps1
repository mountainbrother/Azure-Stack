
<#

.SYNOPSYS

    The purpose of this script is to automate as much as possible post deployment tasks in Azure Stack Development Kit
    This include :
        - Set password expiration
        - Disable windows update on all infrastructures VMs and ASDK host
        - Tools installation (git, azstools, Azure Stack PS module)
        - Registration with Azure
        - Windows Server 2016 and Ubuntu 14.04.4-LTS images installation
        - MySQL Resource Provider Installation
        - Deployment of a MySQL 5.7 hosting Server on Windows Server 2016 Core
        - Attach MySQL hosting to MYSQL resource provider
        - SQL Resource Provider Installation
        - Deployment of a SQL 2014 hosting server on Windows 2016
        - Attach SQL hosting server to SQL resource provider
        - AppService Resource Provider sources download
        - Set new default Quotas for Compute, Network, Storage and keyvault
        - Create a simple offer and plan to provide IaaS capabilities to tenants

.VERSION

    1.0: small bug fixes and adding quotas/plan/offer creation
    0.5: add SQL 2014 VM deployment
    0.4: add Windows update disable
    0.3: Bug fix (SQL Provider prompting for tenantdirectoryID)
    0.2: Bug Fix (AZStools download)

.AUTHOR

    Alain VETIER 

    Blog: http://aka.ms/alainv  

.PARAMETERS

	-AAD (if you used AAD deployment) -Register (If you want to register your ASDK with Azure to enable market place Syndication)

.EXAMPLE

	ConfigASDK.ps1 -AAD -Register -verbose

#>

#####################################################################################################
# This sample script is not supported under any Microsoft standard support program or service.      #
# The sample script is provided AS IS without warranty of any kind. Microsoft further disclaims     #
# all implied warranties including, without limitation, any implied warranties of merchantability   #
# or of fitness for a particular purpose. The entire risk arising out of the use or performance of  #
# the sample scripts and documentation remains with you. In no event shall Microsoft, its authors,  #
# or anyone else involved in the creation, production, or delivery of the scripts be liable for any #
# damages whatsoever (including, without limitation, damages for loss of business profits, business #
# interruption, loss of business information, or other pecuniary loss) arising out of the use of or #
# inability to use the sample scripts or documentation, even if Microsoft has been advised of the   #
# possibility of such damages                                                                       #
#####################################################################################################


[CmdletBinding()]
Param (

# if AAD deployment
[switch]$AAD,

# if you want to enable market place syndication
[switch]$Register

)

$ISOPath = "PATH_TO WIN2016_ISO"                             # path to your windows 2016 evaluation ISO
$rppassword = "ADMINPASSWORD_FOR_RP_INSTALLATION"            # the password that you want to set for Resource Providers administrator account
$Azscredential = Get-Credential -Message "Enter your Azure Stack Service Administrator credentials"              # your service administrator (azure Stack) credentials
$azureRegSubscriptionId = "YOUR_SUBSCRIPTION_ID"             # your Azure subscription ID for registration
$azureRegDirectoryTenantName = "YOUR_AAD_TENANT_NAME"        # your Azure Tenant Directory Name for registration
$azureRegAccountId = "YOUR_AZURE_SERVICE_ADMIN"              # your Azure Global Administrator account ID for registration
$azureDirectoryTenantName = "YOUR_AAD_TENANT_NAME"           # your Azure Tenant Directory Name for Azure Stack 

# set password expiration to 180 days
Write-host "Configuring password expiration policy"
Set-ADDefaultDomainPasswordPolicy -MaxPasswordAge 180.00:00:00 -Identity azurestack.local
Get-ADDefaultDomainPasswordPolicy

#disable Windows update on infrastructure VMs and host
Write-Host "Disabling Windows Update on Infrastructure VMs and ASDK Host"
$AZDCredential = Get-Credential -Credential Azurestack\AzurestackAdmin
$AZSvms = get-vm -Name AZS*
$scriptblock = {
sc.exe config wuauserv start=disabled
Get-Service -Name wuauserv | fl StartType,Status
}
foreach ($vm in $AZSvms) {
Invoke-Command -VMName $vm.name -ScriptBlock $scriptblock -Credential $AZDCredential
}
sc.exe config wuauserv start=disabled

# Install Azure Stack PS module
Write-host "Installing Azure Stack PowerShel module"
Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
Get-Module -ListAvailable | where-Object {$_.Name -like “Azure*”} | Uninstall-Module
Install-Module -Name AzureRm.BootStrapper
Use-AzureRmProfile -Profile 2017-03-09-profile -Force
Install-Module -Name AzureStack -RequiredVersion 1.2.10
Get-Module -ListAvailable | where-Object {$_.Name -like “Azure*”}

# Download git
Write-host "installing Git"
invoke-webrequest https://github.com/git-for-windows/git/releases/download/v2.13.3.windows.1/Git-2.13.3-64-bit.exe -OutFile "c:\temp\Git-2.13.3-64-bit.exe"
$scriptblock = {C:\Temp\Git-2.13.3-64-bit.exe /SILENT /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" | Out-Null }
Invoke-Command -ScriptBlock $scriptblock | Out-Null

#Download AZSTools
Write-host "Downloading AzureStack-Tools"
cd \
invoke-webrequest https://github.com/Azure/AzureStack-Tools/archive/master.zip -OutFile master.zip
expand-archive master.zip -DestinationPath . -Force
Rename-Item -Path .\AzureStack-Tools-master -NewName AzureStack-Tools

# Register with azure - this will prompt for your Azure Credential
Write-host "Registering Azure Stack to Azure for market place syndication, enter your azure registration credential when prompted"
Disable-AzureRmDataCollection
if ($Register) {
C:\AzureStack-Tools\Registration\RegisterWithAzure.ps1 -azureSubscriptionId $azureRegSubscriptionId -azureDirectoryTenantName $azureRegDirectoryTenantName -azureAccountId $azureRegAccountId -Force
}

# login to AzureStackAdmin environment
ipmo C:\AzureStack-Tools\Connect\AzureStack.Connect.psm1
ipmo C:\AzureStack-Tools\ComputeAdmin\AzureStack.ComputeAdmin.psm1
Add-AzureRMEnvironment -Name "AzureStackAdmin" -ArmEndpoint "https://adminmanagement.local.azurestack.external" 
if ($AAD) {
$TenantID = Get-AzsDirectoryTenantId -AADTenantName  $azureDirectoryTenantName -EnvironmentName AzureStackAdmin 
set-AzureRmEnvironment -Name AzureStackAdmin -GraphAudience https://graph.windows.net/
}
else {
$TenantID = Get-AzsDirectoryTenantId -ADFS -EnvironmentName AzureStackAdmin
Set-AzureRmEnvironment AzureStackAdmin -GraphAudience https://graph.local.azurestack.external -EnableAdfsAuthentication:$true
}
Login-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $TenantID -Credential $Azscredential

# Create Windows Server 2016 Images
Write-host "installing Windows Server 2016 Datacenter full and Core images"
New-AzsServer2016VMImage -ISOPath $ISOPath -Version Both -IncludeLatestCU -Net35 $true -CreateGalleryItem $true

# Create Ubuntu 14.04.3-LTS image
Write-host "downloading Ubuntu 14.04.3-LTS Image"
invoke-webrequest https://partner-images.canonical.com/azure/azure_stack/ubuntu-14.04-LTS-microsoft_azure_stack-20170225-10.vhd.zip -OutFile "C:\Temp\Ubuntu.zip"
cd C:\Temp
expand-archive ubuntu.zip -DestinationPath . -Force
Write-host "Adding Ubuntu image to Azure Stack"
Add-AzsVMimage -publisher "Canonical" -offer "UbuntuServer" -sku "14.04.3-LTS" -version "1.0.0" -osType Linux -osDiskLocal 'C:\Temp\trusty-server-cloudimg-amd64-disk1.vhd'
del ubuntu.zip -Force
del trusty-server-cloudimg-amd64-disk1.vhd -Force

# Register resources providers
foreach($s in (Get-AzureRmSubscription)) {
        Select-AzureRmSubscription -SubscriptionId $s.SubscriptionId | Out-Null
        Write-Progress $($s.SubscriptionId + " : " + $s.SubscriptionName)
Get-AzureRmResourceProvider -ListAvailable | Register-AzureRmResourceProvider -Force
    } 

# Install MySQL Resource Provider
Write-host "downloading and installing MySQL resource provider"
Login-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $TenantID -Credential $Azscredential
Invoke-WebRequest https://aka.ms/azurestackmysqlrp -OutFile "c:\temp\MySql.zip"
cd C:\Temp
expand-archive c:\temp\MySql.zip -DestinationPath .\MySQL -Force
cd C:\Temp\MySQL
$vmLocalAdminPass = ConvertTo-SecureString "$rppassword" -AsPlainText -Force
$vmLocalAdminCreds = New-Object System.Management.Automation.PSCredential ("mysqlrpadmin", $vmLocalAdminPass)
$PfxPass = ConvertTo-SecureString "$rppassword" -AsPlainText -Force
.\DeployMySQLProvider.ps1 -DirectoryTenantID $TenantID -AzCredential $AzsCredential -VMLocalCredential $vmLocalAdminCreds -ResourceGroupName "MySqlRG" -VmName "MySQLRPVM" -ArmEndpoint "https://adminmanagement.local.azurestack.external" -TenantArmEndpoint "https://management.local.azurestack.external" -DefaultSSLCertificatePassword $PfxPass -AcceptLicense

# Deploy a mysql VM for hosting tenant db
Write-host "Creating a dedicated MySQL host VM for database hosting"
New-AzureRmResourceGroup -Name MySQL-Host -Location local
New-AzureRmResourceGroupDeployment -Name MySQLHost -ResourceGroupName MySQL-Host -TemplateUri https://raw.githubusercontent.com/alainv-msft/Azure-Stack/master/Templates/MySQL/azuredeploy.json -vmName "mySQLHost1" -adminUsername "mysqlrpadmin" -adminPassword $vmlocaladminpass -vmSize Standard_A1 -windowsOSVersion '2016-Datacenter' -mode Incremental -Verbose

# Create SKU and add host server to mysql RP
Write-Host "Attaching MySQL hosting server to MySQL resource provider"
New-AzureRmResourceGroupDeployment -ResourceGroupName mysql-host -TemplateUri https://raw.githubusercontent.com/alainv-msft/Azure-Stack/master/Templates/mysqladapter-add-hosting-server/azuredeploy.json -username "mysqlrpadmin" -password $vmLocalAdminPass -totalSpaceMB 10240 -skuName MySQL57 -Mode Incremental -Verbose

# Install SQL Resource Provider
Write-host "downloading and installing SQL resource provider"
Login-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $TenantID -Credential $Azscredential
cd C:\Temp
Invoke-WebRequest https://aka.ms/azurestacksqlrp -OutFile "c:\Temp\sql.zip"
expand-archive c:\temp\Sql.zip -DestinationPath .\SQL -Force
cd C:\Temp\SQL
$vmLocalAdminPass = ConvertTo-SecureString "$rppassword" -AsPlainText -Force
$vmLocalAdminCreds = New-Object System.Management.Automation.PSCredential ("sqlrpadmin", $vmLocalAdminPass)
$PfxPass = ConvertTo-SecureString "$rppassword" -AsPlainText -Force
.\DeploySQLProvider.ps1 -DirectoryTenantID $TenantID -AzCredential $AzsCredential -VMLocalCredential $vmLocalAdminCreds -ResourceGroupName "SqlRPRG" -VmName "SqlRPVM" -ArmEndpoint "https://adminmanagement.local.azurestack.external" -TenantArmEndpoint "https://management.local.azurestack.external" -DefaultSSLCertificatePassword $PfxPass

# Deploy a SQL 2014 VM for hosting tenant db
Write-Host "Creating a dedicated SQL 2014 host for database hosting"
New-AzureRmResourceGroup -Name SQL-Host -Location local
New-AzureRmResourceGroupDeployment -Name sqlhost1 -ResourceGroupName SQL-Host -TemplateUri https://raw.githubusercontent.com/alainv-msft/Azure-Stack/master/Templates/SQL2014/azuredeploy.json -adminPassword $vmlocaladminpass -adminUsername "sqlrpadmin" -windowsOSVersion "2016-Datacenter" -Mode Incremental -Verbose

# Create SKU and add host server to sql RP
Write-Host "Attaching SQL hosting server to SQL resource provider"
New-AzureRmResourceGroupDeployment -ResourceGroupName sql-host -TemplateUri https://raw.githubusercontent.com/alainv-msft/Azure-Stack/master/Templates/sqladapter-add-hosting-server/azuredeploy.json -hostingServerSQLLoginName "sa" -hostingServerSQLLoginPassword $vmLocalAdminPass -totalSpaceMB 10240 -skuName SQL2014 -Mode Incremental -Verbose

# install App Service To be added
Write-host "downloading appservice installer"
cd C:\Temp
Invoke-WebRequest http://aka.ms/appsvconmasrc1helper -OutFile "c:\temp\appservicehelper.zip"
Expand-Archive C:\Temp\appservicehelper.zip -DestinationPath .\AppService -Force
Invoke-WebRequest http://aka.ms/appsvconmasrc1installer -OutFile "c:\temp\AppService\appservice.exe"

# Configure a simple base plan and offer for IaaS
Import-Module C:\AzureStack-Tools\Connect\AzureStack.Connect.psm1
Import-Module C:\AzureStack-Tools\ServiceAdmin\AzureStack.ServiceAdmin.psm1
Login-AzureRmAccount -EnvironmentName "AzureStackAdmin" -TenantId $TenantID -Credential $Azscredential

# Default quotas, plan, and offer
$PlanName = "SimplePlan"
$OfferName = "SimpleOffer"
$RGName = "PlansandoffersRG"
$Location = (Get-AzsLocation).Name

$computeParams = @{
Name = "computedefault"
CoresLimit = 200
AvailabilitySetCount = 20
VirtualMachineCount = 100
VmScaleSetCount = 20
Location = $Location
}

$netParams = @{
Name = "netdefault"
PublicIpsPerSubscription = 500
VNetsPerSubscription = 500
GatewaysPerSubscription = 10
ConnectionsPerSubscription = 20
LoadBalancersPerSubscription = 500
NicsPerSubscription = 1000
SecurityGroupsPerSubscription = 500
Location = $Location
}

$storageParams = @{
Name = "storagedefault"
NumberOfStorageAccounts = 200
CapacityInGB = 2048
Location = $Location
}

$kvParams = @{
Location = $Location
}

$quotaIDs = @()
$quotaIDs += (New-AzsNetworkQuota @netParams).ID
$quotaIDs += (New-AzsComputeQuota @computeParams).ID
$quotaIDs += (New-AzsStorageQuota @storageParams).ID
$quotaIDs += (Get-AzsKeyVaultQuota @kvParams)

New-AzureRmResourceGroup -Name $RGName -Location $Location
$plan = New-AzsPlan -Name $PlanName -DisplayName $PlanName -ArmLocation $Location -ResourceGroupName $RGName -QuotaIds $QuotaIDs
New-AzsOffer -Name $OfferName -DisplayName $OfferName -State Public -BasePlanIds $plan.Id -ResourceGroupName $RGName -ArmLocation $Location










