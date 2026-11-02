#!/usr/bin/env python3
"""Проверяет реестр и ответы учебного MCP без поднятого чата."""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import server  # noqa: E402


def assert_true(flag, message):
    if not flag:
        raise SystemExit(message)


def check_registry():
    docs = server.load("documents.csv")
    tasks = server.load("tasks.csv")
    projects = {row["project_id"] for row in server.load("projects.csv")}
    assert_true(len(docs) >= 40, "мало документов в реестре")
    for row in docs:
        assert_true((ROOT / row["path"]).is_file(), f"нет файла {row['path']}")
    for row in tasks:
        if row["project_id"]:
            assert_true(row["project_id"] in projects, row["task_id"])
    ids = [row["document_id"] for row in docs]
    assert_true(len(ids) == len(set(ids)), "повтор document_id")


def check_tools():
    status = server.get_project_status("PRJ-ERP")
    assert_true(status["as_of"] == "2026-06-20", "кэш должен остаться срезом 20.06")
    assert_true(status["complaints"] == "нет", "кэш не должен знать о жалобе")
    live = server.list_tasks("CASE-ERP-001")["tasks"]
    closed = next(row for row in live if row["task_id"] == "T-ERP-01")
    assert_true(closed["sed_status"] == "исполнено" and closed["actual_status"] == "жалобы_открыты", "T-ERP-01")
    missing = server.get_project_status("PRJ-SUP2")
    assert_true(missing["error"] == "not_found", "PRJ-SUP2 нет в кэше")
    denied = server.get_task("T-HR-PAY")
    assert_true(denied["error"] == "access_denied" and "оклад" not in json.dumps(denied, ensure_ascii=False), "отказ без содержимого")
    unknown = server.get_task("T-ERP-99")
    assert_true(unknown["error"] == "not_found", "пустая карточка")
    stock = server.get_warehouse_balance("K12")
    assert_true(stock["error"] == "unavailable" and "420" not in json.dumps(stock), "WMS молчит")
    june = server.list_kpi("2026-06")["kpi"]
    revenue = next(row for row in june if row["kpi_id"] == "REV-2026-06")
    assert_true(revenue["value_sales"] == "40.5" and revenue["value_finance"] == "39.8", "выручка")


def frame(payload):
    body = json.dumps(payload).encode()
    return f"Content-Length: {len(body)}\r\n\r\n".encode() + body


def check_stdio():
    proc = subprocess.run(
        [sys.executable, str(Path(__file__).with_name("server.py"))],
        input=frame({
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": "2024-11-05", "capabilities": {}},
        }) + frame({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        capture_output=True,
        check=True,
    )
    text = proc.stdout.decode()
    assert_true("severprom-training" in text and "get_project_status" in text, "stdio")


if __name__ == "__main__":
    check_registry()
    check_tools()
    check_stdio()
    print("ok")
