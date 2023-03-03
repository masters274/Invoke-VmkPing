#requires -Version 1.0
#requires -Module VMware.PowerCLI

<#PSScriptInfo

        .VERSION 0.4.1

        .GUID 58a4280b-fcf2-43bc-9dc9-b1da178da404

        .AUTHOR Chris Masters

        .COMPANYNAME Chris Masters

        .COPYRIGHT (c) 2018 Chris Masters. All rights reserved.

        .TAGS network vmware vsphere ping vmkping virtual vm

        .LICENSEURI 

        .PROJECTURI https://github.com/masters274/Invoke-VmkPing

        .ICONURI 

        .EXTERNALMODULEDEPENDENCIES VMware.PowerCLI

        .REQUIREDSCRIPTS 

        .EXTERNALSCRIPTDEPENDENCIES 

        .RELEASENOTES
        12/22/2018:        
                0.1 -   Day one release. 
        11/01/2022:
                0.2 -   Added ability to connect thru vCenter
        11/02/2022:
                0.3 -   -IPAddress is now an array of IP addresses, and accepts values from the pipeline
        11/02/2022:
                0.4 -   Moved connection info to Begin{} block 
        03/02/2023:
                0.4.1 - Moved to GitHub. Actions publishing to PowerShell Gallery

        .PRIVATEDATA 
        N/A
#> 

<#
        .SYNOPSIS
        VMK Ping from PowerCli

        .DESCRIPTION
        This script allows you to test the connectivity of your virtual nics in vSphere. You no longer need to 
        enable SSH to perform these tests. This script works great in an automated deployment strategy. 

        .EXAMPLE
        Invoke-VmkPing -VMHost myHost.domain.local -Credential root -IPAddress 192.168.200.10
        This will perform a VMK ping to 192.168.200.10 from host myHost.domain.local, results will look similar to
        the following.

        Duplicated     : 0
        HostAddr       : 192.168.200.10
        PacketLost     : 0
        Recieved       : 3
        RoundtripAvgMS : 192
        RoundtripMaxMS : 221
        RoundtripMinMS : 168
        Transmitted    : 3

        .EXAMPLE
        Invoke-VmkPing -VMHost myHost.domain.local -Credential root -IPAddress 192.168.200.10 -DFBit -Size 8972
        This will perform a VMK ping to 192.168.200.10 from host myHost.domain.local with the DF (don't fragment)
        bit set, and test that jumbo frames are configured properly, end to end. Don't forget about packet headers.
        We set the size to 8972, to test that our jumbo configuration of 9000 is working propery. Don't forget the
        -DFBit setting, otherwise it will always work no matter the size if connectivity is true. 

        .NOTES
        Requires that you have VMware.PowerCli PSSnapin loaded.

        .LINK
        https://github.com/masters274/Invoke-VmkPing
        https://www.powershellgallery.com/profiles/masters274/

        .INPUTS
        Accepts a string value for API key and a string or array of strings for the ServiceTag parameter

        .OUTPUTS
        Provides PSObject with network stats, based on the results
        
        Duplicated     : 0
        HostAddr       : 192.168.200.10
        PacketLost     : 0
        Recieved       : 3
        RoundtripAvgMS : 192
        RoundtripMaxMS : 221
        RoundtripMinMS : 168
        Transmitted    : 3 
#>


Param
(
    [Parameter(Mandatory = $true, HelpMessage = 'VMHost you want to ping from')]
    [String] $VMHost, 

    [Parameter(Mandatory = $false, HelpMessage = 'Connect to vCenter instead of direct to host')]
    [String] $VCenterServer, 
        
    [Parameter(Mandatory = $true, HelpMessage = 'Credentials for administering VMHost')]
    [System.Management.Automation.Credential()]
    [PSCredential] $Credential,
        
    [int] $Count = 3,
        
    [Switch] $DFBit, # set this when testing jumbo frames, or > 1500 packet size
        
    [Parameter(Mandatory = $true, HelpMessage = 'IP you want to ping for testing', ValueFromPipeline)]
    [IPAddress[]] $IPAddress,
        
    [ValidatePattern('^vmk*')]
    [String] $Interface = $null, # $null will pick the nic based on routing table, or interface subnet
        
    [int] $Size = 1500, # set to 8972 to test jumbo frames
        
    [Long] $TTL = $null
)
    
Begin {
    
    # Variables 
    $strStopAction = 'Stop'
    
    # Connect to the VMHost
    Try {
        if ($VCenterServer) {
            $Server = $VCenterServer
        }
        else { 
            $Server = $VMHost
        }
        Connect-VIServer -Server $Server -Credential $Credential -WarningAction SilentlyContinue -ErrorAction $strStopAction | Out-Null
        $cmdESXcli = Get-EsxCli -VMHost $VMHost -ErrorAction $strStopAction
    }
    Catch {
        Write-Error -Message ('Failed to connect to VMHost {0}' -f $VMHost)
        return
    }
}
    
Process {
    
    #ping(long count, boolean debug, boolean df, string host, string interface, string interval, boolean ipv4, boolean ipv6, string netstack, string nexthop, long size, long ttl, string wait
    [Bool] $isIPv4 = $false
    [Bool] $isIPv6 = $false
     
    foreach ($ip in $IPAddress) {
        
        If ($ip.AddressFamily -eq 'InterNetworkV6') {
            $isIPv6 = $true
        }
        Else {
            $isIPv4 = $true
        }
    
        $ret = $cmdESXcli.network.diag.ping(
            $Count,
            $false, # debugging
            $(If (!$DFBit) { $null } Else { $DFBit }), # Don't fragment bit
            $ip,
            $null,
            $null, # String Interval
            $isIPv4,
            $isIPv6,
            $null, # [string] netstack
            $null, # [string] nexthop
            $Size, # Set to 8972 to test jumbo frames, also need DF bit set
            $(If (!$TTL) { $null } Else { $TTL }),
            $null # [String] wait
        )
        
        If ($ret.summary.PacketLost -gt 0) {
            Write-Warning -Message ('IP {0} not reachable, or missing packets!' -f $ip)
        }
    
        $ret.summary
    }
}
    
End {
    Disconnect-VIServer -Server $Server -Force -Confirm:$false | Out-Null
}
