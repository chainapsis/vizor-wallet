"""Font coverage/freshness contracts; run with .dart_tool/ui_fonts/venv Python."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("ui_fonts", ROOT / "tool/l10n/ui_fonts.py")
ui_fonts = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui_fonts)


class UiFontTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        lock, _, _ = ui_fonts.inputs(ROOT)
        files = [ui_fonts.LOCK, ui_fonts.MANIFEST, "tool/l10n/ui_fonts.py",
                 "tool/l10n/ui_font_characters.json", "tool/l10n/ui_font_characters.dart", "pubspec.lock",
                 "lib/src/core/l10n/app_language.dart"]
        for font in lock["fonts"]:
            files.extend([font["arb"], font["output"]])
            if "include_character_file" in font:
                files.append(font["include_character_file"])
        for relative in files:
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / relative, target)

    def test_known_hangul_is_already_covered_and_new_han_character_regenerates(self):
        from fontTools.ttLib import TTFont
        self.assertTrue(ui_fonts.is_current(self.root))
        path = self.root / "lib/l10n/source/app_ko.arb"
        arb = json.loads(path.read_text(encoding="utf-8"))
        arb["testNewCharacter"] = "힣"
        path.write_text(json.dumps(arb, ensure_ascii=False), encoding="utf-8")
        self.assertTrue(ui_fonts.is_current(self.root))
        # Find an upstream-supported Han character outside the selected table.
        lock, _, _ = ui_fonts.inputs(ROOT)
        config = next(f for f in lock["fonts"] if f["locale"] == "zh")
        source = TTFont(ROOT / ".dart_tool/ui_fonts/sources" / (config["sha256"] + ".ttf"))
        current = TTFont(ROOT / config["output"])
        new_han = next(cp for cp in sorted(source.getBestCmap())
                       if 0x4E00 <= cp <= 0x9FFF and cp not in current.getBestCmap())
        chinese_path = self.root / "lib/l10n/app_zh.arb"
        chinese = json.loads(chinese_path.read_text(encoding="utf-8"))
        chinese["testNewCharacter"] = chr(new_han)
        chinese_path.write_text(json.dumps(chinese, ensure_ascii=False), encoding="utf-8")
        self.assertFalse(ui_fonts.is_current(self.root))
        # Use already checksum-verified source files: tests never download.
        lock, _, _ = ui_fonts.inputs(ROOT)
        for font in lock["fonts"]:
            source = ROOT / ".dart_tool/ui_fonts/sources" / (font["sha256"] + ".ttf")
            target = self.root / ".dart_tool/ui_fonts/sources" / source.name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        with patch.object(ui_fonts, "fetch_source", wraps=ui_fonts.fetch_source) as fetched:
            ui_fonts.build(self.root)
        self.assertEqual([call.args[1]["locale"] for call in fetched.call_args_list], ["zh"])
        self.assertTrue(ui_fonts.is_current(self.root))
        font = TTFont(self.root / "assets/fonts/VizorKoreanUI-VF.ttf")
        self.assertIn(ord("힣"), font.getBestCmap())
        chinese_font = TTFont(self.root / "assets/fonts/VizorChineseUI-VF.ttf")
        self.assertIn(new_han, chinese_font.getBestCmap())

    def test_modified_output_is_rejected(self):
        path = self.root / "assets/fonts/VizorChineseUI-VF.ttf"
        path.write_bytes(path.read_bytes() + b"modified")
        self.assertFalse(ui_fonts.is_current(self.root))

    def test_shipped_fonts_cover_ui_and_keep_variable_weights(self):
        from fontTools.ttLib import TTFont
        lock, characters, _ = ui_fonts.inputs(ROOT)
        combined = set()
        ui = set()
        for config in lock["fonts"]:
            font = TTFont(ROOT / config["output"])
            source = TTFont(ROOT / ".dart_tool/ui_fonts/sources" / (config["sha256"] + ".ttf"))
            expected = set(characters[config["locale"]]).intersection(source.getBestCmap())
            self.assertTrue(expected.issubset(font.getBestCmap()))
            extras = ui_fonts.additional_characters(ROOT, config)
            if config["locale"] == "ko":
                self.assertTrue(set(range(0xAC00, 0xD7A4)).issubset(font.getBestCmap()))
                self.assertTrue(set(range(0x3131, 0x3164)).issubset(font.getBestCmap()))
            else:
                self.assertEqual(len(extras), 8105)
                self.assertTrue(extras.issubset(font.getBestCmap()))
            arb = json.loads((ROOT / config["arb"]).read_text(encoding="utf-8"))
            ui.update(ord(c) for k, v in arb.items() if not k.startswith("@")
                      and isinstance(v, str) for c in v if ord(c) >= 32)
            combined.update(font.getBestCmap())
            self.assertIn("wght", {a.axisTag for a in font["fvar"].axes})
            self.assertTrue(all("Pretendard" not in str(n) for n in font["name"].names
                                if n.nameID not in {0, 13, 14}))
        self.assertTrue({ord(c) for c in "한국어简体中文"}.issubset(combined))
        self.assertIn(0x200D, combined)
        self.assertTrue({ord(c) for c in "년年星期四五午"}.issubset(combined))
        self.assertTrue(ui.issubset(combined))

    def test_changed_character_dataset_is_rejected(self):
        path = self.root / "tool/l10n/character_sets/tgh_2013.txt"
        path.write_bytes(path.read_bytes() + b"# modified\n")
        with self.assertRaisesRegex(ValueError, "Character-set checksum mismatch"):
            ui_fonts.is_current(self.root)

    def test_outputs_cannot_escape_through_symlink(self):
        path = self.root / "assets/fonts/VizorKoreanUI-VF.ttf"
        path.unlink()
        path.symlink_to(ROOT / "assets/fonts/VizorKoreanUI-VF.ttf")
        with self.assertRaises(ValueError):
            ui_fonts.is_current(self.root)


if __name__ == "__main__":
    unittest.main()
