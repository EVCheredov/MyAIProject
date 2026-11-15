import shutil


def resolve_opencode_command() -> str:
    """Находит исполняемый файл opencode, пригодный для subprocess.Popen.

    На Windows npm-установка кладёт рядом opencode.cmd, opencode.ps1 и
    opencode-launcher. subprocess не может запустить .ps1 напрямую, поэтому
    предпочитаем .cmd / .exe.
    """

    for name in ("opencode.cmd", "opencode.exe", "opencode"):
        path = shutil.which(name)

        if path:
            return path

    raise FileNotFoundError(
        "Не найден исполняемый файл opencode. "
        "Проверьте установку (npm install -g opencode)."
    )
