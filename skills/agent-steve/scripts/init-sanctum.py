#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# ///
"""First Breath — deterministic sanctum scaffolding for Steve.

This script runs BEFORE the conversational awakening. It creates the sanctum
folder structure, copies reference files (capability prompts + guidance) into
the sanctum, copies template files with config values substituted, and
auto-generates CAPABILITIES.md from capability prompt frontmatter.

After this script runs, the sanctum is fully self-contained — Steve does not
depend on the skill bundle location for normal operation (only First Breath
and this init step read from the bundle).

Uses only the Python standard library. Run with `uv run` or plain `python3`.
"""

import argparse
import re
import shutil
import sys
from datetime import date
from pathlib import Path

SKILL_NAME = "agent-steve"
SANCTUM_DIR = SKILL_NAME

# Files that stay in the skill bundle (only used during First Breath).
SKILL_ONLY_FILES = {"first-breath.md"}

# Sanctum skeleton templates copied (with substitution) from assets/.
# CAPABILITIES.md is auto-generated instead of copied.
TEMPLATE_FILES = [
    "INDEX-template.md",
    "PERSONA-template.md",
    "CREED-template.md",
    "BOND-template.md",
    "MEMORY-template.md",
]

# Whether the owner can teach this agent new capabilities at runtime.
EVOLVABLE = False

# Config files searched under _bmad/, in increasing priority. Later files
# override earlier ones, so the modern root config wins over the legacy
# per-module configs this project still uses.
CONFIG_CANDIDATES = [
    "bmb/config.yaml",
    "cis/config.yaml",
    "config.yaml",
    "config.user.yaml",
]


def parse_yaml_config(config_path: Path) -> dict:
    """Parse top-level scalar key: value pairs from a YAML file."""
    config = {}
    if not config_path.exists():
        return config
    for line in config_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or ":" not in line:
            continue
        key, _, value = line.partition(":")
        value = value.strip().strip("'\"")
        if value:
            config[key.strip()] = value
    return config


def parse_frontmatter(file_path: Path) -> dict:
    """Extract YAML frontmatter (top-level scalars) from a markdown file."""
    meta = {}
    content = file_path.read_text()
    match = re.match(r"^---\s*\n(.*?)\n---", content, re.DOTALL)
    if not match:
        return meta
    for line in match.group(1).strip().split("\n"):
        if ":" in line:
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip().strip("'\"")
    return meta


def copy_references(source_dir: Path, dest_dir: Path) -> list[str]:
    """Copy all reference files (except skill-only files) into the sanctum."""
    dest_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for source_file in sorted(source_dir.iterdir()):
        if source_file.name in SKILL_ONLY_FILES or not source_file.is_file():
            continue
        shutil.copy2(source_file, dest_dir / source_file.name)
        copied.append(source_file.name)
    return copied


def copy_scripts(source_dir: Path, dest_dir: Path) -> list[str]:
    """Copy supporting scripts (not this init script) into the sanctum."""
    if not source_dir.exists():
        return []
    dest_dir.mkdir(parents=True, exist_ok=True)
    copied = []
    for source_file in sorted(source_dir.iterdir()):
        if source_file.is_file() and source_file.name != "init-sanctum.py":
            shutil.copy2(source_file, dest_dir / source_file.name)
            copied.append(source_file.name)
    return copied


def discover_capabilities(references_dir: Path, sanctum_refs_path: str) -> list[dict]:
    """Scan references/ for capability prompt files with name+code frontmatter."""
    capabilities = []
    for md_file in sorted(references_dir.glob("*.md")):
        if md_file.name in SKILL_ONLY_FILES:
            continue
        meta = parse_frontmatter(md_file)
        if meta.get("name") and meta.get("code"):
            capabilities.append(
                {
                    "name": meta["name"],
                    "description": meta.get("description", ""),
                    "code": meta["code"],
                    "source": f"{sanctum_refs_path}/{md_file.name}",
                }
            )
    return capabilities


