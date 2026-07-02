from __future__ import annotations

import os
import time
from collections.abc import Iterator

import httpx
import pytest


API_BASE_URL = os.getenv("LIFLY_API_BASE_URL", "http://localhost:8310")


class LiflyApiClient:
    def __init__(self, base_url: str) -> None:
        self.base_url = base_url.rstrip("/")
        self._client = httpx.Client(base_url=self.base_url, timeout=10.0)

    def close(self) -> None:
        self._client.close()

    def request_json(
        self,
        method: str,
        path: str,
        *,
        expected_status: int = 200,
        json: dict | None = None,
    ) -> dict:
        try:
            response = self._client.request(method, path, json=json)
        except httpx.HTTPError as exc:
            pytest.fail(
                f"Could not reach Lifly API at {self.base_url}. "
                "Start services/api first, then rerun the integration tests. "
                f"Original error: {exc}"
            )

        assert response.status_code == expected_status, response.text
        if response.content:
            return response.json()
        return {}


@pytest.fixture(scope="session")
def api() -> Iterator[LiflyApiClient]:
    client = LiflyApiClient(API_BASE_URL)
    yield client
    client.close()


@pytest.fixture(scope="session")
def run_id() -> str:
    return str(int(time.time() * 1000))


def test_health_reports_patch_version(api: LiflyApiClient) -> None:
    body = api.request_json("GET", "/api/v1/health")

    assert body["status"] == "ok"
    assert body["version"] == "0.1.0"
    assert body["port"] == 8310


def test_mcp_memo_create_and_search_contract(
    api: LiflyApiClient,
    run_id: str,
) -> None:
    created = api.request_json(
        "POST",
        "/api/v1/mcp/memo/create",
        json={
            "type": "memo",
            "title": f"MCP pytest memo {run_id}",
            "content_markdown": "created by pytest integration test",
            "tags": ["mcp", "pytest"],
        },
    )

    memo_id = created["memo_id"]
    assert memo_id
    assert created["undo_token"]
    assert created["memo"]["status"] == "active"

    search = api.request_json(
        "POST",
        "/api/v1/mcp/memo/search",
        json={"q": f"MCP pytest memo {run_id}", "limit": 5},
    )

    assert any(memo["id"] == memo_id for memo in search["memos"])

    api.request_json(
        "POST",
        "/api/v1/mcp/memo/create",
        expected_status=422,
        json={"type": "invalid", "content_markdown": "bad"},
    )


def test_mcp_expense_create_search_and_summary_contract(
    api: LiflyApiClient,
    run_id: str,
) -> None:
    created = api.request_json(
        "POST",
        "/api/v1/mcp/expense/create",
        json={
            "amount": 12.34,
            "currency": "CNY",
            "direction": "expense",
            "merchant": f"MCP Pytest Merchant {run_id}",
            "note": "created by pytest integration test",
        },
    )

    transaction_id = created["transaction"]["id"]
    assert transaction_id
    assert created["transaction"]["status"] == "active"

    api.request_json(
        "POST",
        "/api/v1/mcp/expense/create",
        expected_status=422,
        json={"amount": 0, "currency": "CNY", "direction": "expense"},
    )

    search = api.request_json(
        "POST",
        "/api/v1/mcp/expense/search",
        json={"q": f"MCP Pytest Merchant {run_id}", "limit": 5},
    )

    assert any(tx["id"] == transaction_id for tx in search["transactions"])

    summary = api.request_json(
        "POST",
        "/api/v1/mcp/expense/summary",
        json={"period": "current_month"},
    )

    assert summary["period"] == "current_month"
    assert isinstance(summary["total_expense"], int | float)
    assert isinstance(summary["count"], int)


def test_mcp_task_create_list_and_complete_contract(
    api: LiflyApiClient,
    run_id: str,
) -> None:
    created = api.request_json(
        "POST",
        "/api/v1/mcp/task/create",
        json={
            "title": f"MCP pytest task {run_id}",
            "description": "created by pytest integration test",
            "priority": "normal",
        },
    )

    task_id = created["task"]["id"]
    assert task_id
    assert created["task"]["task_status"] == "todo"

    task_list = api.request_json(
        "POST",
        "/api/v1/mcp/task/list",
        json={"task_status": "todo", "limit": 20},
    )

    assert any(task["id"] == task_id for task in task_list["tasks"])

    completed = api.request_json(
        "POST",
        "/api/v1/mcp/task/complete",
        json={"task_id": task_id},
    )

    assert completed["task"]["task_status"] == "done"
    assert completed["task"]["completed_at"] is not None

    api.request_json(
        "POST",
        "/api/v1/mcp/task/complete",
        expected_status=422,
        json={},
    )


def test_mcp_asset_create_upload_url_and_external_url_contract(
    api: LiflyApiClient,
    run_id: str,
) -> None:
    upload = api.request_json(
        "POST",
        "/api/v1/mcp/asset/create-upload-url",
        json={
            "filename": f"mcp-pytest-{run_id}.txt",
            "mime_type": "text/plain",
            "size_bytes": 12,
            "asset_type": "file",
        },
    )

    assert upload["asset_id"]
    assert upload["storage_key"].startswith("attachments/local-dev/")
    assert upload["upload_url"]
    assert upload["asset"]["kind"] == "internal"
    assert upload["asset"]["sync_status"] == "pending"

    api.request_json(
        "POST",
        "/api/v1/mcp/asset/create-upload-url",
        expected_status=422,
        json={"filename": "bad.txt", "asset_type": "invalid"},
    )

    external = api.request_json(
        "POST",
        "/api/v1/mcp/asset/register-external-url",
        json={
            "external_url": f"https://example.com/lifly-mcp-pytest-{run_id}",
            "title": f"MCP pytest external link {run_id}",
            "asset_type": "link",
        },
    )

    assert external["asset"]["kind"] == "external"
    assert external["asset"]["sync_status"] == "synced"
    assert external["asset"]["external_url"].startswith(
        "https://example.com/lifly-mcp-pytest-"
    )


def test_mcp_capture_parse_commit_and_undo_contract(
    api: LiflyApiClient,
    run_id: str,
) -> None:
    parsed = api.request_json(
        "POST",
        "/api/v1/mcp/capture/parse",
        json={
            "text": f"记一下 Lifly MCP pytest capture {run_id}",
            "timezone": "Asia/Shanghai",
            "locale": "zh-CN",
        },
    )

    capture_id = parsed["capture_id"]
    assert capture_id
    assert len(parsed["actions"]) >= 1

    committed = api.request_json(
        "POST",
        "/api/v1/mcp/capture/commit",
        json={"capture_id": capture_id},
    )

    undo_token = committed["undo_token"]
    assert undo_token
    assert committed["committed"] is True
    assert len(committed["created_entities"]) >= 1

    undone = api.request_json(
        "POST",
        "/api/v1/mcp/capture/undo",
        json={"undo_token": undo_token},
    )

    assert undone["undone"] >= 1
    assert undone["failed_entities"] == []

    repeated = api.request_json(
        "POST",
        "/api/v1/mcp/capture/undo",
        json={"undo_token": undo_token},
    )

    assert repeated["undone"] == 0
    assert repeated["entities"] == []
    assert repeated["failed_entities"] == []
