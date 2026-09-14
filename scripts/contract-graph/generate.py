#!/usr/bin/env python3
"""Print a focused Mermaid reading map from the current Markdown links."""

from __future__ import annotations

import argparse
from bisect import bisect_right
from dataclasses import dataclass
from html import unescape
from html.parser import HTMLParser
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit


EXCLUDED = {"docs/contract-map.md"}
CONTRACTS = "docs/contracts/"
ENTRIES = tuple(CONTRACTS + section + "/index.md" for section in ("domains", "references", "platforms"))
LIST_ITEM = re.compile(r"^\s*(?:[-+*]|\d+[.)])\s+")
HEADING = re.compile(r"^ {0,3}(#{1,6})(?:[ \t]+|$)(.*)$")
DEFINITION = re.compile(
    r"^ {0,3}\[([^\]\n]+)\]:[ \t]*(?:<([^>\n]*)>|(\S+))", re.MULTILINE
)


class GraphError(ValueError):
    """A document relationship cannot be represented faithfully."""


@dataclass(frozen=True)
class MarkdownLink:
    label: str
    href: str
    context: str
    line: int


def blank(text: str) -> str:
    return "".join(char if char in "\r\n" else " " for char in text)


def without_fences(text: str) -> str:
    """Mask fenced blocks without changing offsets or line numbers."""
    result = []
    fence = None
    for line in text.splitlines(keepends=True):
        content = line.rstrip("\r\n")
        if fence:
            result.append(blank(line))
            char, length = fence
            if re.fullmatch(r" {0,3}" + re.escape(char) + "{" + str(length) + r",}[ \t]*", content):
                fence = None
            continue
        match = re.match(r"^ {0,3}(`{3,}|~{3,})(.*)$", content)
        if match and not (match[1][0] == "`" and "`" in match[2]):
            fence = (match[1][0], len(match[1]))
            result.append(blank(line))
        else:
            result.append(line)
    return "".join(result)


def code_spans(text: str):
    position = 0
    while position < len(text):
        start = text.find("`", position)
        if start < 0:
            return
        opening = re.match(r"`+", text[start:])[0]
        end = start + len(opening)
        while True:
            end = text.find(opening, end)
            if end < 0:
                position = start + len(opening)
                break
            closing_end = end + len(opening)
            if text[end - 1] != "`" and (closing_end == len(text) or text[closing_end] != "`"):
                yield start, closing_end, text[start + len(opening):end]
                position = closing_end
                break
            end = closing_end


def escaped(text: str, index: int) -> bool:
    preceding = 0
    while index > 0 and text[index - 1] == "\\":
        preceding += 1
        index -= 1
    return preceding % 2 == 1


def markdown_unescape(text: str) -> str:
    return unescape(re.sub(r"\\([!\"#$%&'()*+,\-./:;<=>?@\[\]\\^_`{|}~])", r"\1", text))


def plain_text(text: str) -> str:
    text = re.sub(r"!?\[([^\]]+)\]\([^)]*\)", r"\1", text)
    text = re.sub(r"\[([^\]]+)\]\[[^\]]*\]", r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"(`+|\*\*|__|~~)", "", text)
    return " ".join(markdown_unescape(text).split())


def destination(text: str, start: int):
    """Read an inline destination and optional title, including balanced ()."""
    pos = start
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos < len(text) and text[pos] == "<":
        end = pos + 1
        while end < len(text) and (text[end] != ">" or escaped(text, end)):
            if text[end] in "\r\n":
                return None
            end += 1
        if end == len(text):
            return None
        target = text[pos + 1:end]
        pos = end + 1
    else:
        begin, depth = pos, 0
        while pos < len(text):
            char = text[pos]
            if escaped(text, pos):
                pos += 1
                continue
            if char == "(":
                depth += 1
            elif char == ")":
                if depth == 0:
                    break
                depth -= 1
            elif char.isspace() and depth == 0:
                break
            pos += 1
        if depth:
            return None
        target = text[begin:pos]
    before_space = pos
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos < len(text) and text[pos] == ")":
        return markdown_unescape(target), pos + 1
    if pos == before_space or pos == len(text) or text[pos] not in "\"'(":
        return None
    closer = ")" if text[pos] == "(" else text[pos]
    pos += 1
    while pos < len(text) and (text[pos] != closer or escaped(text, pos)):
        pos += 1
    pos += 1
    while pos < len(text) and text[pos].isspace():
        pos += 1
    if pos < len(text) and text[pos] == ")":
        return markdown_unescape(target), pos + 1
    return None


