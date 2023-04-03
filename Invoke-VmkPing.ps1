#requires -Version 1.0
#requires -Module VMware.PowerCLI

<#PSScriptInfo

        .VERSION 0.4.3

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
        Invoke-VmkPing -VMHost myHost.domain.local -Credential root -IPAddress 192.168.200.10 -Interface vmk2
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
    [Parameter(Mandatory = $true, HelpMessage = 'Server/VMHost you want to ping from')]
    [Alias('VMHost')]
    [String] $Server, 
        
    [Parameter()]
    [int] $Count = 3,
        
    [Parameter()]
    [Switch] $DFBit, # set this when testing jumbo frames, or > 1500 packet size
        
    [Parameter(Mandatory = $true, HelpMessage = 'IP you want to ping for testing', ValueFromPipeline)]
    [IPAddress[]] $IPAddress,
        
    [Parameter()]
    [ValidatePattern('^vmk*')]
    [String] $Interface = $null, # $null will pick the nic based on routing table, or interface subnet
        
    [Parameter()]
    [int] $Size = 1500, # set to 8972 to test jumbo frames

    [Parameter()]
    [string] $NetStack, # Options are 'defaultTcpipStack', 'vSphereProvisioning', 'vmotion'
        
    [Long] $TTL = $null
)
    
Begin {
    
    # Variables 
    $strStopAction = 'Stop'
    
    # Connect to the VMHost
    Try {
        
        $VMHost = Get-VMHost -Name $Server -ErrorAction $strStopAction
        $cmdESXcli = Get-EsxCli -VMHost $VMHost -V2 -ErrorAction $strStopAction
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
        
        if ($ip.AddressFamily -eq 'InterNetworkV6') {
            $isIPv6 = $true
        }
        else {
            $isIPv4 = $true
        }
        #Create Args Object, so ESXCLI can be called name name rather than position.
        $cmdESXcliArgs = $cmdESXCLI.network.diag.ping.CreateArgs()
        
        #End of line comments are from that object
        #By default all args are "unset" using if (!$Variable) {} Statements to keep them that way, because passing $Null from Params doesn't work
        $cmdESXCLIArgs.host = $IP.ToString()        #([string], optional)
        $cmdESXCLIArgs.debug = $false       #([boolean], optional)
        if ($DFBit) { $cmdESXCLIArgs.df = $DFBit } #([boolean], optional)
        if ($TTL) { $cmdESXCLIArgs.ttl = $TTL }   #([long], optional)
        if ($Count) { $cmdESXCLIArgs.count = $Count }       #([long], optional)
        if ($NetStack) { $cmdESXCLIArgs.netstack = $NetStack }  #([string], optional)        
        if ($Size) { $cmdESXCLIArgs.size = $Size }         #([long], optional)
        if ($interface) { $cmdESXCLIArgs.interface = $Interface }   #([string], optional)
        if ($isIPv4 -eq $false) {} else { $cmdESXCLIArgs.ipv4 = $isIPv4 }        #([boolean], optional)
        if ($isIPv6 -eq $false) {} else { $cmdESXCLIArgs.ipv6 = $isIPv6 }        #([boolean], optional)

        $ret = $cmdESXcli.network.diag.ping.Invoke($cmdESXcliArgs)
        
        if ($ret.summary.PacketLost -gt 0) {
            Write-Warning -Message ('IP {0} not reachable, or missing packets!' -f $ip)
        }
    
        $ret.summary
    }
}

