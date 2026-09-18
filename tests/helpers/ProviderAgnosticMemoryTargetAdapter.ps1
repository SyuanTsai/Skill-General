# SPDX-FileCopyrightText: 2026 SyuanTsai
# SPDX-License-Identifier: Apache-2.0

function New-ProviderAgnosticMemoryAdapterDouble {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Spec
    )

    $adapter = [pscustomobject]@{
        AdapterId = [string]$Spec.adapterId
        Spec = $Spec
        Calls = [System.Collections.Generic.List[string]]::new()
        ActivationRequirementsInspected = $false
        CapabilityInspected = $false
        StoredContent = $null
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name InspectActivation -Value {
        [void]$this.Calls.Add('activation')
        $this.ActivationRequirementsInspected = $true
        $activationProperty = $this.Spec.PSObject.Properties['activation']
        $activation = if ($null -eq $activationProperty) { $null } else { $activationProperty.Value }
        $verifiedProperty = if ($null -eq $activation) { $null } else { $activation.PSObject.Properties['verified'] }
        $readyProperty = if ($null -eq $activation) { $null } else { $activation.PSObject.Properties['ready'] }
        $ready = $null -ne $readyProperty -and [bool]$readyProperty.Value
        $verified = if ($null -eq $verifiedProperty) { $ready } else { [bool]$verifiedProperty.Value }
        return [pscustomobject]@{ Ready = $ready; Verified = $verified }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name InspectCapability -Value {
        [void]$this.Calls.Add('capability')
        $this.CapabilityInspected = $true
        $capabilityProperty = $this.Spec.PSObject.Properties['capability']
        $capability = if ($null -eq $capabilityProperty) { $null } else { $capabilityProperty.Value }
        return [pscustomobject]@{
            Supported = $null -ne $capability -and [bool]$capability.supported
            Configured = $null -ne $capability -and [bool]$capability.configured
            Authorized = $null -ne $capability -and [bool]$capability.authorized
            Available = $null -ne $capability -and [bool]$capability.available
        }
    }

    $adapter | Add-Member -MemberType ScriptMethod -Name WriteAndReadBack -Value {
        param([object]$Content)

        [void]$this.Calls.Add('content-read')
        [void]$this.Calls.Add('content-write')
        $this.StoredContent = $Content
        [void]$this.Calls.Add('readback')
        $readbackProperty = $this.Spec.PSObject.Properties['readbackMatches']
        return $null -ne $readbackProperty -and [bool]$readbackProperty.Value
    }

    return $adapter
}

function Get-ProviderAgnosticBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Bindings,
        [Parameter(Mandatory)]
        [psobject]$Target
    )

    foreach ($binding in $Bindings) {
        $matches =
            [string]$binding.targetId -ceq [string]$Target.targetId -and
            [string]$binding.selectionScope -ceq [string]$Target.selectionScope -and
            [string]$binding.resource -ceq [string]$Target.resource -and
            [string]$binding.location -ceq [string]$Target.location
        if ($matches) {
            return [string]$binding.adapterId
        }
    }
    return $null
}

function Invoke-ProviderAgnosticMemoryTargetSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Target,
        [Parameter(Mandatory)]
        [object[]]$Bindings,
        [Parameter(Mandatory)]
        [object[]]$Adapters,
        [Parameter(Mandatory)]
        [object]$Content,
        [switch]$AttemptProductionWrite
    )

    $requiredTargetFields = @('targetId', 'selectionScope', 'resource', 'location')
    $targetIsComplete = @($requiredTargetFields | Where-Object {
        $property = $Target.PSObject.Properties[$_]
        $null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)
    }).Count -eq 0
    $binding = if ($targetIsComplete) {
        Get-ProviderAgnosticBinding -Bindings $Bindings -Target $Target
    } else {
        $null
    }
    $adapterById = @{}
    foreach ($adapter in $Adapters) {
        $adapterById[[string]$adapter.AdapterId] = $adapter
    }

    $result = [ordered]@{
        SelectionStatus = 'unbound'
        SelectedAdapterId = $null
        ProductionStatus = $null
        FailureCategory = $null
        Durable = $false
        ContentRead = $false
        ContentWrite = $false
        Calls = @()
    }

    if ([string]::IsNullOrWhiteSpace($binding) -or -not $adapterById.ContainsKey($binding)) {
        return [pscustomobject]$result
    }

    $adapter = $adapterById[$binding]
    $result.SelectionStatus = 'selected'
    $result.SelectedAdapterId = [string]$adapter.AdapterId
    [void]$adapter.Calls.Add('selection')

    if (-not $AttemptProductionWrite) {
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }

    $activation = $adapter.InspectActivation()
    if (-not $activation.Ready -or -not $activation.Verified) {
        $result.ProductionStatus = 'activation-not-ready'
        $result.FailureCategory = 'unconfigured'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }

    $capability = $adapter.InspectCapability()
    if (-not $capability.Supported) {
        $result.ProductionStatus = 'unsupported'
        $result.FailureCategory = 'unsupported'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }
    if (-not $capability.Configured) {
        $result.ProductionStatus = 'unconfigured'
        $result.FailureCategory = 'unconfigured'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }
    if (-not $capability.Authorized) {
        $result.ProductionStatus = 'denied'
        $result.FailureCategory = 'denied'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }
    if (-not $capability.Available) {
        $result.ProductionStatus = 'unavailable'
        $result.FailureCategory = 'unavailable'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }

    $result.ContentRead = $true
    $result.ContentWrite = $true
    $readbackMatches = $adapter.WriteAndReadBack($Content)
    if (-not $readbackMatches) {
        $result.ProductionStatus = 'unverified-write-or-readback'
        $result.FailureCategory = 'unverified-write-or-readback'
        $result.Calls = @($adapter.Calls.ToArray())
        return [pscustomobject]$result
    }

    $result.ProductionStatus = 'durable'
    $result.Durable = $true
    $result.Calls = @($adapter.Calls.ToArray())
    return [pscustomobject]$result
}