def normalize_reference(label: str) -> str:
    return " ".join(markdown_unescape(label).split()).casefold()


def context_blocks(text: str, visible: str, definition_lines: set[int]):
    """Retain a paragraph, list item, or table row exactly as authored."""
    originals = text.splitlines(keepends=True)
    masks = visible.splitlines(keepends=True)
    blocks, pending = [], []
    position = start = 0

    def flush():
        if pending:
            blocks.append((start, position, "".join(pending).strip()))
            pending.clear()

    for number, (line, mask) in enumerate(zip(originals, masks)):
        if not mask.strip() or number in definition_lines:
            flush()
            position += len(line)
            continue
        single = mask.lstrip().startswith("|") or HEADING.match(mask)
        if single or LIST_ITEM.match(mask):
            flush()
        if not pending:
            start = position
        pending.append(line)
        position += len(line)
        if single:
            flush()
    flush()
    return blocks


def extract_links(text: str) -> list[MarkdownLink]:
    visible = without_fences(text)
    line_starts = [0] + [match.end() for match in re.finditer("\n", text)]
    definitions, definition_lines = {}, set()
    masked = list(visible)
    for match in DEFINITION.finditer(visible):
        target = match[2] if match[2] is not None else match[3]
        definitions.setdefault(normalize_reference(match[1]), markdown_unescape(target))
        definition_lines.add(bisect_right(line_starts, match.start()) - 1)
        masked[match.start():match.end()] = blank(match[0])
    for start, end, _ in code_spans(visible):
        masked[start:end] = blank(visible[start:end])
    scan = "".join(masked)
    blocks = context_blocks(text, visible, definition_lines)
    block_starts = [block[0] for block in blocks]
    result = []
    position = 0
    while position < len(scan):
        start = scan.find("[", position)
        if start < 0:
            break
        position = start + 1
        if escaped(scan, start) or (start > 0 and scan[start - 1] == "!" and not escaped(scan, start - 1)):
            continue
        end, depth = start + 1, 1
        while end < len(scan) and depth:
            if not escaped(scan, end):
                if scan[end] == "[":
                    depth += 1
                elif scan[end] == "]":
                    depth -= 1
            end += 1
        if depth:
            continue
        label = text[start + 1:end - 1]
        target = None
        if end < len(scan) and scan[end] == "(":
            parsed = destination(scan, end + 1)
            if parsed:
                target, end = parsed
        elif end < len(scan) and scan[end] == "[":
            closing = scan.find("]", end + 1)
            if closing >= 0:
                reference = text[end + 1:closing] or label
                target = definitions.get(normalize_reference(reference))
                end = closing + 1
        else:
            target = definitions.get(normalize_reference(label))
        if target is None:
            continue
        block_index = bisect_right(block_starts, start) - 1
        context = blocks[block_index][2] if block_index >= 0 else text[start:end]
        result.append(MarkdownLink(plain_text(label), target, context, bisect_right(line_starts, start)))
        position = end
    return result


class ExplicitAnchors(HTMLParser):
    def __init__(self):
        super().__init__()
        self.anchors = set()

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if value is not None and (key == "id" or (tag == "a" and key == "name")):
                self.anchors.add(value)


def headings(text: str):
    lines = without_fences(text).splitlines()
    for index, line in enumerate(lines):
        match = HEADING.match(line)
        if match:
            yield plain_text(re.sub(r"[ \t]+#+[ \t]*$", "", match[2]))
        elif index + 1 < len(lines) and line.strip() and not LIST_ITEM.match(line):
            if re.fullmatch(r" {0,3}(?:=+|-+)[ \t]*", lines[index + 1]):
                yield plain_text(line)


def heading_anchors(text: str) -> set[str]:
    anchors = set()
    for heading in headings(text):
        base = re.sub(r"[^\w\- ]", "", heading.lower())
        base = base.replace(" ", "-")
        candidate, suffix = base, 0
        while candidate in anchors:
            suffix += 1
            candidate = f"{base}-{suffix}"
        anchors.add(candidate)
    html = ExplicitAnchors()
    html.feed(without_fences(text))
    return anchors | html.anchors


