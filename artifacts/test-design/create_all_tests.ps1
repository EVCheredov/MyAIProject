# PowerShell-скрипт массового создания тест-кейсов в Testomat.io
# Запуск: .\create_all_tests.ps1
# Требует: PowerShell 5.1+, доступ к testomat_helper.ps1

$ErrorActionPreference = "Stop"
$scriptPath = "C:\Users\ECheredov\IdeaProjects\MyAIProject\.opencode\scripts\testomat_helper.ps1"
$env:TESTOMAT_TOKEN = "tstmt_H3q69ALUXcpMdXH7rTUQoM6jBatN2_bXAQ1794148439"
$apiSuiteId = "f74c58a3"
$uiSuiteId = "57320f45"
$results = @()

function Create-TestCase {
    param($SuiteId, $Title, $Steps)
    
    Write-Host "`n>>> СОЗДАНИЕ: $Title" -ForegroundColor Cyan
    
    $stepsArg = @()
    foreach ($step in $Steps) {
        $stepsArg += @{action = $step.action; expected = $step.expected}
    }
    
    $jsonResult = powershell -NoProfile -File $scriptPath `
        -Action create `
        -SuiteId $SuiteId `
        -Title $Title `
        -Steps $stepsArg
    
    $result = $jsonResult | ConvertFrom-Json
    
    if ($result.status -eq "success") {
        Write-Host "  [OK] ID: $($result.test_id)" -ForegroundColor Green
        Write-Host "  URL: $($result.url)" -ForegroundColor Green
        return @{
            id = $result.test_id
            url = $result.url
            title = $Title
            suite = $SuiteId
            status = "success"
        }
    } else {
        Write-Host "  [FAIL] $($result.message)" -ForegroundColor Red
        return @{
            title = $Title
            suite = $SuiteId
            status = "error"
            message = $result.message
        }
    }
}

Write-Host "╔══════════════════════════════════════════╗" -ForegroundColor Magenta
Write-Host "║  МАССОВОЕ СОЗДАНИЕ ТЕСТ-КЕЙСОВ v3.0    ║" -ForegroundColor Magenta
Write-Host "║  Testomat.io | Super GSM                ║" -ForegroundColor Magenta
Write-Host "╚══════════════════════════════════════════╝" -ForegroundColor Magenta

