Set-StrictMode -Version Latest

function New-FeloErrorResult {
    param(
        [Parameter(Mandatory = $true)]
        [DateTimeOffset] $AsOf,

        [Parameter(Mandatory = $true)]
        [string] $ErrorCode
    )

    return [pscustomobject][ordered]@{
        status = 'error'
        asOf = $AsOf.ToString('o')
        error = $ErrorCode
    }
}

function ConvertTo-FeloTruncatedText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 10000)]
        [int] $MaximumTextElements
    )

    $textElementIndexes = [System.Globalization.StringInfo]::ParseCombiningCharacters($Text)
    if ($textElementIndexes.Count -le $MaximumTextElements) {
        return [pscustomobject]@{
            Text = $Text
            Truncated = $false
        }
    }

    return [pscustomobject]@{
        Text = $Text.Substring(0, $textElementIndexes[$MaximumTextElements])
        Truncated = $true
    }
}

function Test-FeloPublicIpAddress {
    param([Parameter(Mandatory = $true)][Net.IPAddress] $Address)

    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }

    if ([Net.IPAddress]::IsLoopback($Address)) {
        return $false
    }

    $bytes = $Address.GetAddressBytes()
    if ($Address.AddressFamily -eq [Net.Sockets.AddressFamily]::InterNetwork) {
        if ($bytes[0] -eq 0 -or
            $bytes[0] -eq 10 -or
            ($bytes[0] -eq 100 -and ($bytes[1] -band 0xC0) -eq 64) -or
            ($bytes[0] -eq 169 -and $bytes[1] -eq 254) -or
            ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 168) -or
            ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -in @(0, 2)) -or
            ($bytes[0] -eq 198 -and $bytes[1] -in @(18, 19)) -or
            ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) -or
            ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) -or
            $bytes[0] -ge 224) {
            return $false
        }

        return $true
    }

    if ($Address.Equals([Net.IPAddress]::IPv6Any) -or
        $Address.Equals([Net.IPAddress]::IPv6None) -or
        $Address.IsIPv6LinkLocal -or
        $Address.IsIPv6Multicast -or
        $Address.IsIPv6SiteLocal -or
        ($bytes[0] -band 0xFE) -eq 0xFC -or
        ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8)) {
        return $false
    }

    return $true
}

function ConvertTo-FeloNormalizedUrl {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string] $Url)

    if ([string]::IsNullOrWhiteSpace($Url) -or $Url.Length -gt 4096) {
        return $null
    }

    $uri = $null
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref] $uri)) {
        return $null
    }

    if ($uri.Scheme -notin @([Uri]::UriSchemeHttp, [Uri]::UriSchemeHttps)) {
        return $null
    }

    if (-not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.Query -match '(?i)(?:^\?|&)(?:access[_-]?token|api[_-]?key|auth(?:orization)?|credential|signature|sig|x-amz-(?:credential|signature|security-token))=') {
        return $null
    }

    $host = $uri.DnsSafeHost.TrimEnd('.').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($host) -or
        $host -eq 'localhost' -or
        $host.EndsWith('.localhost', [StringComparison]::Ordinal) -or
        $host.EndsWith('.local', [StringComparison]::Ordinal) -or
        $host.EndsWith('.internal', [StringComparison]::Ordinal) -or
        ($uri.HostNameType -eq [UriHostNameType]::Dns -and -not $host.Contains('.'))) {
        return $null
    }

    $ipAddress = $null
    if ([Net.IPAddress]::TryParse($host, [ref] $ipAddress) -and -not (Test-FeloPublicIpAddress -Address $ipAddress)) {
        return $null
    }

    $builder = [UriBuilder]::new($uri)
    $builder.Fragment = ''
    $builder.Host = $host
    if (($builder.Scheme -eq [Uri]::UriSchemeHttp -and $builder.Port -eq 80) -or
        ($builder.Scheme -eq [Uri]::UriSchemeHttps -and $builder.Port -eq 443)) {
        $builder.Port = -1
    }

    return $builder.Uri.AbsoluteUri
}

function ConvertFrom-FeloJsonOutput {
    param([Parameter(Mandatory = $true)][string] $RawOutput)

    $trimmedOutput = $RawOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedOutput)) {
        return $null
    }

    try {
        return $trimmedOutput | ConvertFrom-Json -Depth 30 -ErrorAction Stop
    }
    catch {
        $firstBrace = $trimmedOutput.IndexOf('{')
        $lastBrace = $trimmedOutput.LastIndexOf('}')
        if ($firstBrace -lt 0 -or $lastBrace -lt $firstBrace) {
            return $null
        }

        try {
            $jsonCandidate = $trimmedOutput.Substring($firstBrace, $lastBrace - $firstBrace + 1)
            return $jsonCandidate | ConvertFrom-Json -Depth 30 -ErrorAction Stop
        }
        catch {
            return $null
        }
    }
}