def generate_capabilities_md(capabilities: list[dict], evolvable: bool) -> str:
    """Render CAPABILITIES.md content from discovered capabilities."""
    lines = [
        "# Capabilities",
        "",
        "## Built-in",
        "",
        "| Code | Name | Description | Source |",
        "|------|------|-------------|--------|",
    ]
    for cap in capabilities:
        lines.append(
            f"| [{cap['code']}] | {cap['name']} | {cap['description']} | `{cap['source']}` |"
        )

    if evolvable:
        lines.extend(
            [
                "",
                "## Learned",
                "",
                "_Capabilities added by the owner over time. Prompts live in `capabilities/`._",
                "",
                "| Code | Name | Description | Source | Added |",
                "|------|------|-------------|--------|-------|",
            ]
        )

    lines.extend(
        [
            "",
            "## Tools",
            "",
            "Prefer crafting your own tools over depending on external ones. A script you "
            "wrote and saved is more reliable than an external API. Use the file system "
            "creatively.",
            "",
            "### User-Provided Tools",
            "",
            "_MCP servers, APIs, or services the owner has made available. Document them here._",
        ]
    )
    return "\n".join(lines) + "\n"


def substitute_vars(content: str, variables: dict) -> str:
    """Replace {var_name} placeholders with values from the variables dict."""
    for key, value in variables.items():
        content = content.replace(f"{{{key}}}", value)
    return content


def build_sanctum(project_root: Path, skill_path: Path, verbose: bool) -> int:
    bmad_dir = project_root / "_bmad"
    sanctum_path = bmad_dir / "memory" / SANCTUM_DIR
    assets_dir = skill_path / "assets"
    references_dir = skill_path / "references"
    scripts_dir = skill_path / "scripts"
    sanctum_refs_path = "references"

    if sanctum_path.exists():
        print(f"Sanctum already exists at {sanctum_path}")
        print("Steve has already been born. Skipping First Breath scaffolding.")
        return 0

    config = {}
    for rel in CONFIG_CANDIDATES:
        config.update(parse_yaml_config(bmad_dir / rel))

    variables = {
        "user_name": config.get("user_name", "friend"),
        "communication_language": config.get("communication_language", "English"),
        "birth_date": date.today().isoformat(),
        "project_root": str(project_root),
        "sanctum_path": str(sanctum_path),
    }

    sanctum_path.mkdir(parents=True, exist_ok=True)
    (sanctum_path / "capabilities").mkdir(exist_ok=True)
    (sanctum_path / "sessions").mkdir(exist_ok=True)
    print(f"Created sanctum at {sanctum_path}")

    copied_refs = copy_references(references_dir, sanctum_path / "references")
    print(f"  Copied {len(copied_refs)} reference files to sanctum/references/")
    if verbose:
        for name in copied_refs:
            print(f"    - {name}")

    copied_scripts = copy_scripts(scripts_dir, sanctum_path / "scripts")
    if copied_scripts:
        print(f"  Copied {len(copied_scripts)} scripts to sanctum/scripts/")

    for template_name in TEMPLATE_FILES:
        template_path = assets_dir / template_name
        if not template_path.exists():
            print(f"  Warning: template {template_name} not found, skipping", file=sys.stderr)
            continue
        output_name = template_name.replace("-template", "").upper()[:-3] + ".md"
        content = substitute_vars(template_path.read_text(), variables)
        (sanctum_path / output_name).write_text(content)
        print(f"  Created {output_name}")

    capabilities = discover_capabilities(references_dir, sanctum_refs_path)
    capabilities_content = generate_capabilities_md(capabilities, evolvable=EVOLVABLE)
    (sanctum_path / "CAPABILITIES.md").write_text(capabilities_content)
    print(f"  Created CAPABILITIES.md ({len(capabilities)} built-in capabilities discovered)")

    print()
    print("First Breath scaffolding complete. The conversational awakening can begin.")
    print(f"Sanctum: {sanctum_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Scaffold Steve's sanctum before First Breath (idempotent).",
    )
    parser.add_argument("project_root", help="Project root (where _bmad/ lives)")
    parser.add_argument(
        "skill_path", help="Path to the agent-steve skill directory (SKILL.md, assets/, references/)"
    )
    parser.add_argument("--verbose", action="store_true", help="List every copied file")
    args = parser.parse_args()

    project_root = Path(args.project_root).resolve()
    skill_path = Path(args.skill_path).resolve()

    if not skill_path.exists():
        print(f"Error: skill path does not exist: {skill_path}", file=sys.stderr)
        return 2

    try:
        return build_sanctum(project_root, skill_path, args.verbose)
    except OSError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
