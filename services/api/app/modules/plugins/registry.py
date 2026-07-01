from __future__ import annotations

import json
from dataclasses import dataclass, field
from typing import Protocol


# ─── Plugin Protocol ──────────────────────────────────────────────────────────

class ImportPlugin(Protocol):
    """导入插件协议。实现此接口即可注册为导入解析器。"""
    name: str
    provider: str
    description: str

    def parse(self, content: bytes) -> dict: ...


@dataclass
class PluginManifest:
    id: str
    display_name: str
    version: str
    description: str
    author: str
    entry_point: str  # "module:function" 格式
    icon: str = "extension"


# ─── Plugin Registry ──────────────────────────────────────────────────────────

@dataclass
class PluginRegistry:
    plugins: dict[str, PluginManifest] = field(default_factory=dict)
    import_handlers: dict[str, ImportPlugin] = field(default_factory=dict)

    def register_manifest(self, manifest: PluginManifest):
        self.plugins[manifest.id] = manifest

    def register_import_handler(self, provider: str, handler: ImportPlugin):
        self.import_handlers[provider] = handler

    def list_manifest(self) -> list[dict]:
        return [
            {
                "id": m.id,
                "display_name": m.display_name,
                "version": m.version,
                "description": m.description,
                "author": m.author,
                "icon": m.icon,
            }
            for m in self.plugins.values()
        ]


# ─── Global Registry ──────────────────────────────────────────────────────────

_registry = PluginRegistry()


def get_registry() -> PluginRegistry:
    return _registry


# ─── Built-in Plugins ─────────────────────────────────────────────────────────

_registry.register_manifest(PluginManifest(
    id="lifly.core.import",
    display_name="通用导入",
    version="1.0.0",
    description="CSV（通用/支付宝/微信）、飞书、Notion、Obsidian 导入",
    author="Lifly Team",
    entry_point="imexport.csv_parser:parse_generic_csv",
    icon="file_present",
))

_registry.register_manifest(PluginManifest(
    id="lifly.core.export",
    display_name="通用导出",
    version="1.0.0",
    description="CSV/JSON/Markdown 导出",
    author="Lifly Team",
    entry_point="imexport.exporter:export_entities",
    icon="file_download",
))

_registry.register_manifest(PluginManifest(
    id="lifly.core.calendar",
    display_name="ICS 日历",
    version="1.0.0",
    description="ICS（RFC 5545）日历导入/导出",
    author="Lifly Team",
    entry_point="imexport.ics_handler:parse_ics",
    icon="calendar_month",
))

_registry.register_manifest(PluginManifest(
    id="lifly.core.capture",
    display_name="AI 混合输入",
    version="1.0.0",
    description="自然语言捕获（capture_parse/commit/undo）",
    author="Lifly Team",
    entry_point="mcp.parse_engine:parse_mixed_input",
    icon="smart_toy",
))
