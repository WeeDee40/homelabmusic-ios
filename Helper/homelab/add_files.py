#!/usr/bin/env python3
"""Fügt Swift-Dateien aus Amperfy/HomeLab/ dem Ziel «Amperfy» hinzu (Gruppe «HomeLab»), falls noch nicht drin.
Aufruf im Repo-Wurzelverzeichnis: python3 Helper/homelab/add_files.py"""
import hashlib, os, re

P = "Amperfy.xcodeproj/project.pbxproj"
TARGET_SOURCES = "508385E021C5965B00C4BB32"
MAIN_GROUP = "508385E621C5965B00C4BB32"
s = open(P).read()

def uid(text):
    return hashlib.md5(("homelab:" + text).encode()).hexdigest()[:24].upper()

def section_add(name, eintrag):
    global s
    s = s.replace(f"/* End {name} section */", eintrag + f"/* End {name} section */", 1)

gruppe = uid("group")
if gruppe not in s:
    section_add("PBXGroup", f'\t\t{gruppe} /* HomeLab */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n\t\t\tpath = HomeLab;\n\t\t\tsourceTree = "<group>";\n\t\t}};\n')
    s = re.sub(rf"({MAIN_GROUP} /\* Amperfy \*/ = \{{\s*isa = PBXGroup;\s*children = \()", rf"\1\n\t\t\t\t{gruppe} /* HomeLab */,", s, count=1)

for name in sorted(os.listdir("Amperfy/HomeLab")):
    if not name.endswith(".swift"):
        continue
    ref, build = uid("ref:" + name), uid("build:" + name)
    if ref in s:
        continue
    section_add("PBXFileReference", f'\t\t{ref} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n')
    section_add("PBXBuildFile", f'\t\t{build} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {ref} /* {name} */; }};\n')
    s = re.sub(rf"({gruppe} /\* HomeLab \*/ = \{{\s*isa = PBXGroup;\s*children = \()", rf"\1\n\t\t\t\t{ref} /* {name} */,", s, count=1)
    s = re.sub(rf"({TARGET_SOURCES} /\* Sources \*/ = \{{\s*isa = PBXSourcesBuildPhase;\s*buildActionMask = \d+;\s*files = \()",
               rf"\1\n\t\t\t\t{build} /* {name} in Sources */,", s, count=1)
    print("hinzugefügt:", name)
open(P, "w").write(s)