# ============ СЬЮТ A: Авторизация по КЭП (SCN-001) ============
Write-Host "`n═══════════ СЬЮТ A: Авторизация по КЭП (SCN-001) ═══════════" -ForegroundColor Yellow

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Авторизация с валидным КЭП (Happy Path)" -Steps @(
    @{action="Отправить POST-запрос на /api/v1/auth/kep с валидным PKCS#7/CMS сертификатом (ИНН/ОГРН в базе)"; expected="Запрос отправлен"}
    @{action="Проверить HTTP-статус код ответа"; expected="Код 200 OK"}
    @{action="Проверить наличие поля access_token (JWT) в теле ответа"; expected="access_token присутствует, expires_in=900"}
    @{action="Декодировать JWT, проверить exp - iat"; expected="exp - iat = 900 секунд (15 минут)"}
    @{action="Использовать JWT для запроса к защищённому ресурсу"; expected="Код 200 OK, данные профиля получены"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Неверный формат PKCS#7/CMS (400)" -Steps @(
    @{action="Сформировать запрос с повреждённым base64 PKCS#7/CMS"; expected="Payload сформирован"}
    @{action="Отправить POST-запрос на /api/v1/auth/kep"; expected="Код 400 Bad Request"}
    @{action="Проверить тело ошибки"; expected="Сообщение о неверном формате сертификата, JWT отсутствует"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Отозванный сертификат (401)" -Steps @(
    @{action="Отправить POST-запрос на /api/v1/auth/kep с отозванным сертификатом"; expected="Код 401 Unauthorized"}
    @{action="Проверить тело ответа"; expected="Ошибка certificate_revoked"}
    @{action="Проверить отсутствие JWT-токена"; expected="JWT-токен отсутствует"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "ИНН/ОГРН не найден в базе (403)" -Steps @(
    @{action="Отправить POST-запрос на /api/v1/auth/kep с сертификатом, чей ИНН/ОГРН отсутствует в БД"; expected="Код 403 Forbidden"}
    @{action="Проверить тело ошибки"; expected="Ошибка inn_not_found, JWT отсутствует"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Таймаут CRL-проверки >3000ms (504)" -Steps @(
    @{action="Эмулировать недоступность CRL-сервера (блокировка порта)"; expected="CRL-сервер не отвечает"}
    @{action="Отправить POST-запрос на /api/v1/auth/kep с валидным сертификатом"; expected="Код 504 Gateway Timeout"}
    @{action="Проверить время выполнения запроса"; expected="Время >3000ms и <=5000ms"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Размер ключа превышает 10MB (граничное значение)" -Steps @(
    @{action="Сформировать PKCS#7/CMS-сообщение размером 10.5MB"; expected="Payload сформирован"}
    @{action="Отправить POST-запрос на /api/v1/auth/kep"; expected="Код 400 Bad Request или 413 Payload Too Large"}
)

# ============ СЬЮТ B: Пакетная загрузка (SCN-002) ============
Write-Host "`n═══════════ СЬЮТ B: Пакетная загрузка (SCN-002) ═══════════" -ForegroundColor Yellow

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Успешная загрузка CSV (202 Accepted)" -Steps @(
    @{action="Подготовить CSV-файл со 100 валидными строками (MSISDN,ФИО,Баланс)"; expected="CSV сформирован"}
    @{action="Отправить POST-запрос на /api/v1/billing/import (multipart/form-data)"; expected="Код 202 Accepted"}
    @{action="Проверить тело ответа"; expected="import_id присутствует, status=processing"}
    @{action="Опрашивать статус импорта каждые 30 сек до 5 мин"; expected="Статус completed в течение 5 минут"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Превышение лимита файла >50МБ (413)" -Steps @(
    @{action="Подготовить CSV-файл размером 51MB"; expected="Файл сформирован"}
    @{action="Отправить POST-запрос на /api/v1/billing/import"; expected="Код 413 Payload Too Large"}
    @{action="Проверить тело ошибки"; expected="error: file_too_large, max_size_mb: 50"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Превышение лимита строк >100000 (413)" -Steps @(
    @{action="Подготовить CSV-файл со 100001 строкой (размер <50MB)"; expected="Файл сформирован"}
    @{action="Отправить POST-запрос на /api/v1/billing/import"; expected="Код 413 Payload Too Large"}
    @{action="Проверить тело ошибки"; expected="error: too_many_rows, max_rows: 100000"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Дубликаты записей в CSV (422)" -Steps @(
    @{action="Подготовить CSV-файл с 10 строками, где 3 дубликата по MSISDN"; expected="CSV сформирован"}
    @{action="Отправить POST-запрос на /api/v1/billing/import"; expected="Код 422 Unprocessable Entity"}
    @{action="Проверить тело ответа на наличие списка дубликатов"; expected="error: duplicate_records, список MSISDN-дубликатов"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Более 30% записей с ошибками (422)" -Steps @(
    @{action="Подготовить CSV-файл со 100 строками, 40 строк с нечисловым балансом"; expected="CSV сформирован"}
    @{action="Отправить POST-запрос на /api/v1/billing/import"; expected="Код 422 Unprocessable Entity"}
    @{action="Проверить тело ошибки"; expected="error: too_many_errors, error_rate: 0.4, max_error_rate: 0.3"}
)

# ============ СЬЮТ C: Безопасность (S3) ============
Write-Host "`n═══════════ СЬЮТ C: Безопасность (S3) ═══════════" -ForegroundColor Yellow

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Блокировка УЗ после 5 неудачных попыток авторизации" -Steps @(
    @{action="Выполнить 5 попыток авторизации с неверным КЭП"; expected="Попытки 1-5: 401 Unauthorized"}
    @{action="Выполнить 6-ю попытку с валидным КЭП"; expected="Код 423 Locked, account_locked, lock_duration_min=30"}
    @{action="Подождать 30 минут и повторить с валидным КЭП"; expected="Код 200 OK, JWT-токен выдаётся"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Отозванный сертификат - бессрочная блокировка УЗ" -Steps @(
    @{action="Отправить запрос с отозванным сертификатом"; expected="Код 401, certificate_revoked"}
    @{action="Через 31 минуту отправить запрос с новым валидным сертификатом"; expected="Код 401/403, бессрочная блокировка не снимается"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Inactivity 15 минут - уничтожение JWT-токена" -Steps @(
    @{action="Авторизоваться и получить JWT-токен"; expected="200 OK, токен получен"}
    @{action="Не выполнять запросов в течение 15 минут"; expected="Ожидание 15 мин"}
    @{action="Отправить запрос к защищённому ресурсу с имеющимся JWT"; expected="Код 401, token_expired"}
)

$results += Create-TestCase -SuiteId $apiSuiteId -Title "Более 3 Action Forbidden - блокировка до конца дня" -Steps @(
    @{action="Выполнить 3 запрещённых действия для роли SupportOps"; expected="Код 403 Forbidden на каждом"}
    @{action="Выполнить 4-е запрещённое действие"; expected="Код 423 Locked, daily_limit_exceeded"}
    @{action="Попытаться выполнить разрешённое действие"; expected="Код 423 Locked, УЗ заблокирована до конца дня"}
)

# ============ СЬЮТ D: UI-компоненты (S4) ============
Write-Host "`n═══════════ СЬЮТ D: UI-компоненты (S4) ═══════════" -ForegroundColor Yellow

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Поиск в таблице реестра с дебаунсом 300мс" -Steps @(
    @{action="Ввести текст +7999111 в строку поиска"; expected="Текст введён"}
    @{action="Замерить время до отправки запроса поиска"; expected="Запрос отправлен через ~300мс после последнего ввода"}
    @{action="Проверить отображение отфильтрованных результатов"; expected="Отображаются строки, содержащие +7999111"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Пагинация таблицы (20/50/100 записей)" -Steps @(
    @{action="Установить количество записей на странице = 20"; expected="Отображается ровно 20 строк"}
    @{action="Переключить на 50 записей"; expected="Отображается 50 строк"}
    @{action="Переключить на 100 записей"; expected="Отображается 100 строк"}
    @{action="Нажать кнопку Следующая страница"; expected="Отображается следующая страница с указанным количеством строк"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Форма баланса: только цифры, переключатель +/-, лимит 5000" -Steps @(
    @{action="Ввести текст abc в поле суммы"; expected="Ввод букв заблокирован, поле остаётся пустым"}
    @{action="Ввести 12345 (превышает лимит 5000 для SupportOps)"; expected="Ошибка валидации: превышение лимита"}
    @{action="Ввести 5000, выбрать тип +, нажать Сохранить"; expected="Операция успешна, баланс увеличен на 5000"}
    @{action="Выбрать тип -, ввести 5000, сохранить"; expected="Баланс уменьшен на 5000"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "DragDrop CSV-файла (успешная загрузка)" -Steps @(
    @{action="Перетащить валидный CSV-файл (2MB, 50 строк) в зону DragDrop"; expected="Файл принят, отображается имя и прогресс"}
    @{action="Дождаться завершения загрузки"; expected="Код 202 Accepted от API"}
    @{action="Проверить статус импорта"; expected="Импорт завершён успешно"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "DragDrop неподдерживаемого формата .exe.pdf (ошибка)" -Steps @(
    @{action="Перетащить .exe-файл в зону DragDrop"; expected="Сообщение: Неподдерживаемый формат. Допустимы только .csv и .xlsx"}
    @{action="Перетащить .pdf-файл в зону DragDrop"; expected="То же сообщение об ошибке"}
    @{action="Проверить, что файлы не отправлены на сервер"; expected="Запросов к API не было"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Toast-уведомление при ошибке 504" -Steps @(
    @{action="Отправить запрос на авторизацию при недоступном CRL-сервере"; expected="Ошибка 504 Gateway Timeout"}
    @{action="Проверить отображение Toast-уведомления"; expected="Красный Toast: Сервис временно недоступен. Повторите попытку позже."}
    @{action="Дождаться автоматического закрытия Toast"; expected="Toast скрыт через заданный таймаут"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Badge-индикаторы статуса (цвета #10B981 #EF4444 #6B7280)" -Steps @(
    @{action="Найти запись со статусом Активен, проверить цвет badge"; expected="Badge зелёный (#10B981)"}
    @{action="Найти запись со статусом Ошибка, проверить цвет badge"; expected="Badge красный (#EF4444)"}
    @{action="Найти запись со статусом Неактивен, проверить цвет badge"; expected="Badge серый (#6B7280)"}
)

$results += Create-TestCase -SuiteId $uiSuiteId -Title "Модальное окно при потере сетевого соединения" -Steps @(
    @{action="Отключить сетевое соединение"; expected="Сеть отключена"}
    @{action="Выполнить любое действие (нажать кнопку)"; expected="Отображается модальное окно: Потеря сетевого соединения"}
    @{action="Восстановить сеть и нажать Повторить"; expected="Запрос выполнен успешно"}
)

# ============ ИТОГОВАЯ СВОДКА ============
Write-Host "`n`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    ИТОГОВАЯ СВОДКА                          ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green

$successCount = ($results | Where-Object { $_.status -eq "success" }).Count
$errorCount = ($results | Where-Object { $_.status -eq "error" }).Count

Write-Host "`n✅ Успешно создано: $successCount" -ForegroundColor Green
if ($errorCount -gt 0) { Write-Host "❌ Ошибок: $errorCount" -ForegroundColor Red }
Write-Host "Всего тест-кейсов: $($results.Count)" -ForegroundColor Cyan

Write-Host "`n┌─────────────────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│                        РЕЗУЛЬТАТЫ                                │" -ForegroundColor Cyan
Write-Host "├─────────────────────────────────────────────────────────────────┤" -ForegroundColor Cyan

foreach ($r in $results) {
    if ($r.status -eq "success") {
        Write-Host "│ [OK] $($r.id) | $($r.title)" -ForegroundColor Green
        Write-Host "│      URL: $($r.url)" -ForegroundColor DarkGray
    } else {
        Write-Host "│ [FAIL] $($r.title) — $($r.message)" -ForegroundColor Red
    }
}
Write-Host "└─────────────────────────────────────────────────────────────────┘" -ForegroundColor Cyan

Write-Host "`nСводка ID тест-кейсов для отчёта:" -ForegroundColor Yellow
foreach ($r in $results) {
    if ($r.status -eq "success") {
        Write-Host "  $($r.id) — $($r.title)" -ForegroundColor White
    }
}

Write-Host "`nСкрипт завершён. Всего создано: $successCount / $($results.Count)" -ForegroundColor Magenta
