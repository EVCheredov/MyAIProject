# Testomat.io MCP Helper v2.0
# Поддерживает кириллицу. Description в формате: ## Шаги / ## Ожидаемый результат / ## Тестовые данные
#
# Использование:
#   Рекомендуемый способ (Desc с разметкой как в эталоне 01392adb):
#     testomat_helper.ps1 -Action create -SuiteId "xxxx" -Title "Название" -Desc "## Шаги\n1. Действие\n\n## Ожидаемый результат\n- Результат\n\n## Тестовые данные\n- Параметр: значение"
#
#   Или с Steps (автоформат, "действие||ожидание"):
#     testomat_helper.ps1 -Action create -SuiteId "xxxx" -Title "Название" -Steps "Действие 1||ОР 1","Действие 2||ОР 2"

param(
    [string]$Action = "create",
    [string]$SuiteId = "",
    [string]$TestId = "",
    [string]$Title = "",
    [string]$Desc = "",          # Готовое описание (будет использовано как есть)
    [array]$Steps = @(),         # Шаги в формате "действие||ожидаемый результат"
    [array]$Preconds = @(),      # Предусловия (массив строк)
    [string]$Priority = "normal"
)

# === Конфигурация ===
$token = $env:TESTOMAT_TOKEN
if (-not $token) {
    $envFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile -Raw -Encoding UTF8
        if ($envContent -match 'TESTOMAT_TOKEN="([^"]+)"') { $token = $matches[1] }
    }
}
if (-not $token) { Write-Output '{"status":"error","message":"TESTOMAT_TOKEN not found"}'; exit 1 }

$url = "https://mcp.testomat.io/mcp/mytests-ed9d5"
$projectId = "mytests-ed9d5"
$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
    "Accept" = "application/json, text/event-stream"
    "x-project-id" = $projectId
}

# === Экранирование ===
function Escape-Unicode {
    param([string]$text)
    if ([string]::IsNullOrEmpty($text)) { return "" }
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $text.ToCharArray()) {
        $code = [int]$c
        if ($code -eq 10) { $sb.Append("\n") | Out-Null }
        elseif ($code -eq 13) { $sb.Append("\r") | Out-Null }
        elseif ($code -eq 34) { $sb.Append('\u0022') | Out-Null }
        elseif ($code -eq 92) { $sb.Append('\u005C') | Out-Null }
        elseif ($code -gt 127) { $sb.AppendFormat("\u{0:X4}", $code) | Out-Null }
        else { $sb.Append($c) | Out-Null }
    }
    return $sb.ToString()
}

# === Сборка description в формате эталонного кейса ===
function Build-Description {
    $parts = @()
    
    # Предусловия
    if ($Preconds -and $Preconds.Count -gt 0) {
        $parts += "## \u041F\u0440\u0435\u0434\u0443\u0441\u043B\u043E\u0432\u0438\u044F"
        $num = 1
        foreach ($pc in $Preconds) { $parts += "$num. $(Escape-Unicode $pc)"; $num++ }
        $parts += ""
    }
    
    # Шаги и ОР
    if ($Steps -and $Steps.Count -gt 0) {
        $parts += "## \u0428\u0430\u0433\u0438"
        $stepDescs = @()
        $stepResults = @()
        $stepNum = 1
        foreach ($s in $Steps) {
            $split = $s -split "\|\|"
            $action = if ($split.Length -ge 1) { $split[0].Trim() } else { "" }
            $expected = if ($split.Length -ge 2) { $split[1].Trim() } else { "" }
            $parts += "$stepNum. $(Escape-Unicode $action)"
            $stepResults += "- $(Escape-Unicode $expected)"
            $stepNum++
        }
        $parts += ""
        
        $parts += "## \u041E\u0436\u0438\u0434\u0430\u0435\u043C\u044B\u0439 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442"
        foreach ($r in $stepResults) { $parts += $r }
        $parts += ""
        
        $parts += "## \u0422\u0435\u0441\u0442\u043E\u0432\u044B\u0435 \u0434\u0430\u043D\u043D\u044B\u0435"
        $parts += "- \u042D\u043D\u0434\u043F\u043E\u0438\u043D\u0442: $(Escape-Unicode $Title)"
    }
    
    return ($parts -join "\n")
}

# === Формирование MCP-запроса ===
$rpcId = Get-Random -Minimum 1000 -Maximum 99999