def build_graph(repo_root: Path) -> dict:
    """Validate the corpus and its direct Markdown targets; never crawl guides."""
    repo_root = repo_root.resolve()
    initial = [repo_root / "AGENTS.md"] + sorted((repo_root / "docs/contracts").rglob("*.md"))
    documents = {}

    def load(path: Path):
        path = path.resolve()
        try:
            identifier = path.relative_to(repo_root).as_posix()
        except ValueError as error:
            raise GraphError(f"Markdown target leaves the repository: {path}") from error
        if identifier not in documents:
            if not path.is_file():
                raise GraphError(f"Missing document: {identifier}")
            text = path.read_text(encoding="utf-8")
            documents[identifier] = (path, text, heading_anchors(text))
        return identifier

    initial_ids = {load(path) for path in initial if path.relative_to(repo_root).as_posix() not in EXCLUDED}
    nodes, edges = {}, []

    def node(identifier: str):
        if identifier in nodes:
            return nodes[identifier]
        path, _, _ = documents[identifier]
        terminal = identifier not in initial_ids
        if identifier == "AGENTS.md":
            kind = "root"
        elif terminal:
            kind = "guide"
        else:
            parts = path.relative_to(repo_root / "docs/contracts").parts
            kind = "index" if path.name == "index.md" else "guide" if parts[0] == "guides" else "contract"
        nodes[identifier] = {"id": identifier, "kind": kind, "terminal": terminal}
        return nodes[identifier]

    for identifier in sorted(initial_ids):
        source = node(identifier)
        path, text, _ = documents[identifier]
        for found in extract_links(text):
            parsed = urlsplit(found.href)
            if parsed.scheme or parsed.netloc:
                continue
            target = ((repo_root if parsed.path.startswith("/") else path.parent) / unquote(parsed.path).lstrip("/")).resolve() if parsed.path else path
            try:
                target_id = target.relative_to(repo_root).as_posix()
            except ValueError:
                target_id = None
            if target_id in EXCLUDED:
                continue
            if target.suffix.lower() == ".md":
                try:
                    target_id = load(target)
                    if parsed.fragment and unquote(parsed.fragment) not in documents[target_id][2]:
                        raise GraphError(f"Missing anchor: {target_id}#{unquote(parsed.fragment)}")
                except GraphError as error:
                    raise GraphError(f"{identifier}:{found.line}: {error}") from error
                node(target_id)
                edges.append({
                    "source": identifier, "target": target_id,
                    "kind": "route" if source["kind"] in {"root", "index"} else "reference",
                    "label": found.label, "context": found.context,
                    "line": found.line,
                })
    return {"nodes": nodes, "edges": edges}


def select_scope(graph: dict, scope: str, incoming: bool = False) -> dict:
    """Select the requested files and one hop only, even with --incoming."""
    if not scope or scope.startswith("/") or any(part in {".", ".."} for part in scope.split("/")):
        raise GraphError("Scope must be AGENTS.md or a path relative to docs/contracts")
    scope = scope.rstrip("/")
    prefix = scope if scope == "AGENTS.md" else CONTRACTS + scope
    selected = {key for key, value in graph["nodes"].items() if not value["terminal"] and (key == prefix or key.startswith(prefix + "/"))}
    if not selected:
        raise GraphError(f"Unknown or empty contract scope: {scope}")
    edges = [edge for edge in graph["edges"] if edge["source"] in selected or (incoming and edge["target"] in selected)]
    included = selected | {edge[key] for edge in edges for key in ("source", "target")}
    return {"nodes": {key: graph["nodes"][key] for key in sorted(included)}, "edges": edges}


def overview(graph: dict) -> dict:
    """Collapse only the three entry indexes' direct routes into owner folders."""
    missing = [key for key in ("AGENTS.md",) + ENTRIES if key not in graph["nodes"]]
    if missing:
        raise GraphError("Missing overview entry: " + ", ".join(missing))
    nodes = {key: graph["nodes"][key] for key in ("AGENTS.md",) + ENTRIES}
    edges, seen = [], set()
    for edge in graph["edges"]:
        source, target = edge["source"], edge["target"]
        if source == "AGENTS.md" and target in ENTRIES:
            pass
        elif source in ENTRIES and target.startswith(CONTRACTS):
            parts = target[len(CONTRACTS):].split("/")
            if len(parts) < 3 or parts[0] not in {"domains", "references", "platforms"}:
                continue
            target = CONTRACTS + "/".join(parts[:2])
            nodes[target] = {"id": target, "kind": "group", "terminal": False}
        else:
            continue
        if (source, target) not in seen:
            seen.add((source, target))
            edges.append({**edge, "target": target})
    return {"nodes": {key: nodes[key] for key in sorted(nodes)}, "edges": edges}


