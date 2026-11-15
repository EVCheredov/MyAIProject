# PowerShell-скрипт создания тест-кейсов EVC-001 в Testomat.io
# Сьют: f74c58a3 (API/Security, проект mytests-ed9d5)
# Запуск: powershell -NoProfile -ExecutionPolicy Bypass -File .\create_evc001_v4.ps1
# Требует: TESTOMAT_TOKEN (из .env или окружения); доступ к .opencode/scripts/testomat_helper.ps1

$ErrorActionPreference = "Stop"

$helper   = "C:\Users\ECheredov\IdeaProjects\MyAIProject\.opencode\scripts\testomat_helper.ps1"
$project  = "C:\Users\ECheredov\IdeaProjects\MyAIProject"
$suiteId  = "f74c58a3"

# Токен из корневого .env (если не задан в окружении)
if (-not $env:TESTOMAT_TOKEN) {
    $envFile = Join-Path $project ".env"
    if (Test-Path $envFile) {
        $m = Select-String -Path $envFile -Pattern 'TESTOMAT_TOKEN="([^"]+)"'
        if ($m) { $env:TESTOMAT_TOKEN = $m.Matches[0].Groups[1].Value }
    }
}
if (-not $env:TESTOMAT_TOKEN) { Write-Error "TESTOMAT_TOKEN не найден"; exit 1 }

$results = @()

function Create-TC {
    param([string]$Title, [string[]]$Preconds, [string[]]$Steps)
    Write-Host ">>> $Title" -ForegroundColor Cyan
    $desc = ""
    if ($Preconds) {
        $desc += "## Предусловия`n"
        $i = 1; foreach ($p in $Preconds) { $desc += "$i. $p`n"; $i++ }
        $desc += "`n"
    }
    $desc += "## Шаги`n"
    $j = 1; foreach ($s in $Steps) { $desc += "$j. $s`n"; $j++ }
    $desc += "`n## Ожидаемый результат`n- См. шаги (детализация в артефакте v4.0.md)`n"

    $json = & powershell -NoProfile -ExecutionPolicy Bypass -File $helper -Action create -SuiteId $suiteId -Title $Title -Desc $desc
    $r = $json | ConvertFrom-Json
    if ($r.status -eq "success") {
        Write-Host "  [OK] $($r.test_id) $($r.url)" -ForegroundColor Green
        $script:results += [pscustomobject]@{ title=$Title; id=$r.test_id; url=$r.url; status="success" }
    } else {
        Write-Host "  [FAIL] $($r.message)" -ForegroundColor Red
        $script:results += [pscustomobject]@{ title=$Title; id=$null; url=$null; status="error"; message=$r.message }
    }
}

# ---- FR-01 (KAN-22) ----
Create-TC -Title "TC-EVC-001-01 Успешный вход по MSISDN+пароль (Happy Path)" -Preconds @("УЗ активна","MSISDN +79991112233, пароль SuperGsm2024") -Steps @(
 "Зафиксировать статус и баланс +79991112233",
 "Отправить вход: MSISDN +79991112233 / SuperGsm2024",
 "Проверить HTTP 200 и наличие сессии",
 "Повторно зафиксировать статус и баланс"
)
Create-TC -Title "TC-EVC-001-02 Неверный пароль → 401 AUTH_INVALID_CREDENTIALS" -Steps @(
 "Отправить вход: +79991112233 / WrongPass123",
 "Проверить HTTP 401 и тело {""errorCode"":""AUTH_INVALID_CREDENTIALS""}",
 "Проверить отсутствие сессии"
)
Create-TC -Title "TC-EVC-001-03 Несуществующий логин → 401 идентичное тело" -Steps @(
 "Отправить вход: +79991112299 / SuperGsm2024",
 "Проверить HTTP 401 и тело AUTH_INVALID_CREDENTIALS"
)
Create-TC -Title "TC-EVC-001-04 Неразличимость неверный логин vs неверный пароль" -Steps @(
 "Вход: +79991112233 / WrongPass123",
 "Вход: +79991112299 / SuperGsm2024",
 "Сравнить статус и тело обоих ответов — идентичны"
)

# ---- FR-02 (KAN-23) ----
Create-TC -Title "TC-EVC-001-05 Длина пароля 7 → отказ" -Steps @("Ввести Abc1234 (7)","Проверить отказ валидации")
Create-TC -Title "TC-EVC-001-06 Длина пароля 8 → успех" -Steps @("Ввести Abc12345 (8)","Проверить успех")
Create-TC -Title "TC-EVC-001-07 Длина пароля 64 → успех" -Steps @("Ввести пароль из 64 симв. (Aa1+61)","Проверить успех")
Create-TC -Title "TC-EVC-001-08 Длина пароля 65 → отказ" -Steps @("Ввести пароль из 65 симв.","Проверить отказ")
Create-TC -Title "TC-EVC-001-09 Отсутствие класса символов → отказ" -Steps @("abcd1234 без заглавной → отказ","ABCD1234 без строчной → отказ","Abcdefgh без цифры → отказ")
Create-TC -Title "TC-EVC-001-10 Спецсимволы разрешены, не обязательны" -Steps @("Abc123!@# → принят","Abc12345 → принят")
Create-TC -Title "TC-EVC-001-11 Хранение Argon2id (хеш+соль, необратимо)" -Steps @("Прочитать хеш из БД","Проверить формат $argon2id$ и соль","Одинаковые пароли → разные хеши")
Create-TC -Title "TC-EVC-001-12 Пароль не в логах/трассировках/ответах API" -Steps @("Выполнить вход и смену пароля","Проверить ответы API","Проверить логи и трассировки — пароля/хеша нет")