function ConvertTo-FeloCompactResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $RawOutput,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset] $AsOf,

        [ValidateRange(1, 10000)]
        [int] $SummaryCharacterLimit = 800,

        [ValidateRange(1, 100)]
        [int] $SourceLimit = 5,

        [ValidateRange(1, 1000)]
        [int] $SourceTitleCharacterLimit = 200
    )

    $response = ConvertFrom-FeloJsonOutput -RawOutput $RawOutput
    if ($null -eq $response) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'invalid-response'
    }

    $statusProperty = $response.PSObject.Properties['status']
    $dataProperty = $response.PSObject.Properties['data']
    if ($null -eq $statusProperty -or $null -eq $dataProperty -or $null -eq $dataProperty.Value) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'invalid-response'
    }

    $statusValue = [string] $statusProperty.Value
    if ($statusValue -notin @('200', 'ok')) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'request-failed'
    }

    $data = $dataProperty.Value
    $answerProperty = $data.PSObject.Properties['answer']
    if ($null -eq $answerProperty) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'invalid-response'
    }

    $answer = [string] $answerProperty.Value
    if ([string]::IsNullOrWhiteSpace($answer)) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'invalid-response'
    }

    $sources = [System.Collections.Generic.List[object]]::new()
    $seenUrls = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sourceTitlesWereTruncated = $false
    $resourcesProperty = $data.PSObject.Properties['resources']
    $resources = if ($null -eq $resourcesProperty) { @() } else { @($resourcesProperty.Value) }
    foreach ($resource in $resources) {
        if ($null -eq $resource) {
            continue
        }

        $titleProperty = $resource.PSObject.Properties['title']
        $linkProperty = $resource.PSObject.Properties['link']
        $title = if ($null -eq $titleProperty) { '' } else { [string] $titleProperty.Value }
        $link = if ($null -eq $linkProperty) { '' } else { [string] $linkProperty.Value }
        $normalizedUrl = ConvertTo-FeloNormalizedUrl -Url $link
        if ([string]::IsNullOrWhiteSpace($title) -or $null -eq $normalizedUrl) {
            continue
        }

        if ($seenUrls.Add($normalizedUrl)) {
            $titleResult = ConvertTo-FeloTruncatedText -Text $title.Trim() -MaximumTextElements $SourceTitleCharacterLimit
            $sourceTitlesWereTruncated = $sourceTitlesWereTruncated -or $titleResult.Truncated
            $sources.Add([pscustomobject][ordered]@{
                title = $titleResult.Text
                url = $normalizedUrl
            })
        }
    }

    if ($sources.Count -eq 0) {
        return New-FeloErrorResult -AsOf $AsOf -ErrorCode 'no-sources'
    }

    $summaryResult = ConvertTo-FeloTruncatedText -Text $answer.Trim() -MaximumTextElements $SummaryCharacterLimit
    $sourcesWereTruncated = $sources.Count -gt $SourceLimit
    $limitedSources = @($sources | Select-Object -First $SourceLimit)

    return [pscustomobject][ordered]@{
        status = 'ok'
        asOf = $AsOf.ToString('o')
        summary = $summaryResult.Text
        sources = $limitedSources
        truncated = [bool] ($summaryResult.Truncated -or $sourcesWereTruncated -or $sourceTitlesWereTruncated)
    }
}

function Invoke-FeloChildProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList,

        [ValidateRange(1, 605)]
        [int] $TimeoutSeconds = 60
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardOutputEncoding = $utf8Encoding
    $startInfo.StandardErrorEncoding = $utf8Encoding
    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw 'The FELO child process could not be started.'
        }

        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) {
            $process.Kill($true)
            $process.WaitForExit()
        }

        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()
        $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }

        return [pscustomobject]@{
            ExitCode = $exitCode
            TimedOut = $timedOut
            StandardOutput = $standardOutput
            StandardError = $standardError
        }
    }
    finally {
        $process.Dispose()
    }
}

function New-FeloSearchQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [ValidateRange(1, 10000)]
        [int] $SummaryCharacterLimit = 800
    )

    return @"
$Query

Answer in the same language as the query. Keep the answer within $SummaryCharacterLimit Unicode characters and support it with public sources.
"@.Trim()
}

