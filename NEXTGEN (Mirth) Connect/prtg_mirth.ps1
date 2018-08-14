#MIT License
#
#Copyright (c) 2018, Johannes Liegert
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
#
# PRTG monitoring script for NEXTGEN (Mirth) Connect API
# Author: Johannes Liegert
# Version: 1.0


param(
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Hostname,
    [Parameter(Mandatory = $true, Position = 2)]
    [int]$Port,
    [Parameter(Mandatory = $false, Position = 3)]
    [string]$Username,
    [Parameter(Mandatory = $false, Position = 4)]
    [string]$Password,
    [Parameter(Mandatory = $true, Position = 5)]
    [string]$Type,
    [Parameter(Mandatory = $false, Position = 6)]
    [string]$ChannelID
)

function Init() {

    $error.Clear()

    $Password = ConvertTo-SecureString -String $Password -AsPlainText -Force

    if ($Debug) {
        Write-Verbose "Used parameter:"
        Write-Verbose "Host: $Hostname"
        Write-Verbose "User: $Username"
        Write-Verbose "Password: $Password"
        Write-Verbose "Debug:$Debug"
    }

    if (-not ([System.Management.Automation.PSTypeName]'ServerCertificateValidationCallback').Type) {
        $certCallback = @"
    using System;
    using System.Net;
    using System.Net.Security;
    using System.Security.Cryptography.X509Certificates;
    public class ServerCertificateValidationCallback
    {
        public static void Ignore()
        {
            if(ServicePointManager.ServerCertificateValidationCallback ==null)
            {
                ServicePointManager.ServerCertificateValidationCallback += 
                    delegate
                    (
                        Object obj, 
                        X509Certificate certificate, 
                        X509Chain chain, 
                        SslPolicyErrors errors
                    )
                    {
                        return true;
                    };
            }
        }
    }
"@
        Add-Type $certCallback
    }
    [ServerCertificateValidationCallback]::Ignore()
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

}
function Login() {
    Write-Verbose "Try to connect to Mirth API on $Hostname using User $Username."

    $Body = @{
        username = $Username
        password = $Password
    }

    $URI = "https://" + $Hostname + ":" + $Port + "/api/users/_login"

    Write-Verbose "Request URI"
    Write-Verbose "$URI"
    
    try {
        $session = $null
        $LoginResponse = Invoke-WebRequest $URI  -Body $Body -Method 'POST' -UseBasicParsing -ContentType "application/x-www-form-urlencoded" -SessionVariable 'session'   
        new-object psobject -property @{
            session  = $session;
            response = $LoginResponse; 
        }
    }
    catch {
        WriteError $Error[0]
        Exit
    }
}
function Logout {
    Param(
        $session
    )
    $URI = "https://" + $Hostname + ":" + $Port + "/api/users/_logout"
   
    Write-Verbose "Try to call $URI at $Hostname using User $Username."
    Write-Verbose $session.Headers


    try {
        $LogoutResponse = Invoke-WebRequest $URI -WebSession $session -UseBasicParsing -Method 'POST' -ContentType 'application/xml'
    }
    catch {
        WriteError $Error[0]
        Exit
    }
}
function GetSystemStats {
    Param(
        $session
    )

    $URI = "https://" + $Hostname + ":" + $Port + "/api/system/stats"
  
    Write-Verbose "Try to call $URI at $Hostname using User $Username."
    
    try {
        $SystemResponse = Invoke-WebRequest $URI -WebSession $session -UseBasicParsing -Method 'GET' -ContentType 'application/xml' 
        $stats = [xml]$SystemResponse.Content 

        new-object psobject -property @{
            "CPU %"       = $stats."com.mirth.connect.model.systemstats".cpuusagepct;
            "Disk Free"   = $stats."com.mirth.connect.model.systemstats".diskfreebytes + ":" + $stats."com.mirth.connect.model.systemstats".disktotalbytes;
            "Memory Free" = $stats."com.mirth.connect.model.systemstats".freeMemoryBytes + ":" + $stats."com.mirth.connect.model.systemstats".maxMemoryBytes;
        }
    }
    catch {
        WriteError $Error[0]
        Exit
    }
}
function GetChannels {
    Param(
        $session
    )

    $URI = "https://" + $Hostname + ":" + $Port + "/api/channels/statuses"

    Write-Verbose "Try to call $URI at $Hostname using User $Username."
    
    try {
        $ChannelResponse = Invoke-WebRequest $URI -WebSession $session -UseBasicParsing -Method 'GET' -ContentType 'application/xml' 
        [xml]$chan = [xml]$ChannelResponse.Content
        $dataset = ForEach ($item in $chan.list.dashboardStatus) {
            $ObjectProperties = @{
                "Name"      = $item.name
                "ChannelId" = $item.channelID
            }
            New-Object psobject -Property $ObjectProperties
        }
        return $dataset
    }
    catch {
        WriteError $Error[0]
        Exit
    }
}
function GetChannelStats {
    Param(
        $session,
        $ChannelID
    )

    $URI = "https://" + $Hostname + ":" + $Port + "/api/channels/" + $ChannelID + "/statistics"

    Write-Verbose "Try to call $URI at $Hostname using User $Username."

    try {
        $ChannelResponse = Invoke-WebRequest $URI -WebSession $session -UseBasicParsing -Method 'GET' -ContentType 'application/xml' 
        $stats = [xml]$ChannelResponse.Content
        $dataset = foreach ($item in $stats.channelstatistics) {
            $ObjectProperties = @{
                "Received" = $item.received 
                "Sent"     = $item.sent 
                "Error"    = $item.error 
                "Filtered" = $item.filtered 
                "Queued"   = $item.queued 
            }
            New-Object psobject -Property $ObjectProperties
        }
        return $dataset
       
        
    }
    catch {
        Write-Verbose "Error occured $Error[0]" 
        Exit
    }
}
function WriteResult {
    Param(
        $data
    )
    
    $XmlDocument = New-Object System.XML.XMLDocument
    $XmlRoot = $XmlDocument.CreateElement("prtg")
    $XmlDocument.appendChild($XmlRoot) | Out-Null

    if ($data) {        
        foreach ($channel in $data) {
            foreach ($prop in $channel.PSObject.Properties) {
                $XmlResult = $XmlRoot.appendChild($XmlDocument.CreateElement("result"))
                $XmlKey = $XmlDocument.CreateElement("channel")
                $XmlResult.AppendChild($XmlKey) | Out-Null

                $XmlValue = $XmlDocument.CreateTextNode($prop.Name)
                $XmlKey.AppendChild($XmlValue) | Out-Null

                $XmlKey = $XmlDocument.CreateElement("value")
                $XmlResult.AppendChild($XmlKey) | Out-Null
                $extract = ""
                if ($prop.value -match ":") {
                    $extract = ($prop.value -split ":")
                    $XmlValue = $XmlDocument.CreateTextNode($extract[0])
                    $XmlKey.AppendChild($XmlValue) | Out-Null
                }
                else {
                    $XmlValue = $XmlDocument.CreateTextNode($prop.value)
                    $XmlKey.AppendChild($XmlValue) | Out-Null
                }
               

                if ($prop.Name.ToLower() -match ("cpu")) {
                    $XmlKey = $XmlDocument.CreateElement("unit")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("CPU")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitmaxerror")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("95")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitmaxwarning")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("90")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitmode")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("1")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("primary")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("1")
                    $XmlKey.AppendChild($XmlValue) | Out-Null
                }
                elseif ($prop.Name.ToLower() -match ("disk")) {
                    
                    $XmlKey = $XmlDocument.CreateElement("unit")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("BytesDisk")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitminerror")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode([double]$extract[1] * 0.05)
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitminwarning")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode([double]$extract[1] * 0.1)
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitmode")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("1")
                    $XmlKey.AppendChild($XmlValue) | Out-Null
                }
                elseif ($prop.Name.ToLower() -match ("memory")) {
                    $XmlKey = $XmlDocument.CreateElement("unit")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("BytesDisk")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitminerror")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode(([double]$extract[1]) * 0.05)
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitminwarning")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode(([double]$extract[1]) * 0.1)
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("limitmode")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("1")
                    $XmlKey.AppendChild($XmlValue) | Out-Null
                }
                else {
                    $XmlKey = $XmlDocument.CreateElement("unit")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("Count")
                    $XmlKey.AppendChild($XmlValue) | Out-Null

                    $XmlKey = $XmlDocument.CreateElement("Mode")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("Difference")
                    $XmlKey.AppendChild($XmlValue) | Out-Null    
                    
                    $XmlKey = $XmlDocument.CreateElement("SpeedTime")
                    $XmlResult.AppendChild($XmlKey) | Out-Null
    
                    $XmlValue = $XmlDocument.CreateTextNode("Minute")
                    $XmlKey.AppendChild($XmlValue) | Out-Null  
                }
              
            }
        }
    }
    else {
        $XmlError = $XmlDocument.CreateElement("error")
        $XmlRoot.AppendChild($XmlError) | Out-Null

        $XmlErrorValue = $XmlDocument.CreateTextNode(1)
        $XmlError.AppendChild($XmlErrorValue) | Out-Null

        $XmlText = $XmlDocument.CreateElement("Text")
        $XmlRoot.AppendChild($XmlText) | Out-Null

        $XmlTextValue = $XmlDocument.CreateTextNode($MyError)
        $XmlText.AppendChild($XmlTextValue) | Out-Null
    }

    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $XmlWriter.Formatting = "indented"
    $XmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t" 
    $XmlDocument.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 

    Return $StringWriter.ToString() 
}
function WriteMeta {
    Param(
        $data
    )

    $XmlDocument = New-Object System.XML.XMLDocument
    $XmlRoot = $XmlDocument.CreateElement("prtg")
    $XmlDocument.appendChild($XmlRoot) | Out-Null

    if ($data) {        
        foreach ($channel in $data) {
            $XmlResult = $XmlRoot.appendChild($XmlDocument.CreateElement("item"))
            $XmlKey = $XmlDocument.CreateElement("name")
            $XmlResult.AppendChild($XmlKey) | Out-Null

            $XmlValue = $XmlDocument.CreateTextNode("Channel " + $channel.Name)
            $XmlKey.AppendChild($XmlValue) | Out-Null

            $XmlKey = $XmlDocument.CreateElement("exefile")
            $XmlResult.AppendChild($XmlKey) | Out-Null
            
            $XmlValue = $XmlDocument.CreateTextNode("prtg_mirth.ps1")
            $XmlKey.AppendChild($XmlValue) | Out-Null

            $XmlKey = $XmlDocument.CreateElement("params")
            $XmlResult.AppendChild($XmlKey) | Out-Null
            
            $XmlValue = $XmlDocument.CreateTextNode("%host $Port %linuxuser %linuxpassword `"channel`" " + $channel.ChannelId)
            $XmlKey.AppendChild($XmlValue) | Out-Null
        }
    }
    else {
        $XmlError = $XmlDocument.CreateElement("error")
        $XmlRoot.AppendChild($XmlError) | Out-Null

        $XmlErrorValue = $XmlDocument.CreateTextNode(1)
        $XmlError.AppendChild($XmlErrorValue) | Out-Null

        $XmlText = $XmlDocument.CreateElement("Text")
        $XmlRoot.AppendChild($XmlText) | Out-Null

        $XmlTextValue = $XmlDocument.CreateTextNode($MyError)
        $XmlText.AppendChild($XmlTextValue) | Out-Null
    }

    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $XmlWriter.Formatting = "indented"
    $XmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t" 
    $XmlDocument.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 

    Return $StringWriter.ToString() 
}

function WriteError {
    Param(
        $MyError
    )

    $XmlDocument = New-Object System.XML.XMLDocument
    $XmlRoot = $XmlDocument.CreateElement("prtg")
    $XmlDocument.appendChild($XmlRoot) | Out-Null


    $XmlError = $XmlDocument.CreateElement("error")
    $XmlRoot.AppendChild($XmlError) | Out-Null

    $XmlErrorValue = $XmlDocument.CreateTextNode(1)
    $XmlError.AppendChild($XmlErrorValue) | Out-Null

    $XmlText = $XmlDocument.CreateElement("Text")
    $XmlRoot.AppendChild($XmlText) | Out-Null

    $XmlTextValue = $XmlDocument.CreateTextNode($MyError)
    $XmlText.AppendChild($XmlTextValue) | Out-Null
    

    <# Format XML output #>
    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $XmlWriter.Formatting = "indented"
    $XmlWriter.Indentation = 1
    $XmlWriter.IndentChar = "`t" 
    $XmlDocument.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 

    Return $StringWriter.ToString()           
}

Write-Verbose "Init Script"

Init

Write-Verbose "Login User"

$call = Login

switch ($Type) {
    "meta" {
      
        Write-Verbose "Meta Channels"
      
        $channels = GetChannels $call.session

        WriteMeta $channels
    }
    "system" {
     
        Write-Verbose "Get SystemStats"
       
        $system = GetSystemStats $call.session
    
        WriteResult $system
    }
    "channel" {
  
        Write-Verbose "Get ChannelStats"
        
        $channelstats = GetChannelStats $call.session $ChannelID

        WriteResult $channelstats
    }
    Default {
     
        Write-Verbose "Logout User"
            
        Logout $call.session
        
    }
}

Write-Verbose "Logout User"
    
Logout $call.session




