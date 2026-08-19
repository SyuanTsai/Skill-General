$script:SkillRoot = Join-Path $PSScriptRoot '..\.agents\skills\search-with-felo'
$script:ModulePath = Join-Path $script:SkillRoot 'scripts\SearchWithFelo.psm1'

Import-Module $script:ModulePath -Force

Describe 'search-with-felo compact wrapper' {
    It 'T010_projects_a_success_response_to_the_compact_allowlist' {
        $rawResponse = @'
Searching...
{
  "status": 200,
  "code": 0,
  "request_id": "request-private",
  "data": {
    "id": "answer-private",
    "message_id": "message-private",
    "answer": "A compact public answer.",
    "query_analysis": { "queries": ["expanded query"] },
    "resources": [
      { "title": "One", "link": "https://example.com/one", "snippet": "private snippet one" },
      { "title": "One duplicate", "link": "https://EXAMPLE.com/one#section", "snippet": "private duplicate" },
      { "title": "Two", "link": "https://example.com/two", "snippet": "private snippet two" },
      { "title": "Three", "link": "https://example.com/three", "snippet": "private snippet three" },
      { "title": "Four", "link": "https://example.com/four", "snippet": "private snippet four" },
      { "title": "Five", "link": "https://example.com/five", "snippet": "private snippet five" },
      { "title": "Six", "link": "https://example.com/six", "snippet": "private snippet six" }
    ]
  }
}
'@
        $asOf = [DateTimeOffset]::Parse('2026-08-10T12:00:00+08:00')
        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf $asOf
        $json = $result | ConvertTo-Json -Depth 5 -Compress
        ($result.PSObject.Properties.Name -join ',') | Should -Be 'status,asOf,summary,sources,truncated'
        $result.status | Should -Be 'ok'
        $result.asOf | Should -Be '2026-08-10T12:00:00.0000000+08:00'
        $result.summary | Should -Be 'A compact public answer.'
        @($result.sources).Count | Should -Be 5
        $result.sources[0].title | Should -Be 'One'
        $result.sources[0].url | Should -Be 'https://example.com/one'
        $result.truncated | Should -Be $true
        $json | Should -Not -Match 'request-private|answer-private|message-private|query_analysis|snippet|expanded query'
    }

    It 'T020_truncates_summary_by_Unicode_text_elements' {
        $answer = ('a' * 799) + "👩‍💻" + 'tail'
        $rawResponse = [ordered]@{
            status = 200
            data = [ordered]@{
                answer = $answer
                resources = @([ordered]@{ title = 'Source'; link = 'https://example.com/source' })
            }
        } | ConvertTo-Json -Depth 5
        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::UtcNow)
        $textElementCount = [System.Globalization.StringInfo]::ParseCombiningCharacters($result.summary).Count
        $textElementCount | Should -Be 800
        $result.summary.EndsWith("👩‍💻") | Should -Be $true
        $result.summary | Should -Not -Match 'tail'
        $result.truncated | Should -Be $true
    }

    It 'T030_returns_a_safe_error_for_invalid_output' {
        $rawResponse = 'Searching failed with private diagnostic details.'
        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::Parse('2026-08-10T12:00:00Z'))
        $json = $result | ConvertTo-Json -Compress
        ($result.PSObject.Properties.Name -join ',') | Should -Be 'status,asOf,error'
        $result.status | Should -Be 'error'
        $result.error | Should -Be 'invalid-response'
        $json | Should -Not -Match 'private diagnostic'
    }

    It 'T035_returns_a_safe_error_when_the_response_schema_changes' {
        $rawResponse = '{"unexpected":"private-schema-value"}'
        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::Parse('2026-08-10T12:00:00Z'))
        $json = $result | ConvertTo-Json -Compress
        $result.status | Should -Be 'error'
        $result.error | Should -Be 'invalid-response'
        $json | Should -Not -Match 'private-schema-value'
    }

    It 'T040_returns_a_safe_error_when_no_sources_are_usable' {
        $rawResponse = [ordered]@{
            status = 200
            data = [ordered]@{
                answer = 'Uncited answer'
                resources = @(
                    [ordered]@{ title = 'Missing URL'; link = '' },
                    [ordered]@{ title = 'Local file'; link = 'file:///private/report.txt' }
                )
            }
        } | ConvertTo-Json -Depth 5
        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::UtcNow)
        $result.status | Should -Be 'error'
        $result.error | Should -Be 'no-sources'
    }

    It 'T045_rejects_credentialed_or_nonpublic_source_URLs' {
        $rawResponse = [ordered]@{
            status = 200
            data = [ordered]@{
                answer = 'Public answer'
                resources = @(
                    [ordered]@{ title = 'User info'; link = 'https://user:secret@example.com/private' },
                    [ordered]@{ title = 'Loopback'; link = 'http://127.0.0.1/admin' },
                    [ordered]@{ title = 'IPv6 loopback'; link = 'http://[::1]/admin' },
                    [ordered]@{ title = 'Link local'; link = 'http://169.254.169.254/latest/meta-data' },
                    [ordered]@{ title = 'Private network'; link = 'http://10.0.0.1/admin' },
                    [ordered]@{ title = 'Single-label host'; link = 'http://intranet/admin' },
                    [ordered]@{ title = 'Sensitive query'; link = 'https://example.com/private?access_token=secret' },
                    [ordered]@{ title = 'Generic token query'; link = 'https://example.com/private?token=secret' },
                    [ordered]@{ title = 'Encoded secret query'; link = 'https://example.com/private?client%5Fsecret=secret' },
                    [ordered]@{ title = 'Password query'; link = 'https://example.com/private?password=secret' },
                    [ordered]@{ title = 'Public source'; link = 'https://example.com/public' }
                )
            }
        } | ConvertTo-Json -Depth 5

        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::UtcNow)
        $result.status | Should -Be 'ok'
        @($result.sources).Count | Should -Be 1
        $result.sources[0].title | Should -Be 'Public source'
        $result.sources[0].url | Should -Be 'https://example.com/public'
        ($result | ConvertTo-Json -Depth 5 -Compress) |
            Should -Not -Match 'secret|127\.0\.0\.1|::1|169\.254\.169\.254|10\.0\.0\.1|intranet'
    }

    It 'T047_limits_source_titles_and_reports_truncation' {
        $rawResponse = [ordered]@{
            status = 200
            data = [ordered]@{
                answer = 'Public answer'
                resources = @(
                    [ordered]@{ title = ('x' * 250); link = 'https://example.com/public' }
                )
            }
        } | ConvertTo-Json -Depth 5

        $result = ConvertTo-FeloCompactResult -RawOutput $rawResponse -AsOf ([DateTimeOffset]::UtcNow)
        $result.status | Should -Be 'ok'
        $result.sources[0].title.Length | Should -Be 200
        $result.truncated | Should -Be $true
    }

    It 'T050_captures_child_process_stdout_and_stderr_separately' {
        $fakeScript = Join-Path $TestDrive 'fake-felo.ps1'
        Set-Content -LiteralPath $fakeScript -Encoding UTF8 -Value @'
[Console]::Out.WriteLine('{"status":200}')
[Console]::Error.WriteLine('private stderr diagnostic')
exit 0
'@
        $result = Invoke-FeloChildProcess `
            -FilePath (Get-Command pwsh -ErrorAction Stop).Source `
            -ArgumentList @('-NoProfile', '-File', $fakeScript) `
            -TimeoutSeconds 5
        $result.ExitCode | Should -Be 0
        $result.TimedOut | Should -Be $false
        $result.StandardOutput.Trim() | Should -Be '{"status":200}'
        $result.StandardError.Trim() | Should -Be 'private stderr diagnostic'
    }

    It 'T055_accepts_the_public_maximum_plus_child_process_buffer' {
        $fakeScript = Join-Path $TestDrive 'fake-felo-timeout-boundary.ps1'
        Set-Content -LiteralPath $fakeScript -Encoding UTF8 -Value 'exit 0'
        $result = Invoke-FeloChildProcess `
            -FilePath (Get-Command pwsh -ErrorAction Stop).Source `
            -ArgumentList @('-NoProfile', '-File', $fakeScript) `
            -TimeoutSeconds 605
        $result.ExitCode | Should -Be 0
        $result.TimedOut | Should -Be $false
    }

    It 'UnitT55_decodes_child_process_stdout_and_stderr_as_UTF8' {
        $fakeScript = Join-Path $TestDrive 'fake-felo-utf8.ps1'
        Set-Content -LiteralPath $fakeScript -Encoding UTF8 -Value @'
$stdoutBytes = [System.Text.Encoding]::UTF8.GetBytes('繁體中文摘要')
$stderrBytes = [System.Text.Encoding]::UTF8.GetBytes('診斷訊息')
[Console]::OpenStandardOutput().Write($stdoutBytes, 0, $stdoutBytes.Length)
[Console]::OpenStandardError().Write($stderrBytes, 0, $stderrBytes.Length)
'@
        $originalOutputEncoding = [Console]::OutputEncoding
        try {
            [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(950)
            $result = Invoke-FeloChildProcess `
                -FilePath (Get-Command pwsh -ErrorAction Stop).Source `
                -ArgumentList @('-NoProfile', '-File', $fakeScript) `
                -TimeoutSeconds 5
        }
        finally {
            [Console]::OutputEncoding = $originalOutputEncoding
        }
        $result.StandardOutput | Should -Be '繁體中文摘要'
        $result.StandardError | Should -Be '診斷訊息'
    }

    It 'T060_adds_the_compact_answer_instruction_to_the_query' {
        $query = 'Compare current public transport options.'
        $result = New-FeloSearchQuery -Query $query -SummaryCharacterLimit 800
        $result | Should -Match ([regex]::Escape($query))
        $result | Should -Match 'same language'
        $result | Should -Match '800'
    }

    It 'UnitT65_returns_retried_false_when_the_first_request_succeeds' {
        InModuleScope SearchWithFelo {
            Mock Resolve-FeloCliInvocation {
                [pscustomobject]@{ FilePath = 'node'; PrefixArguments = @('felo.js') }
            }
            Mock Invoke-FeloChildProcess {
                [pscustomobject]@{
                    ExitCode = 0
                    TimedOut = $false
                    StandardOutput = '{"status":200,"data":{"answer":"Answer","resources":[{"title":"Source","link":"https://example.com/source"}]}}'
                    StandardError = ''
                }
            }
            Mock Start-Sleep {}
            $result = Invoke-FeloSearch -Query 'Public query'
            Should -Invoke Invoke-FeloChildProcess -Times 1 -Exactly -Scope It
            Should -Invoke Start-Sleep -Times 0 -Exactly -Scope It
            ($result.PSObject.Properties.Name -join ',') | Should -Be 'status,asOf,summary,sources,truncated,retried'
            $result.status | Should -Be 'ok'
            $result.retried | Should -Be $false
        }
    }

    It 'UnitT70_retries_request_failed_once_and_returns_the_success' {
        InModuleScope SearchWithFelo {
            $script:invocationCount = 0
            Mock Resolve-FeloCliInvocation {
                [pscustomobject]@{ FilePath = 'node'; PrefixArguments = @('felo.js') }
            }
            Mock Invoke-FeloChildProcess {
                $script:invocationCount++
                if ($script:invocationCount -eq 1) {
                    return [pscustomobject]@{
                        ExitCode = 1
                        TimedOut = $false
                        StandardOutput = ''
                        StandardError = 'Temporary provider failure.'
                    }
                }
                return [pscustomobject]@{
                    ExitCode = 0
                    TimedOut = $false
                    StandardOutput = '{"status":200,"data":{"answer":"Recovered","resources":[{"title":"Source","link":"https://example.com/source"}]}}'
                    StandardError = ''
                }
            }
            Mock Start-Sleep {}
            $result = Invoke-FeloSearch -Query 'Public query'
            Should -Invoke Invoke-FeloChildProcess -Times 2 -Exactly -Scope It
            Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It -ParameterFilter {
                $Milliseconds -ge 1000 -and $Milliseconds -le 2000
            }
            $result.status | Should -Be 'ok'
            $result.summary | Should -Be 'Recovered'
            $result.retried | Should -Be $true
        }
    }

    It 'UnitT80_stops_after_one_request_failed_retry' {
        InModuleScope SearchWithFelo {
            Mock Resolve-FeloCliInvocation {
                [pscustomobject]@{ FilePath = 'node'; PrefixArguments = @('felo.js') }
            }
            Mock Invoke-FeloChildProcess {
                [pscustomobject]@{
                    ExitCode = 1
                    TimedOut = $false
                    StandardOutput = ''
                    StandardError = 'Temporary provider failure.'
                }
            }
            Mock Start-Sleep {}
            $result = Invoke-FeloSearch -Query 'Public query'
            Should -Invoke Invoke-FeloChildProcess -Times 2 -Exactly -Scope It
            Should -Invoke Start-Sleep -Times 1 -Exactly -Scope It
            ($result.PSObject.Properties.Name -join ',') | Should -Be 'status,asOf,error,retried'
            $result.status | Should -Be 'error'
            $result.error | Should -Be 'request-failed'
            $result.retried | Should -Be $true
        }
    }

    It 'UnitT90_does_not_retry_a_classified_failure' {
        InModuleScope SearchWithFelo {
            Mock Resolve-FeloCliInvocation {
                [pscustomobject]@{ FilePath = 'node'; PrefixArguments = @('felo.js') }
            }
            Mock Invoke-FeloChildProcess {
                [pscustomobject]@{
                    ExitCode = 1
                    TimedOut = $false
                    StandardOutput = ''
                    StandardError = 'Unauthorized (401).'
                }
            }
            Mock Start-Sleep {}
            $result = Invoke-FeloSearch -Query 'Public query'
            Should -Invoke Invoke-FeloChildProcess -Times 1 -Exactly -Scope It
            Should -Invoke Start-Sleep -Times 0 -Exactly -Scope It
            $result.status | Should -Be 'error'
            $result.error | Should -Be 'authentication'
            $result.retried | Should -Be $false
        }
    }
}
