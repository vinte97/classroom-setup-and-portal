"""Решения установщика, которые проверяют тесты. Скрипты повторяют те же правила."""


def plan_action(current_hash, expected_hash, previous_hash):
    if not current_hash:
        return "COPY"
    if current_hash == expected_hash:
        return "UNCHANGED"
    if previous_hash and current_hash == previous_hash:
        return "UPDATE"
    return "KEEP"


def decide_status(os_ok, space_ok, pack_ok, writable, materials_ok, workai, mode, git_ok, python_ok):
    if not all((os_ok, space_ok, pack_ok, writable, materials_ok)):
        return "ТРЕБУЕТСЯ ПОМОЩЬ"
    advanced_ok = mode != "ADVANCED" or (git_ok and python_ok)
    if workai and advanced_ok:
        return "ГОТОВО"
    return "ЧАСТИЧНО"