switch ($Action) {
    "create" {
        if (-not $SuiteId -or -not $Title) {
            Write-Output '{"status":"error","message":"create requires SuiteId and Title"}'; exit 1
        }
        
        $escapedTitle = Escape-Unicode $Title
        $description = ""
        
        if ($Desc) {
            # Используем готовое описание как есть
            $description = Escape-Unicode $Desc
        } elseif ($Steps -and $Steps.Count -gt 0) {
            # Генерируем описание из Steps в формате "действие||ОР"
            $description = Build-Description
        }
        
        $descJson = if ($description) { ",`"description`":`"$description`"" } else { "" }
        $mcpBody = "{`"jsonrpc`":`"2.0`",`"id`":$rpcId,`"method`":`"tools/call`",`"params`":{`"name`":`"tests`",`"arguments`":{`"command`":`"create`",`"suite_id`":`"$SuiteId`",`"title`":`"$escapedTitle`"$descJson}}}"
    }
    "list_suites" {
        $mcpBody = "{`"jsonrpc`":`"2.0`",`"id`":$rpcId,`"method`":`"tools/call`",`"params`":{`"name`":`"suites`",`"arguments`":{`"command`":`"list`",`"per_page`":50}}}"
    }
    "list_tests" {
        if (-not $SuiteId) { Write-Output '{"status":"error","message":"list_tests requires SuiteId"}'; exit 1 }
        $mcpBody = "{`"jsonrpc`":`"2.0`",`"id`":$rpcId,`"method`":`"tools/call`",`"params`":{`"name`":`"tests`",`"arguments`":{`"command`":`"list`",`"suite_id`":`"$SuiteId`",`"per_page`":50}}}"
    }
    "get" {
        if (-not $TestId) { Write-Output '{"status":"error","message":"get requires TestId"}'; exit 1 }
        $mcpBody = "{`"jsonrpc`":`"2.0`",`"id`":$rpcId,`"method`":`"tools/call`",`"params`":{`"name`":`"tests`",`"arguments`":{`"command`":`"get`",`"test_id`":`"$TestId`"}}}"
    }
    "delete" {
        if (-not $TestId) { Write-Output '{"status":"error","message":"delete requires TestId"}'; exit 1 }
        $mcpBody = "{`"jsonrpc`":`"2.0`",`"id`":$rpcId,`"method`":`"tools/call`",`"params`":{`"name`":`"tests`",`"arguments`":{`"command`":`"delete`",`"test_id`":`"$TestId`"}}}"
    }
}

# === Отправка ===
try {
    $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $mcpBody -TimeoutSec 30
    if ($response.error) { Write-Output "{`"status`":`"error`",`"message`":`"$($response.error.message)`"}"; exit 1 }
    
    $rawResult = $response.result.content[0].text
    $parsedResult = $rawResult | ConvertFrom-Json
    
    switch ($Action) {
        "create" {
            $output = @{status="success"; action="create"; test_id=$parsedResult.data.id; url="https://app.testomat.io/projects/$projectId/test/$($parsedResult.data.id)"; suite_id=$SuiteId}
            Write-Output ($output | ConvertTo-Json -Depth 3)
        }
        "list_suites" {
            $suites = @(); foreach ($s in $parsedResult.data) { $suites += @{id=$s.id; test_count=$s.test_count} }
            Write-Output (@{status="success"; action="list_suites"; total=$parsedResult.meta.total; suites=$suites} | ConvertTo-Json -Depth 5)
        }
        "list_tests" {
            $tests = @(); foreach ($t in $parsedResult.data) { $tests += @{id=$t.id; priority=$t.priority; state=$t.state} }
            Write-Output (@{status="success"; action="list_tests"; suite_id=$SuiteId; total=$parsedResult.meta.total; tests=$tests} | ConvertTo-Json -Depth 5)
        }
        "get" {
            Write-Output (@{status="success"; action="get"; test_id=$parsedResult.data.id; priority=$parsedResult.data.priority; state=$parsedResult.data.state; url="https://app.testomat.io/projects/$projectId/test/$($parsedResult.data.id)"} | ConvertTo-Json -Depth 3)
        }
        "delete" {
            Write-Output (@{status="success"; action="delete"; test_id=$TestId} | ConvertTo-Json -Depth 2)
        }
    }
} catch {
    $errorMsg = $_.Exception.Message -replace '"', '\"' -replace "`r", "" -replace "`n", " "
    Write-Output "{`"status`":`"error`",`"message`":`"$errorMsg`"}"
    exit 1
}
