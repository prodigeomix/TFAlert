#!/usr/bin/env python
"""
tools/run_tests.py
==================
TFAlert verification suite (modelled on the HolyPriest toolbase).

Target runtime: Turtle WoW 1.18.1 client (WoW 1.12.1 FrameXML, Lua 5.0.3),
with optional SuperWoW / Nampower / UnitXP_SP3 present or absent.

Checks, in order:
  1. luac50 -p              Real Lua 5.0.3 compiler parse of every .lua file
  2. validate_lua50         Banned post-5.0 syntax / APIs (#, %, select, string.match ...)
  3. block balance          function/if/do ... end balance
  4. TOC / XML integrity    TOC lists only existing files, XML parses, frame handlers exist
  5. runtime scenarios      tools/test_runtime.lua executed by lua50.exe (mocked 1.12.1 API)

Exit code 0 only if every check passes. Run this before every commit.
"""

import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(TOOLS, ".."))
LUA50 = os.path.join(TOOLS, "bin", "lua50", "lua50.exe")
LUAC50 = os.path.join(TOOLS, "bin", "lua50", "luac50.exe")

BANNED = [
    (r'(?<![A-Za-z0-9_])#\s*[A-Za-z0-9_\{\(\"\']', "length operator '#' (5.1+): use table.getn / string.len"),
    (r'(?<![A-Za-z0-9_])%\s*[A-Za-z0-9_\{\(\"\']', "modulo '%' (5.1+): use math.mod"),
    (r'(?<![A-Za-z0-9_])//(?![A-Za-z0-9_])', "integer division '//' (5.3+)"),
    (r'\bgoto\s+[A-Za-z0-9_]+', "goto (5.2+)"),
    (r'::[A-Za-z0-9_]+::', "label (5.2+)"),
    (r'\bstring\.match\b', "string.match (5.1+): use string.find captures"),
    (r'\bstring\.gmatch\b', "string.gmatch (5.1+): use string.gfind"),
    (r'\btable\.unpack\b', "table.unpack (5.1+): use unpack"),
    (r'\btable\.pack\b', "table.pack (5.2+)"),
    (r'\bselect\s*\(', "select() (5.1+): use arg table"),
    (r'\bmath\.huge\b', "math.huge (5.1+)"),
    (r'\bhooksecurefunc\b', "hooksecurefunc (WoW 2.0+)"),
    (r':HookScript\b', ":HookScript (WoW 2.0+)"),
    (r'\bC_[A-Za-z0-9_]+\b', "C_* namespace (retail API)"),
    (r'\bloadstring\b|\bRunScript\b', "dynamic code execution (forbidden)"),
]


def addon_lua_files():
    out = []
    for f in sorted(os.listdir(ROOT)):
        if f.endswith(".lua"):
            out.append(os.path.join(ROOT, f))
    return out


def strip(line):
    i = line.find("--")
    if i != -1:
        line = line[:i]
    line = re.sub(r'"[^"\\]*(?:\\.[^"\\]*)*"', '""', line)
    line = re.sub(r"'[^'\\]*(?:\\.[^'\\]*)*'", "''", line)
    return line


def check_luac():
    ok = True
    for p in addon_lua_files():
        r = subprocess.run([LUAC50, "-p", p], capture_output=True, text=True)
        if r.returncode != 0:
            print("    FAIL " + os.path.basename(p) + ": " + (r.stderr or r.stdout).strip())
            ok = False
        else:
            print("    ok   " + os.path.basename(p) + " parses under Lua 5.0.3")
    return ok


