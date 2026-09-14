#!/usr/bin/env python3
"""Focused checks for Markdown extraction and deterministic graph generation."""

import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import generate


class MarkdownTests(unittest.TestCase):
    def test_fences_code_images_and_definitions_are_not_relationships(self):
        text = """# Example

```markdown
[not a relationship](missing.md)
```
~~~
[also ignored](missing.md)
~~~
`[inline code](missing.md)` and ![image](picture.md).
\\[escaped](missing.md)

- When cancellation changes, read
  [the release contract][release].
| Condition | [Owner](owner.md) |

[release]: release.md "Release title"
"""
        links = generate.extract_links(text)
        self.assertEqual([link.href for link in links], ["release.md", "owner.md"])
        self.assertEqual(links[0].context, "- When cancellation changes, read\n  [the release contract][release].")
        self.assertEqual(links[0].line, 13)
        self.assertEqual(links[1].context, "| Condition | [Owner](owner.md) |")

    def test_balanced_destinations_angle_paths_titles_and_reference_links(self):
        text = """[Paren](folder/owner(v2).md#heading "Title")
[Space](<folder/owner name.md#heading>)
[Escaped](owner\\(v2\\).md)
[Entity](owner.md?a=1&amp;b=2)
[Repeated][] and [shortcut].

[repeated]: owner.md
[shortcut]: <owner.md#heading>
"""
        self.assertEqual(
            [link.href for link in generate.extract_links(text)],
            ["folder/owner(v2).md#heading", "folder/owner name.md#heading", "owner(v2).md", "owner.md?a=1&b=2", "owner.md", "owner.md#heading"],
        )

    def test_heading_anchors_include_duplicates_unicode_setext_and_explicit_ids(self):
        text = """# Repeated
## Repeated-1
## Repeated
## 계정 `ID` & 상태
Setext heading
---
<a id="CustomAnchor"></a>
```
## Not a heading
```
"""
        self.assertEqual(
            generate.heading_anchors(text),
            {"repeated", "repeated-1", "repeated-2", "계정-id--상태", "setext-heading", "CustomAnchor"},
        )

class GraphTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.write("AGENTS.md", "# Project\n\n[Domains](docs/contracts/domains/index.md).\n[References](docs/contracts/references/index.md).\n[Platforms](docs/contracts/platforms/index.md).\n[Map guide](docs/contract-map.md).\n")
        self.write("docs/contracts/domains/index.md", "# Domains\n\nChoose the owner.\n\n| Change | Contract |\n| Release | [Release](send/release.md#release) |\n")
        self.write("docs/contracts/domains/send/index.md", "# Send\n\n[Release](release.md).\n")
        self.write("docs/contracts/domains/send/release.md", "# Send\n\nRead when changing `discardSendProposal`.\n\n## Release\n\n- When retry changes, read [Guide](../../../../guide.md#verification).\n- When signing changes, read [Recovery](../../references/signing/recovery.md).\n- Implementation: [source](../../../../src/owner.py).\n- For remote specifications: [spec](https://example.org/spec).\n")
        self.write("docs/contracts/references/index.md", "# References\n\n[Signing](signing/recovery.md).\n")
        self.write("docs/contracts/references/signing/recovery.md", "# Signing\n\n[Release](../transactions/release.md).\n")
        self.write("docs/contracts/references/transactions/release.md", "# Release\n")
        self.write("docs/contracts/platforms/index.md", "# Platforms\n\n[Signing](../references/signing/recovery.md).\n[Keychain](apple/keychain.md).\n")
        self.write("docs/contracts/platforms/apple/keychain.md", "# Keychain\n")
        self.write("docs/contracts/guides/consumer.md", "# Consumer\n\n[Send](../domains/send/release.md).\n[Sibling](sibling.md).\n")
        self.write("docs/contracts/guides/sibling.md", "# Sibling\n")
        self.write("guide.md", "# External guide\n\nGuide summary.\n\n## Verification\n\n[Do not crawl](not-present.md).\n")
        self.write("src/owner.py", "pass\n")

    def write(self, relative, text):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_direct_document_links_terminal_guides_and_determinism(self):
        graph = generate.build_graph(self.root)
        nodes = graph["nodes"]
        self.assertEqual(nodes["AGENTS.md"]["kind"], "root")
        self.assertEqual(nodes["docs/contracts/domains/index.md"]["kind"], "index")
        self.assertTrue(nodes["guide.md"]["terminal"])
        self.assertFalse(any(edge["source"] == "guide.md" for edge in graph["edges"]))
        self.assertNotIn("src/owner.py", nodes)
        self.assertFalse(any("contract-map" in key for key in nodes))
        self.assertTrue(all(edge["kind"] == ("route" if nodes[edge["source"]]["kind"] in {"root", "index"} else "reference") for edge in graph["edges"]))
        self.assertEqual(graph, generate.build_graph(self.root))

    def test_scope_outgoing_incoming_and_folder_do_not_expand_recursively(self):
        graph = generate.build_graph(self.root)
        scope = "domains/send/release.md"
        outgoing = generate.select_scope(graph, scope)
        self.assertEqual(set(outgoing["nodes"]), {"docs/contracts/" + scope, "guide.md", "docs/contracts/references/signing/recovery.md"})
        self.assertEqual(len(outgoing["edges"]), 2)
        incoming = generate.select_scope(graph, scope, incoming=True)
        self.assertIn("docs/contracts/guides/consumer.md", incoming["nodes"])
        self.assertNotIn("docs/contracts/guides/sibling.md", incoming["nodes"])
        self.assertNotIn("docs/contracts/references/transactions/release.md", incoming["nodes"])
        folder = generate.select_scope(graph, "domains/send/")
        self.assertIn("docs/contracts/domains/send/index.md", folder["nodes"])
        self.assertEqual(len(folder["edges"]), 3)
        self.assertEqual(generate.select_scope(graph, "AGENTS.md")["edges"], graph["edges"][:3])

    def test_empty_missing_or_escaping_scopes_fail(self):
        graph = generate.build_graph(self.root)
        for scope in ("", "/", "../guide.md", "domains/../send", "domains/sen", "guide.md", "docs/contracts/domains/send"):
            with self.subTest(scope=scope), self.assertRaises(generate.GraphError):
                generate.select_scope(graph, scope)

    def test_overview_collapses_direct_routes_to_queryable_groups(self):
        graph = generate.overview(generate.build_graph(self.root))
        self.assertEqual(set(graph["nodes"]), {"AGENTS.md", *generate.ENTRIES, "docs/contracts/domains/send", "docs/contracts/references/signing", "docs/contracts/platforms/apple"})
        self.assertIn(("docs/contracts/platforms/index.md", "docs/contracts/references/signing"), {(edge["source"], edge["target"]) for edge in graph["edges"]})
        self.assertNotIn("docs/contracts/references/transactions", graph["nodes"])
        for key, node in graph["nodes"].items():
            if node["kind"] == "group":
                self.assertTrue(generate.select_scope(generate.build_graph(self.root), generate.display_path(key))["nodes"])

    def test_missing_document_and_anchor_fail_with_the_referring_line(self):
        self.write("AGENTS.md", "# Root\n\n[Missing](missing.md)\n")
        with self.assertRaisesRegex(generate.GraphError, r"AGENTS.md:3: Missing document: missing.md"):
            generate.build_graph(self.root)
        self.write("AGENTS.md", "# Root\n\n[Missing](guide.md#absent)\n")
        with self.assertRaisesRegex(generate.GraphError, r"AGENTS.md:3: Missing anchor: guide.md#absent"):
            generate.build_graph(self.root)

    def test_encoded_paths_and_anchors_resolve_before_validation(self):
        self.write("AGENTS.md", "# Root\n\n[Guide](My%20Guide.md#%EA%B3%84%EC%A0%95)\n")
        self.write("My Guide.md", "# 계정\n\nA guide.\n")
        graph = generate.build_graph(self.root)
        edge = next(edge for edge in graph["edges"] if edge["source"] == "AGENTS.md")
        self.assertEqual(edge["target"], "My Guide.md")

    def test_cli_prints_markdown_without_writing_files_and_requires_a_mode(self):
        script_path = self.write("scripts/contract-graph/generate.py", "")
        before = {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()}
        for args in (["--scope", "domains/send"], ["--scope", "domains/send", "--incoming"], ["--overview"]):
            output = io.StringIO()
            with patch.object(generate, "__file__", str(script_path)), contextlib.redirect_stdout(output):
                self.assertEqual(generate.main(args), 0)
            self.assertIn("```mermaid\nflowchart LR\n", output.getvalue())
            self.assertTrue(output.getvalue().endswith("```\n"))
        self.assertEqual(before, {path: path.read_bytes() for path in self.root.rglob("*") if path.is_file()})
        for args in ([], ["--overview", "--scope", "domains/send"], ["--overview", "--incoming"]):
            with self.subTest(args=args), contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as error:
                generate.main(args)
            self.assertEqual(error.exception.code, 2)


class RenderingTests(unittest.TestCase):
    def test_conditions_are_complete_and_do_not_drop_trailing_qualifiers(self):
        self.assertEqual(generate.reading_condition("| Release succeeds \\| refresh fails | [Owner](owner.md) |"), "Release succeeds \\| refresh fails")
        self.assertEqual(generate.reading_condition("- When changing exit cleanup, read [Owner](owner.md)."), "When changing exit cleanup")
        self.assertEqual(generate.reading_condition("For signing recovery, read\n[Owner](owner.md)."), "For signing recovery")
        for context in ("When changing exit cleanup, read [Owner](owner.md) only after drain.", "Preserve the [Owner](owner.md) behavior while signing is open.", "| " + "long condition " * 20 + " | [Owner](owner.md) |"):
            self.assertIsNone(generate.reading_condition(context))

    def test_mermaid_escapes_paths_labels_and_uses_source_lines_without_repeating_nodes(self):
        source, target = 'docs/contracts/domains/send/[strange]"|<path>.md', "guide.md"
        graph = {"nodes": {source: {"terminal": False}, target: {"terminal": True}}, "edges": [
            {"source": source, "target": target, "kind": "reference", "label": 'Owner "details"', "context": "Long explanatory prose.", "line": 12},
        ]}
        rendered = generate.render_mermaid(graph, "Scope")
        self.assertIn('-.->|"Owner #34;details#34; · L12"|', rendered)
        self.assertIn("domains/send/#91;strange#93;#34;#124;#60;path#62;.md", rendered)
        self.assertIn('["@guide.md"]', rendered)
        self.assertNotIn("Long explanatory prose", rendered)
        self.assertEqual(rendered.count("@guide.md"), 1)
        self.assertEqual(rendered.count("```"), 2)
        self.assertEqual(rendered, generate.render_mermaid(graph, "Scope"))


if __name__ == "__main__":
    unittest.main()
