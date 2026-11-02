#!/usr/bin/env python3
"""Учебный MCP СеверПром. Только чтение. Сеть не используется.

get_project_status отдаёт файл кэша как есть.
get_warehouse_balance всегда отвечает, что данных нет.
get_task по T-HR-PAY отказывает без содержимого.
"""
import csv
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "09_Учебная_система"
DENIED = {"T-HR-PAY"}


def load(name):
    with (ROOT / name).open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def list_tasks(case_id=None):
    rows = load("tasks.csv")
    if case_id:
        rows = [row for row in rows if row["case_id"] == case_id]
    return {"tasks": rows, "source": "tasks.csv"}


def get_task(task_id):
    if task_id in DENIED:
        return {
            "error": "access_denied",
            "task_id": task_id,
            "message": "Недостаточно полномочий. Содержимое не передано.",
        }
    for row in load("tasks.csv"):
        if row["task_id"] == task_id:
            return row
    return {"error": "not_found", "task_id": task_id, "message": "Сведений нет."}


def get_project_status(project_id):
    cache = json.loads((ROOT / "кэш" / "pmo_cache.json").read_text(encoding="utf-8"))
    if project_id == cache["project_id"]:
        return cache
    return {
        "error": "not_found",
        "project_id": project_id,
        "message": "В кэше PMO сведений нет.",
    }


def get_warehouse_balance(sku):
    return {
        "error": "unavailable",
        "sku": sku,
        "message": "WMS не ответила: таймаут. Данные не получены.",
    }


def list_kpi(period=None):
    rows = load("kpi.csv")
    if period:
        rows = [row for row in rows if row["period"] == period]
    return {"kpi": rows, "source": "kpi.csv"}


TOOLS = {
    "list_tasks": {
        "description": "Список поручений из реестра. Статус СЭД и фактический статус могут различаться.",
        "schema": {
            "type": "object",
            "properties": {"case_id": {"type": "string"}},
        },
        "fn": lambda a: list_tasks(a.get("case_id") or None),
    },
    "get_task": {
        "description": "Одна карточка поручения по task_id.",
        "schema": {
            "type": "object",
            "properties": {"task_id": {"type": "string"}},
            "required": ["task_id"],
        },
        "fn": lambda a: get_task(a["task_id"]),
    },
    "get_project_status": {
        "description": "Статус проекта из кэша PMO.",
        "schema": {
            "type": "object",
            "properties": {"project_id": {"type": "string"}},
            "required": ["project_id"],
        },
        "fn": lambda a: get_project_status(a["project_id"]),
    },
    "get_warehouse_balance": {
        "description": "Остаток SKU по данным WMS.",
        "schema": {
            "type": "object",
            "properties": {"sku": {"type": "string"}},
            "required": ["sku"],
        },
        "fn": lambda a: get_warehouse_balance(a["sku"]),
    },
    "list_kpi": {
        "description": "Показатели из реестра. Пустой period возвращает все строки.",
        "schema": {
            "type": "object",
            "properties": {"period": {"type": "string"}},
        },
        "fn": lambda a: list_kpi(a.get("period") or None),
    },
}


def tool_result(payload):
    return {"content": [{"type": "text", "text": json.dumps(payload, ensure_ascii=False)}]}


def handle(message):
    method = message.get("method")
    if method == "initialize":
        return {
            "protocolVersion": "2024-11-05",
            "capabilities": {"tools": {}},
            "serverInfo": {"name": "severprom-training", "version": "2"},
        }
    if method == "tools/list":
        return {
            "tools": [
                {
                    "name": name,
                    "description": spec["description"],
                    "inputSchema": spec["schema"],
                }
                for name, spec in TOOLS.items()
            ]
        }
    if method == "tools/call":
        params = message.get("params") or {}
        name = params.get("name")
        if name not in TOOLS:
            return tool_result({"error": "not_found", "message": "Инструмента нет."})
        try:
            payload = TOOLS[name]["fn"](params.get("arguments") or {})
        except KeyError as exc:
            return tool_result({"error": "bad_request", "message": f"Нет поля {exc.args[0]}."})
        return tool_result(payload)
    if method == "ping":
        return {}
    if method and method.startswith("notifications/"):
        return None
    return {"error": "method_not_found"}


def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("ascii").split(":", 1)
        headers[key.strip().lower()] = value.strip()
    length = int(headers["content-length"])
    body = sys.stdin.buffer.read(length)
    return json.loads(body.decode("utf-8"))


def write_message(payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(f"Content-Length: {len(body)}\r\n\r\n".encode("ascii"))
    sys.stdout.buffer.write(body)
    sys.stdout.buffer.flush()


def main():
    while True:
        message = read_message()
        if message is None:
            return
        result = handle(message)
        if result is None or "id" not in message:
            continue
        if isinstance(result, dict) and result.get("error") == "method_not_found":
            write_message({
                "jsonrpc": "2.0",
                "id": message["id"],
                "error": {"code": -32601, "message": "Method not found"},
            })
            continue
        write_message({"jsonrpc": "2.0", "id": message["id"], "result": result})


if __name__ == "__main__":
    main()