# ---- FR-03 (KAN-24) ----
Create-TC -Title "TC-EVC-001-13 Блокировка после 3 неудач; SIM/баланс без изменений" -Preconds @("счётчик=0") -Steps @(
 "Зафиксировать статус SIM и баланс",
 "3 входа с WrongPass123",
 "Проверить 401 у 1-2, блокировку после 3",
 "Вход верным SuperGsm2024 → 423 ACCOUNT_BLOCKED retryAfterSeconds<=1800",
 "Повторно зафиксировать статус SIM и баланс — без изменений"
)
Create-TC -Title "TC-EVC-001-14 Блокировка после 3-й, не после 2-й" -Steps @("2 входа WrongPass123 (401)","Вход верным → 200; счётчик сброшен")
Create-TC -Title "TC-EVC-001-15 В блокировке верный пароль → 423 ACCOUNT_BLOCKED" -Steps @("Вход верным SuperGsm2024","Проверить 423 и retryAfterSeconds>0")
Create-TC -Title "TC-EVC-001-16 Авто-разблокировка 30 мин + обнуление счётчика" -Steps @("Заблокировать","Сэмулировать 30 мин","Вход верным → 200","2 неудачи не блокируют")
Create-TC -Title "TC-EVC-001-17 Ручная разблокировка админом + аудит" -Steps @("Зафиксировать статус/баланс","Снять блокировку вручную","Вход верным → 200","Проверить запись в аудите","Повторно статус/баланс")
Create-TC -Title "TC-EVC-001-18 BR-01 сброс счётчика после успешного входа" -Steps @("2 неудачи","Успешный вход","Снова 2 неудачи — без блокировки")

# ---- FR-04 (KAN-25) ----
Create-TC -Title "TC-EVC-001-19 TTL 30 мин с последней активности; продление" -Steps @("Войти","Через 20 мин операция (продление)","Через 25 мин после — сессия активна")
Create-TC -Title "TC-EVC-001-20 Истечение TTL → 401 SESSION_EXPIRED" -Steps @("Войти","Простой 30 мин","Запрос → 401 SESSION_EXPIRED")
Create-TC -Title "TC-EVC-001-21 Смена пароля инвалидирует все сессии + баланс/статус" -Steps @("Зафиксировать статус/баланс","Сменить пароль из сессии A","A и B → 401","Повторный вход новым паролем → 200","Повторно статус/баланс")
Create-TC -Title "TC-EVC-001-22 Logout завершает только текущую сессию" -Steps @("Logout в A → A 401","B остаётся 200")

# ---- FR-05 (KAN-26) ----
Create-TC -Title "TC-EVC-001-23 Успешное восстановление по SMS + баланс/статус" -Steps @("Зафиксировать статус/баланс","Запросить восстановление","Получить код на MSISDN","Ввести верный код","Задать SuperGsm2025","Вход новым паролем → 200","Повторно статус/баланс")
Create-TC -Title "TC-EVC-001-24 Код на привязанный MSISDN; действителен 5 мин" -Steps @("Запросить код","Проверить приход на привязанный MSISDN","Через 5 мин код не принимается")
Create-TC -Title "TC-EVC-001-25 3 попытки кода; затем аннулирование" -Steps @("2 неверных — допускаются","3-й неверный → аннулирование","Верный код не принимается","Повторный запрос нового кода")
Create-TC -Title "TC-EVC-001-26 Новый пароль валидируется по FR-02" -Steps @("abc → отказ","SuperGsm2025 → успех")

# ---- FR-06 (KAN-27) ----
Create-TC -Title "TC-EVC-001-27 Auth Service недоступен → 503 AUTH_SERVICE_UNAVAILABLE" -Steps @("Эмулировать недоступность","Вход → 503 AUTH_SERVICE_UNAVAILABLE")
Create-TC -Title "TC-EVC-001-28 Таймаут Auth Service 5 с" -Steps @("Эмулировать задержку >5с","Замер: прерывание ~5с → 503")
Create-TC -Title "TC-EVC-001-29 Недоставка SMS → 502 SMS_DELIVERY_FAILED" -Steps @("Эмулировать недоставку","Запрос восстановления → 502 SMS_DELIVERY_FAILED")
Create-TC -Title "TC-EVC-001-30 Повторный запрос SMS не ранее 60 с" -Steps @("Запрос кода","Через 30с — отклонено","Через 60с+ — успех")

# ---- BR-03/BR-04 (KAN-28) ----
Create-TC -Title "TC-EVC-001-31 BR-03 успешный вход в аудите" -Steps @("Успешный вход","Найти событие в аудите")
Create-TC -Title "TC-EVC-001-32 BR-03 отказ в аудите" -Steps @("Неверный пароль","Найти событие отказа в аудите")
Create-TC -Title "TC-EVC-001-33 BR-03 блокировка в аудите" -Steps @("3 неудачи","Найти событие блокировки в аудите")
Create-TC -Title "TC-EVC-001-34 BR-03 разблокировка в аудите" -Steps @("Ручная разблокировка","Авто-разблокировка 30 мин","Найти оба события в аудите")
Create-TC -Title "TC-EVC-001-35 BR-04 пароль и SMS-код не в аудите/логах" -Steps @("Вход+смена пароля","Восстановление по SMS","Проверить аудит — нет секретов","Проверить логи — нет секретов")

Write-Host "`n===== ИТОГ =====" -ForegroundColor Yellow
$ok = ($results | Where-Object status -eq "success").Count
Write-Host "Создано: $ok / $($results.Count)"
$results | ForEach-Object { if ($_.status -eq "success") { Write-Host "[$($_.id)] $($_.title) — $($_.url)" } else { Write-Host "[FAIL] $($_.title): $($_.message)" } }
$results | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $project "artifacts\test-design\create_evc001_v4.result.json") -Encoding UTF8
