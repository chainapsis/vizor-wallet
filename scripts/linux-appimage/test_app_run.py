#!/usr/bin/env python3
"""Test the generated AppRun with native ELF fixtures; no wallet is opened."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


PACKAGER = Path(__file__).resolve().parents[1] / "package-linux-appimage.sh"
LIBRARY = "libvizor_apprun_probe.so"


@unittest.skipUnless(sys.platform == "linux" and shutil.which("cc"),
                     "Requires Linux, Bash, and a C compiler")
class AppRunTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="vizor-apprun-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.appdir = self.root / "AppDir with spaces"
        self.hostile = self.root / "hostile"
        self.hostile.mkdir()
        (self.hostile / "relative").mkdir()
        for directory in ("usr/bin/lib", "usr/lib"):
            (self.appdir / directory).mkdir(parents=True)
        self.marker = self.root / "injected"
        self.environment = dict(os.environ)
        self.environment.pop("LD_LIBRARY_PATH", None)
        self.environment.pop("APPDIR", None)
        self.environment.pop("GST_PLUGIN_SCANNER", None)
        self.environment["VIZOR_TEST_MARKER"] = str(self.marker)

        # Execute the actual generator, without running the packaging pipeline.
        source = PACKAGER.read_text()
        start = source.index("write_app_run() {\n")
        end = source.index("\n}\n", start) + 3
        subprocess.run(["bash", "-c", source[start:end] + "\nwrite_app_run"],
                       env=dict(self.environment, APPDIR=str(self.appdir),
                                BINARY_NAME="probe"), check=True)

        self.good = self.root / LIBRARY
        self.compile("good.c", "int vizor_probe(void) { return 7; }",
                     "-shared", "-fPIC", "-Wl,-soname," + LIBRARY,
                     "-o", str(self.good))
        self.compile("evil.c", '''
#include <stdio.h>
#include <stdlib.h>
__attribute__((constructor)) static void injected(void) {
    FILE *file = fopen(getenv("VIZOR_TEST_MARKER"), "w");
    if (file) { fputs("injected", file); fclose(file); }
}
int vizor_probe(void) { return 99; }
''', "-shared", "-fPIC", "-Wl,-soname," + LIBRARY,
                     "-o", str(self.hostile / LIBRARY))
        shutil.copyfile(self.hostile / LIBRARY, self.hostile / "relative" / LIBRARY)
        self.compile("probe.c", '''
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
extern int vizor_probe(void);
int main(int argc, char **argv) {
    volatile double zero = 0;
    if (cos(zero) != 1 || vizor_probe() != 7) return 42;
    printf("ld=%s\\n", getenv("LD_LIBRARY_PATH"));
    printf("gst=%s\\n", getenv("GST_PLUGIN_PATH_1_0"));
    const char *scanner = getenv("GST_PLUGIN_SCANNER");
    if (scanner) printf("scanner=%s\\n", scanner);
    for (int i = 1; i < argc; ++i) printf("arg=%s\\n", argv[i]);
    return argc > 1 && strcmp(argv[1], "--exit-23") == 0 ? 23 : 0;
}
''', "-L" + str(self.root), "-lvizor_apprun_probe", "-lm",
                     "-o", str(self.appdir / "usr/bin/probe"))

    def compile(self, name, source, *arguments):
        path = self.root / name
        path.write_text(source)
        subprocess.run(["cc", str(path), *arguments], check=True, timeout=30)

    def launch(self, inherited=None, arguments=(), appdir_override=None):
        environment = dict(self.environment)
        if inherited is not None:
            environment["LD_LIBRARY_PATH"] = inherited
        if appdir_override is not None:
            environment["APPDIR"] = appdir_override
        return subprocess.run([str(self.appdir / "AppRun"), *arguments],
                              cwd=self.hostile, env=environment,
                              capture_output=True, text=True, timeout=10)

    def test_hostile_libraries_are_not_loaded(self):
        # No bundled probe library: the safe loader must reject the binary.
        for inherited in (None, "", ":", ".", "relative", str(self.hostile),
                          ":/usr/lib::", ";/usr/lib;", "/usr/lib;;/lib"):
            with self.subTest(inherited=inherited):
                self.marker.unlink(missing_ok=True)
                result = self.launch(inherited)
                self.assertFalse(self.marker.exists(), result.stderr)
                self.assertEqual(result.returncode, 127, result.stdout + result.stderr)
                self.assertIn(LIBRARY, result.stderr)

    def test_bundled_and_system_libraries_arguments_and_scanner(self):
        scanner = self.appdir / "usr/lib/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner"
        scanner.parent.mkdir(parents=True)
        scanner.write_text("#!/bin/sh\nexit 0\n")
        scanner.chmod(0o755)
        arguments = ("zcash:test?memo=a%20b#fragment", "with spaces", "")
        for directory, appdir_override in (
            ("usr/bin/lib", None), ("usr/lib", str(self.appdir)),
            ("usr/lib", os.path.relpath(self.appdir, self.hostile)),
        ):
            with self.subTest(directory=directory, appdir=appdir_override):
                library = self.appdir / directory / LIBRARY
                shutil.copyfile(self.good, library)
                result = self.launch(str(self.hostile), arguments, appdir_override)
                library.unlink()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.marker.exists())
                self.assertEqual(result.stdout.splitlines(), [
                    f"ld={self.appdir}/usr/bin/lib:{self.appdir}/usr/lib",
                    f"gst={self.appdir}/usr/lib/gstreamer-1.0",
                    f"scanner={scanner}", *[f"arg={value}" for value in arguments],
                ])

    def test_exit_status_without_bundled_scanner(self):
        shutil.copyfile(self.good, self.appdir / "usr/lib" / LIBRARY)
        result = self.launch(arguments=("--exit-23",))
        self.assertEqual(result.returncode, 23, result.stderr)
        self.assertNotIn("scanner=", result.stdout)

    def test_appdir_search_path_separators_are_rejected(self):
        planted = self.hostile / "relative/usr/bin/lib"
        planted.mkdir(parents=True)
        shutil.copyfile(self.hostile / LIBRARY, planted / LIBRARY)
        for separator in (":", ";"):
            with self.subTest(separator=separator):
                renamed = self.root / f"AppDir{separator}relative"
                self.appdir.rename(renamed)
                self.appdir = renamed
                shutil.copyfile(self.good, self.appdir / "usr/bin/lib" / LIBRARY)
                self.marker.unlink(missing_ok=True)
                result = self.launch()
                self.assertFalse(self.marker.exists(), result.stderr)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn("AppDir path contains a library-path separator", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