def display_path(identifier: str) -> str:
    return identifier[len(CONTRACTS):] if identifier.startswith(CONTRACTS) else "@" + identifier


def reading_condition(context: str) -> str | None:
    """Use a complete table cell or unqualified explicit read condition only."""
    context = context.strip()
    if context.startswith("|"):
        masked = list(context)
        for start, end, _ in code_spans(context):
            masked[start:end] = blank(context[start:end])
        for end in range(1, len(masked)):
            if masked[end] == "|" and not escaped(context, end):
                cell = context[1:end].strip()
                if cell and len(cell) <= 160 and not extract_links(cell):
                    return cell
                return None
    prose = LIST_ITEM.sub("", context, count=1)
    # Do not discard qualifications after the link (for example, "only if...").
    match = re.fullmatch(
        r"((?:When|For|Before|After|If)\b[^.!?]+?),\s+read\s+"
        r"\[[^\]]+\](?:\([^\n)]+\)|\[[^\]]*\])\.?",
        prose, re.DOTALL,
    )
    if match:
        condition = " ".join(match[1].split())
        if len(condition) <= 160:
            return condition
    return None


def mermaid_escape(text: str) -> str:
    """Mermaid decimal entities keep paths and labels inside quoted nodes."""
    return "".join(f"#{ord(char)};" if char in '&<>"#[]{}|`\\' or ord(char) < 32 else char for char in text)


def markdown_escape(text: str) -> str:
    return re.sub(r"([\\\[\]`|])", r"\\\1", text).replace("<", "&lt;").replace(">", "&gt;")


def render_mermaid(graph: dict, title: str, compact: bool = False) -> str:
    keys = sorted(graph["nodes"])
    aliases = {key: f"n{index}" for index, key in enumerate(keys)}
    lines = [f"# {title}", "", "Paths are relative to `docs/contracts/`; `@` marks repository-root paths. External Markdown guides are terminal.", "", "Solid arrows are authored routes; dotted arrows are authored references, not mandatory dependencies.", ""]
    if compact:
        lines += ["Entry links are grouped by their target folder. Query a displayed folder with `--scope`; leaf contracts are not expanded.", ""]
    else:
        lines += ["Only direct links for the requested scope are shown. L numbers point to the source document. Labels without an explicit reading condition require checking that source line.", ""]
    lines += ["```mermaid", "flowchart LR"]
    for key in keys:
        lines.append(f'  {aliases[key]}["{mermaid_escape(display_path(key))}"]')
    for edge in graph["edges"]:
        arrow = "-->" if edge["kind"] == "route" else "-.->"
        label = ""
        if not compact:
            condition = reading_condition(edge["context"])
            label = (condition or edge["label"] or edge["kind"]) + f" · L{edge['line']}"
            label = '|"' + mermaid_escape(label) + '"|'
        lines.append(f"  {aliases[edge['source']]} {arrow}{label} {aliases[edge['target']]}")
    lines += ["```"]
    return "\n".join(lines) + "\n"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--overview", action="store_true", help="show AGENTS.md, the three entry indexes, and their owner folders")
    mode.add_argument("--scope", metavar="PATH", help="AGENTS.md or a file/folder relative to docs/contracts (for example, domains/donation)")
    parser.add_argument("--incoming", action="store_true", help="include direct references into --scope, without following them recursively")
    args = parser.parse_args(argv)
    if args.incoming and not args.scope:
        parser.error("--incoming requires --scope")
    repo_root = Path(__file__).resolve().parents[2]
    try:
        graph = build_graph(repo_root)
        selected = overview(graph) if args.overview else select_scope(graph, args.scope, args.incoming)
        title = "Contract overview" if args.overview else "Contract scope: " + markdown_escape(args.scope) + (" (including incoming links)" if args.incoming else "")
        print(render_mermaid(selected, title, compact=args.overview), end="")
    except (GraphError, OSError, UnicodeError) as error:
        print(f"Contract graph: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