function Resolve-FeloCliInvocation {
    $nodeCommand = Get-Command node.exe, node -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $nodeCommand) {
        return $null
    }

    $feloCommand = Get-Command felo.cmd, felo -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $feloCommand) {
        return $null
    }

    $npmPrefix = Split-Path -Parent $feloCommand.Source
    $packageRoot = Join-Path $npmPrefix 'node_modules\felo-ai'
    $packagePath = Join-Path $packageRoot 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        return $null
    }

    try {
        $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        $relativeCliPath = [string] $package.bin.felo
        $cliPath = Join-Path $packageRoot $relativeCliPath
    }
    catch {
        return $null
    }

    if ([string]::IsNullOrWhiteSpace($relativeCliPath) -or -not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
        return $null
    }

    return [pscustomobject]@{
        FilePath = $nodeCommand.Source
        PrefixArguments = @($cliPath)
    }
}

function Get-FeloFailureClassification {
    param([AllowEmptyString()][string] $StandardError)

    if ($StandardError -match '(?i)invalid[_ -]?api[_ -]?key|unauthori[sz]ed|\b401\b|api key.+not configured') {
        return 'authentication'
    }

    if ($StandardError -match '(?i)quota|insufficient|rate limit|\b402\b|\b429\b') {
        return 'quota-unavailable'
    }

    return 'request-failed'
}

function Add-FeloRetryMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [psobject] $Result,

        [Parameter(Mandatory = $true)]
        [bool] $Retried
    )

    $Result | Add-Member -NotePropertyName 'retried' -NotePropertyValue $Retried
    return $Result
}

function Invoke-FeloSearchAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject] $Invocation,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList,

        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 60,

        [ValidateRange(1, 10000)]
        [int] $SummaryCharacterLimit = 800,

        [ValidateRange(1, 100)]
        [int] $SourceLimit = 5
    )

    $asOf = [DateTimeOffset]::Now
    try {
        $processResult = Invoke-FeloChildProcess `
            -FilePath $Invocation.FilePath `
            -ArgumentList $ArgumentList `
            -TimeoutSeconds ($TimeoutSeconds + 5)
    }
    catch {
        return New-FeloErrorResult -AsOf $asOf -ErrorCode 'cli-unavailable'
    }

    if ($processResult.TimedOut) {
        return New-FeloErrorResult -AsOf $asOf -ErrorCode 'timeout'
    }

    if ($processResult.ExitCode -ne 0) {
        $classification = Get-FeloFailureClassification -StandardError $processResult.StandardError
        return New-FeloErrorResult -AsOf $asOf -ErrorCode $classification
    }

    return ConvertTo-FeloCompactResult `
        -RawOutput $processResult.StandardOutput `
        -AsOf $asOf `
        -SummaryCharacterLimit $SummaryCharacterLimit `
        -SourceLimit $SourceLimit
}

function Invoke-FeloSearch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Query,

        [ValidateRange(1, 600)]
        [int] $TimeoutSeconds = 60,

        [ValidateRange(1, 10000)]
        [int] $SummaryCharacterLimit = 800,

        [ValidateRange(1, 100)]
        [int] $SourceLimit = 5
    )

    $invocation = Resolve-FeloCliInvocation
    if ($null -eq $invocation) {
        $result = New-FeloErrorResult -AsOf ([DateTimeOffset]::Now) -ErrorCode 'cli-unavailable'
        return Add-FeloRetryMetadata -Result $result -Retried $false
    }

    $feloQuery = New-FeloSearchQuery -Query $Query -SummaryCharacterLimit $SummaryCharacterLimit
    $arguments = @($invocation.PrefixArguments) + @(
        'search',
        $feloQuery,
        '--json',
        '--timeout',
        [string] $TimeoutSeconds
    )

    $attemptParameters = @{
        Invocation = $invocation
        ArgumentList = $arguments
        TimeoutSeconds = $TimeoutSeconds
        SummaryCharacterLimit = $SummaryCharacterLimit
        SourceLimit = $SourceLimit
    }
    $result = Invoke-FeloSearchAttempt @attemptParameters
    if ($result.status -ne 'error' -or $result.error -ne 'request-failed') {
        return Add-FeloRetryMetadata -Result $result -Retried $false
    }

    $retryDelayMilliseconds = Get-Random -Minimum 1000 -Maximum 2001
    Start-Sleep -Milliseconds $retryDelayMilliseconds
    $result = Invoke-FeloSearchAttempt @attemptParameters
    return Add-FeloRetryMetadata -Result $result -Retried $true
}

Export-ModuleMember -Function @(
    'ConvertTo-FeloCompactResult',
    'Invoke-FeloChildProcess',
    'Invoke-FeloSearch',
    'New-FeloSearchQuery'
)
