"""
Testomat.io API Client для eval_runner.py.

Обёртка над PowerShell-скриптом .opencode/scripts/testomat_helper.ps1.

Позволяет создавать тест-кейсы и проверять их статус
непосредственно из Python-пайплайна eval_runner.
"""

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Optional


# =============================================================
# PATHS
# =============================================================

PROJECT_ROOT = Path(__file__).resolve().parent.parent

HELPER_SCRIPT = (
    PROJECT_ROOT
    / ".opencode"
    / "scripts"
    / "testomat_helper.ps1"
)

ENV_FILE = PROJECT_ROOT / ".env"


# =============================================================
# TOKEN LOADER
# =============================================================

def _load_token() -> str:
    """Загружает TESTOMAT_TOKEN из .env файла."""
    token = os.environ.get("TESTOMAT_TOKEN")

    if token:
        return token

    if ENV_FILE.exists():
        content = ENV_FILE.read_text(encoding="utf-8")

        for line in content.splitlines():
            line = line.strip()

            if line.startswith("TESTOMAT_TOKEN="):
                # Формат: TESTOMAT_TOKEN="значение"
                raw = line.split("=", 1)[1].strip()

                if raw.startswith('"') and raw.endswith('"'):
                    raw = raw[1:-1]

                token = raw
                break

    if not token:
        raise RuntimeError(
            "TESTOMAT_TOKEN не найден ни в переменных окружения, "
            f"ни в файле {ENV_FILE}"
        )

    return token


# =============================================================
# POWERSHELL RUNNER
# =============================================================

def _run_helper(action: str, **kwargs: Any) -> dict[str, Any]:
    """
    Вызывает testomat_helper.ps1 с указанным action и аргументами.

    Args:
        action: create / get / list_suites / list_tests / delete
        **kwargs: Дополнительные аргументы для скрипта.

    Returns:
        Распарсенный JSON-ответ от скрипта.
    """
    if not HELPER_SCRIPT.exists():
        raise FileNotFoundError(
            f"Скрипт testomat_helper.ps1 не найден: {HELPER_SCRIPT}"
        )

    # Маппинг kwargs в PowerShell параметры
    param_map: dict[str, str] = {
        "suite_id": "SuiteId",
        "test_id": "TestId",
        "title": "Title",
        "desc": "Desc",
        "steps": "Steps",
        "preconds": "Preconds",
        "priority": "Priority",
    }

    # Формируем PowerShell команду
    # Используем -Command для корректной передачи массивов
    ps_command_parts = [
        f"& '{HELPER_SCRIPT}'",
        f"-Action '{action}'",
    ]

    for key, value in kwargs.items():
        ps_param = param_map.get(key)

        if ps_param is None:
            continue

        if isinstance(value, str):
            # Экранируем одинарные кавычки
            escaped = value.replace("'", "''")
            ps_command_parts.append(f"-{ps_param} '{escaped}'")

        elif isinstance(value, (list, tuple)):
            # Массив в PowerShell: @('item1', 'item2')
            items_joined = ", ".join(
                f"'{str(item).replace(chr(39), chr(39)*2)}'"
                for item in value
            )
            ps_command_parts.append(f"-{ps_param} @({items_joined})")

        elif isinstance(value, bool):
            if value:
                ps_command_parts.append(f"-{ps_param}")

        else:
            ps_command_parts.append(
                f"-{ps_param} '{str(value)}'"
            )

    ps_command = " ".join(ps_command_parts)

    # Устанавливаем токен в окружении для дочернего процесса
    env = os.environ.copy()
    env["TESTOMAT_TOKEN"] = _load_token()

    # Запускаем PowerShell
    result = subprocess.run(
        [
            "powershell",
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-Command",
            ps_command,
        ],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=60,
        env=env,
    )

    # Собираем stdout (скрипт выводит JSON в stdout)
    output = (result.stdout or "").strip()

    # Если stdout пуст — смотрим stderr
    if not output:
        stderr = (result.stderr or "").strip()

        if stderr:
            raise RuntimeError(
                f"PowerShell скрипт вернул ошибку:\n{stderr}"
            )

        raise RuntimeError(
            f"PowerShell скрипт не вернул вывод. "
            f"Return code: {result.returncode}"
        )

    # Парсим JSON
    try:
        data = json.loads(output)
    except json.JSONDecodeError as error:
        raise RuntimeError(
            f"Не удалось разобрать ответ PowerShell скрипта как JSON.\n"
            f"Ответ: {output[:500]}"
        ) from error

    # Проверяем статус
    if data.get("status") == "error":
        raise RuntimeError(
            f"Testomat.io API вернул ошибку: {data.get('message', 'неизвестная ошибка')}"
        )

    return data


# =============================================================
# PUBLIC API
# =============================================================

def create_test(
    suite_id: str,
    title: str,
    steps: Optional[list[str]] = None,
    desc: Optional[str] = None,
    preconds: Optional[list[str]] = None,
    priority: str = "normal",
) -> dict[str, Any]:
    """
    Создаёт тест-кейс в Testomat.io.

    Args:
        suite_id: ID сьюта (папки) в Testomat.io.
        title: Название тест-кейса.
        steps: Список шагов в формате "действие||ожидаемый результат".
        desc: Готовое описание (если есть, steps игнорируются).
        preconds: Список предусловий.
        priority: Приоритет (normal / high / low).

    Returns:
        Словарь с полями: status, action, test_id, url, suite_id
    """
    kwargs: dict[str, Any] = {
        "suite_id": suite_id,
        "title": title,
        "priority": priority,
    }

    if desc:
        kwargs["desc"] = desc
    elif steps:
        kwargs["steps"] = steps

    if preconds:
        kwargs["preconds"] = preconds

    return _run_helper("create", **kwargs)