def check_banned():
    ok = True
    for p in addon_lua_files():
        with open(p, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        for n, raw in enumerate(lines, 1):
            s = strip(raw)
            for pat, desc in BANNED:
                if re.search(pat, s):
                    print("    FAIL %s:%d %s\n         %s" % (os.path.basename(p), n, desc, raw.strip()))
                    ok = False
    if ok:
        print("    ok   no post-5.0 syntax or forbidden APIs")
    return ok


def check_blocks():
    ok = True
    for p in addon_lua_files():
        with open(p, encoding="utf-8") as fh:
            c = fh.read()
        c = re.sub(r"--\[\[.*?\]\]", "", c, flags=re.DOTALL)
        c = re.sub(r"--[^\n]*", "", c)
        c = re.sub(r'"(?:\\.|[^"\\])*"', '""', c)
        c = re.sub(r"'(?:\\.|[^'\\])*'", "''", c)
        depth = 0
        for tok in re.findall(r"\b(function|if|do|end|repeat|until)\b", c):
            if tok in ("function", "if", "do", "repeat"):
                depth += 1
            else:
                depth -= 1
            if depth < 0:
                break
        if depth != 0:
            print("    FAIL %s: unbalanced blocks (depth %d)" % (os.path.basename(p), depth))
            ok = False
        else:
            print("    ok   " + os.path.basename(p) + " blocks balanced")
    return ok


def check_toc_xml():
    ok = True
    tocs = [f for f in os.listdir(ROOT) if f.endswith(".toc")]
    if len(tocs) != 1 or tocs[0] != "TFAlert.toc":
        print("    FAIL expected exactly one TFAlert.toc, found %s" % tocs)
        return False
    with open(os.path.join(ROOT, "TFAlert.toc"), encoding="utf-8") as fh:
        toc = fh.read()
    if "## Interface: 11200" not in toc:
        print("    FAIL TOC Interface must be 11200")
        ok = False
    listed = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
    for f in listed:
        if not os.path.exists(os.path.join(ROOT, f)):
            print("    FAIL TOC lists missing file " + f)
            ok = False
    for f in [x for x in listed if x.endswith(".xml")]:
        try:
            tree = ET.parse(os.path.join(ROOT, f))
        except ET.ParseError as e:
            print("    FAIL %s does not parse: %s" % (f, e))
            ok = False
            continue
        text = ET.tostring(tree.getroot(), encoding="unicode")
        for fn in re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
            found = False
            for p in addon_lua_files():
                with open(p, encoding="utf-8") as fh:
                    if re.search(r"function\s+" + fn + r"\s*\(", fh.read()):
                        found = True
            if not found:
                print("    FAIL %s calls undefined %s()" % (f, fn))
                ok = False
        for s in re.findall(r'file="([^"]+)"', text):
            if not os.path.exists(os.path.join(ROOT, s)):
                print("    FAIL %s references missing %s" % (f, s))
                ok = False
    if ok:
        print("    ok   TOC/XML consistent (" + ", ".join(listed) + ")")
    return ok


def check_runtime():
    r = subprocess.run([LUA50, os.path.join(TOOLS, "test_runtime.lua"), os.path.join(ROOT, "TFAlert.lua")],
                       capture_output=True, text=True, cwd=ROOT)
    out = (r.stdout or "") + (r.stderr or "")
    for l in out.strip().splitlines():
        print("    " + l)
    return r.returncode == 0 and "[FAIL]" not in out


CHECKS = [
    ("Lua 5.0.3 compiler parse (luac50 -p)", check_luac),
    ("Lua 5.0 / 1.12 API compliance", check_banned),
    ("Block balance", check_blocks),
    ("TOC / XML integrity", check_toc_xml),
    ("Runtime scenarios on lua50.exe", check_runtime),
]


def main():
    for exe in (LUA50, LUAC50):
        if not os.path.exists(exe):
            print("Missing " + exe)
            sys.exit(1)
    print("=" * 72)
    print("TFALERT VERIFICATION SUITE  (Lua 5.0.3 / Turtle WoW 1.18.1)")
    print("=" * 72)
    results = []
    for name, fn in CHECKS:
        print("\n>>> " + name)
        results.append((name, fn()))
    print("\n" + "=" * 72)
    for name, ok in results:
        print("  %-8s %s" % ("[PASS]" if ok else "[FAIL]", name))
    print("-" * 72)
    if all(ok for _, ok in results):
        print("OVERALL: ALL %d CHECKS PASSED" % len(results))
        sys.exit(0)
    print("OVERALL: VERIFICATION FAILED")
    sys.exit(1)


if __name__ == "__main__":
    main()
