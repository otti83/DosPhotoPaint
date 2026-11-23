#!/usr/bin/env python3
"""Merge compiler-extracted keys (.stringsdata) and Japanese translations into the String Catalogs.

Usage:
  python3 tools/l10n_sync.py [--dd .dd] [--dump]   # --dump prints extracted keys per table as JSON
Translations live in tools/l10n_ja/<Table>.json ({"English key": "日本語"}).
Writes DosPhotoPaint/Resources/<Table>.xcstrings and reports missing translations.

Note: keys that go through a helper taking String.LocalizationValue (MainMenu `t`, ContextMenus `t`,
Toolbar `t`, SettingsLabels `s`, ...) are extracted by the compiler as table "Localizable"; HELPER_TABLES
maps the source file back to the table the helper really uses at runtime.
"""
import argparse, glob, json, os, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER_TABLES = {
    "MainMenu.swift": "Menu", "ContextMenus.swift": "Menu",
    "MainWindowController+Toolbar.swift": "Toolbar",
    "SettingsLabels.swift": "Settings", "ShortcutCatalog.swift": "Settings", "HelpWindowController.swift": "Settings",
    "ImageInfoView.swift": "Viewer", "ImageBrowserView.swift": "Viewer", "ResizeImageSheet.swift": "Paint",
}
# Keys that are intentionally identical in every language (never need a translation).
IDENTICAL = {"DosPhotoPaint", "PNG", "JPEG", "HEIC", "TIFF", "BMP", "px", "%", "", "OK", "ISO", "RGB %lld, %lld, %lld"}

def extract(dd):
    keys = collections.defaultdict(dict)  # table -> key -> comment
    pattern = os.path.join(dd, "Build/Intermediates.noindex/DosPhotoPaint.build/*/DosPhotoPaint.build/Objects-normal/*/*.stringsdata")
    files = glob.glob(pattern)
    if not files:
        sys.exit("no .stringsdata found; build first")
    for f in files:
        d = json.load(open(f))
        base = os.path.basename(d["source"])
        for table, entries in d["tables"].items():
            if table == "Localizable":
                table = HELPER_TABLES.get(base, "Localizable")
            for e in entries:
                if e["key"] == "":
                    continue
                keys[table][e["key"]] = e.get("comment", "")
    return keys

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dd", default=os.path.join(ROOT, ".dd"))
    ap.add_argument("--dump", action="store_true")
    a = ap.parse_args()
    keys = extract(a.dd)
    if a.dump:
        print(json.dumps({t: sorted(k) for t, k in keys.items()}, ensure_ascii=False, indent=1)); return
    missing = 0
    for table, ks in sorted(keys.items()):
        tpath = os.path.join(ROOT, "tools/l10n_ja", table + ".json")
        ja = json.load(open(tpath)) if os.path.exists(tpath) else {}
        strings = {}
        for k in sorted(ks):
            loc = {}
            if k in ja:
                loc["ja"] = {"stringUnit": {"state": "translated", "value": ja[k]}}
            elif k in IDENTICAL:
                loc["ja"] = {"stringUnit": {"state": "translated", "value": k}}
            else:
                print(f"MISSING [{table}] {k!r}"); missing += 1
            entry = {"extractionState": "manual", "localizations": loc}
            strings[k] = entry
        for k in ja:
            if k not in ks:
                print(f"UNUSED translation [{table}] {k!r}")
        out = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
        path = os.path.join(ROOT, "DosPhotoPaint/Resources", table + ".xcstrings")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(out, fh, ensure_ascii=False, indent=2, sort_keys=True); fh.write("\n")
        print(f"{table}: {len(strings)} keys")
    print("missing:", missing)
    sys.exit(1 if missing else 0)

main()