def get_test(test_id: str) -> dict[str, Any]:
    """
    Получает тест-кейс по ID.

    Args:
        test_id: ID тест-кейса в Testomat.io.

    Returns:
        Словарь с полями: status, action, test_id, priority, state, url
    """
    return _run_helper("get", test_id=test_id)


def list_suites() -> dict[str, Any]:
    """
    Получает список сьютов в Testomat.io.

    Returns:
        Словарь с полями: status, action, total, suites
    """
    return _run_helper("list_suites")


def list_tests(suite_id: str) -> dict[str, Any]:
    """
    Получает список тестов в сьюте.

    Args:
        suite_id: ID сьюта.

    Returns:
        Словарь с полями: status, action, suite_id, total, tests
    """
    return _run_helper("list_tests", suite_id=suite_id)


def delete_test(test_id: str) -> dict[str, Any]:
    """
    Удаляет тест-кейс по ID.

    Args:
        test_id: ID тест-кейса в Testomat.io.

    Returns:
        Словарь с полями: status, action, test_id
    """
    return _run_helper("delete", test_id=test_id)


def verify_test_exists(test_id: str) -> bool:
    """
    Проверяет, существует ли тест-кейс в Testomat.io.

    Args:
        test_id: ID тест-кейса.

    Returns:
        True если тест-кейс существует, иначе False.
    """
    try:
        result = get_test(test_id)
        return result.get("status") == "success"
    except RuntimeError:
        return False


# =============================================================
# BATCH OPERATIONS
# =============================================================

def create_tests_batch(
    suite_id: str,
    test_cases: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """
    Создаёт несколько тест-кейсов пачкой.

    Args:
        suite_id: ID сьюта.
        test_cases: Список словарей с полями:
            - title (str): Название
            - steps (list[str], optional): Шаги
            - desc (str, optional): Описание
            - preconds (list[str], optional): Предусловия
            - priority (str, optional): Приоритет

    Returns:
        Список результатов создания каждого кейса.
    """
    results: list[dict[str, Any]] = []

    for tc in test_cases:
        try:
            result = create_test(
                suite_id=suite_id,
                title=tc["title"],
                steps=tc.get("steps"),
                desc=tc.get("desc"),
                preconds=tc.get("preconds"),
                priority=tc.get("priority", "normal"),
            )
            result["_success"] = True
        except RuntimeError as error:
            result = {
                "status": "error",
                "title": tc["title"],
                "error": str(error),
                "_success": False,
            }

        results.append(result)

    return results


def verify_tests_batch(
    test_ids: list[str],
) -> dict[str, bool]:
    """
    Проверяет существование нескольких тест-кейсов.

    Args:
        test_ids: Список ID тест-кейсов.

    Returns:
        Словарь {test_id: exists_bool}
    """
    results: dict[str, bool] = {}

    for test_id in test_ids:
        results[test_id] = verify_test_exists(test_id)

    return results


# =============================================================
# CLI (для ручного тестирования)
# =============================================================

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Testomat.io Client CLI"
    )

    parser.add_argument(
        "action",
        choices=[
            "create", "get", "delete",
            "list_suites", "list_tests",
            "verify",
        ],
        help="Действие",
    )

    parser.add_argument(
        "--suite-id",
        help="ID сьюта",
    )

    parser.add_argument(
        "--test-id",
        help="ID тест-кейса",
    )

    parser.add_argument(
        "--title",
        help="Название тест-кейса",
    )

    parser.add_argument(
        "--desc",
        help="Описание тест-кейса",
    )

    parser.add_argument(
        "--step",
        action="append",
        dest="steps",
        help="Шаг в формате 'действие||ожидаемый результат'",
    )

    parser.add_argument(
        "--precond",
        action="append",
        dest="preconds",
        help="Предусловие",
    )

    parser.add_argument(
        "--priority",
        default="normal",
        choices=["normal", "high", "low"],
        help="Приоритет",
    )

    args = parser.parse_args()

    try:
        if args.action == "create":
            result = create_test(
                suite_id=args.suite_id,
                title=args.title,
                steps=args.steps,
                desc=args.desc,
                preconds=args.preconds,
                priority=args.priority,
            )

        elif args.action == "get":
            result = get_test(test_id=args.test_id)

        elif args.action == "delete":
            result = delete_test(test_id=args.test_id)

        elif args.action == "list_suites":
            result = list_suites()

        elif args.action == "list_tests":
            result = list_tests(suite_id=args.suite_id)

        elif args.action == "verify":
            exists = verify_test_exists(test_id=args.test_id)
            result = {
                "status": "success" if exists else "not_found",
                "test_id": args.test_id,
                "exists": exists,
            }

        else:
            result = {"status": "error", "message": f"Неизвестное действие: {args.action}"}

    except (RuntimeError, FileNotFoundError) as error:
        result = {"status": "error", "message": str(error)}

    print(json.dumps(result, ensure_ascii=False, indent=2))
