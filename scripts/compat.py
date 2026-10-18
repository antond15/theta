#!/usr/bin/env python3
"""Check Theta's hooks and ObjC lookups against an Instagram build.

    ./scripts/compat.py <Instagram.app>                  # what is missing in this build
    ./scripts/compat.py <old-Instagram.app> <new.app>    # what broke between two builds
    ./scripts/compat.py -v ...                           # also list hooks that resolved

Every NullHookMessage*/ThetaInstallMessageHook/ThetaHookFirst call in Source/ is checked
as a (class, selector) pair: the class must exist in the bundle (or the iOS SDK) and the
selector must be on it, one of its categories, or a superclass. Class and selector
arguments passed as variables are traced back to their assignment or for-in list in the
same file; any candidate pair that exists counts as resolved, matching how Theta's
fallback lists behave at runtime.

Class lookups and "_ivar" strings outside hook calls are checked by name only, so they
are lower confidence: an ivar that moved to another class is not flagged.

A pair that resolves can still be broken (changed arguments, behaviour, or a method that
exists but is no longer called). This finds renames and deletions; it does not replace
running the build.

Based on scripts/compat.py by Nico Jan (github.com/nicojan/theta, branch
local-build-notes, commit 5fb3bd4); extended with per-hook (class, selector) checks,
variable tracing, SDK filtering and single-build mode.
"""
import collections
import os
import pathlib
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from objcdump import Image  # noqa: E402

REPO = pathlib.Path(__file__).resolve().parent.parent
MACHO_MAGIC = b"\xcf\xfa\xed\xfe"
HOOK_CALL = re.compile(r"\b(NullHookMessageEx|NullHookMessageIfPresent|NullHookMessage|"
                       r"ThetaInstallMessageHook|ThetaHookFirst|ThetaNSESwizzle)\s*\(")
TRACE_SKIP = {"Class", "SEL", "NSString", "nil", "Nil", "NULL", "self", "UTF8String", "class",
              "objc_getClass", "NSClassFromString", "NSSelectorFromString", "object_getClass",
              "sel_registerName"}
OK, CLASS_MISSING, SEL_MISSING, UNRESOLVED = "ok", "class missing", "selector missing", "unresolved"
SYSTEM = "system, unverified"
# Private UIKit/Foundation names are not in the SDK's .tbd/headers; they exist on device
# but cannot be checked offline.
SYSTEM_PREFIXES = ("__NS", "_NS", "NS", "_UI", "UI", "CA", "AV", "_AV", "PH", "WK", "SF")


# ---------------------------------------------------------------- bundle / SDK indexes

def swift_mangle(name):
    """'Module.Class' -> '_TtC6Module5Class' (the runtime name objc_getClass resolves)."""
    parts = name.split(".")
    if len(parts) != 2 or not all(parts):
        return None
    return "_TtC" + "".join(f"{len(p)}{p}" for p in parts)


class Bundle:
    def __init__(self, app):
        self.path = app
        self.classes = {}   # name -> {"super", "sels" (instance + class + categories)}
        self.ivars = set()
        self.sel_owners = collections.defaultdict(set)
        cat_sels = collections.defaultdict(set)
        for root, _dirs, files in os.walk(app):
            for f in files:
                p = os.path.join(root, f)
                try:
                    with open(p, "rb") as fh:
                        if fh.read(4) != MACHO_MAGIC:
                            continue
                    img = Image(p)
                    for name, info in img.classes().items():
                        if name in self.classes:
                            continue
                        self.classes[name] = {"super": info["super"],
                                              "sels": set(info["methods"]) | set(info["class_methods"])}
                        self.ivars.update(info["ivars"])
                    for cls, _cat, inst, klass in img.categories():
                        cat_sels[cls].update(inst)
                        cat_sels[cls].update(klass)
                except Exception:
                    continue
        if not self.classes:
            sys.exit(f"error: no ObjC metadata found under {app}")
        # Categories on SDK classes (UIView, NSObject...) are kept under that name so
        # lookups through an external superclass still see them.
        self.external_sels = collections.defaultdict(set)
        for cls, sels in cat_sels.items():
            if cls in self.classes:
                self.classes[cls]["sels"].update(sels)
            else:
                self.external_sels[cls].update(sels)
        for name, info in self.classes.items():
            for s in info["sels"]:
                self.sel_owners[s].add(name)
        for cls, sels in self.external_sels.items():
            for s in sels:
                self.sel_owners[s].add(cls)
        self.alias = collections.defaultdict(set)
        for k in self.classes:
            m = re.match(r"^_TtC(\d+)(.*)$", k)
            if not m:
                continue
            rest = m.group(2)[int(m.group(1)):]
            m2 = re.match(r"^(\d+)(.*)$", rest)
            if m2:
                self.alias[m2.group(2)[:int(m2.group(1))]].add(k)

    def resolve(self, name):
        """Runtime class names objc_getClass/NSClassFromString(name) can return in this bundle.

        A bare name does not find a Swift class registered under its mangled name, so a
        trailing-name match is not a resolution; see swift_successors()."""
        if name in self.classes:
            return [name]
        mangled = swift_mangle(name)
        if mangled and mangled in self.classes:
            return [mangled]
        return []

    def swift_successors(self, name):
        """Swift classes whose plain name matches `name` (a likely ObjC -> Swift move)."""
        return sorted(self.alias.get(name.split(".")[-1], ()))

    def summary(self):
        return (f"{len(self.classes)} classes, {len(self.ivars)} ivars, "
                f"{len(self.sel_owners)} selectors")


class SDK:
    """Classes, ivars and selectors the iOS SDK declares, to tell UIKit from Instagram."""
    def __init__(self):
        theos = pathlib.Path(os.environ.get("THEOS", pathlib.Path.home() / "theos"))
        self.root = theos / "sdks" / "iPhoneOS14.5.sdk"
        self.classes, self.ivars, self.sels = set(), set(), set()
        if not self.root.is_dir():
            print(f"warning: {self.root} not found; UIKit/Foundation names will show as missing")
            return
        for tbd in self.root.rglob("*.tbd"):
            text = tbd.read_text(errors="replace")
            for key, dest in (("objc-classes", self.classes), ("objc-eh-types", self.classes),
                              ("objc-ivars", self.ivars)):
                for block in re.findall(key + r":\s*\[([^\]]*)\]", text):
                    for item in re.split(r"[,\s]+", block):
                        item = item.strip("'\"")
                        if not item:
                            continue
                        dest.add(item.split(".", 1)[1] if dest is self.ivars and "." in item else item)
        for hdr in (self.root / "System" / "Library").rglob("*.h"):
            self._scan_header(hdr.read_text(errors="replace"))

    def _scan_header(self, text):
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
        text = re.sub(r"\b[A-Z][A-Z0-9_]{2,}\b(\s*\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\))?", " ", text)
        for decl in re.findall(r"^\s*[-+]\s*\(.*?;", text, flags=re.M | re.S):
            body = decl
            while True:  # drop parenthesised types, innermost first
                stripped = re.sub(r"\([^()]*\)", " ", body)
                if stripped == body:
                    break
                body = stripped
            body = body.strip().lstrip("-+").strip()
            parts = re.findall(r"(\w+)\s*:", body)
            if parts:
                self.sels.add("".join(p + ":" for p in parts))
            else:
                m = re.match(r"\s*(\w+)", body)
                if m:
                    self.sels.add(m.group(1))
        for attrs, rest in re.findall(r"@property\s*(\([^)]*\))?([^;]*);", text):
            m = re.search(r"(\w+)\s*$", rest.strip())
            if not m:
                continue
            name = m.group(1)
            getter = re.search(r"getter\s*=\s*(\w+)", attrs or "")
            self.sels.add(getter.group(1) if getter else name)
            if "readonly" not in (attrs or ""):
                setter = re.search(r"setter\s*=\s*(\w+:)", attrs or "")
                self.sels.add(setter.group(1) if setter else f"set{name[0].upper()}{name[1:]}:")


# ---------------------------------------------------------------- Theta source scan

def source_files():
    for sub in ("Source", "Include"):
        for root, _dirs, files in os.walk(REPO / sub):
            for f in sorted(files):
                if f.endswith((".m", ".h", ".x", ".xm", ".mm")):
                    yield pathlib.Path(root) / f


def strip_comments(text):
    """Blank out // and /* */ comments (keeping newlines, so line numbers hold)."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"' and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def read_source(p):
    return strip_comments(p.read_text(errors="replace"))


def call_args(text, i):
    """Top-level comma-separated arguments of the call whose '(' ends just before i."""
    depth, cur, out, quote = 0, [], [], False
    while i < len(text):
        c = text[i]
        if c == '"' and text[i - 1] != "\\":
            quote = not quote
        if not quote:
            if c in "([{":
                depth += 1
            elif c in ")]}":
                if depth == 0:
                    out.append("".join(cur).strip())
                    return out
                depth -= 1
            elif c == "," and depth == 0:
                out.append("".join(cur).strip())
                cur = []
                i += 1
                continue
        cur.append(c)
        i += 1
    return out


def literal_classes(expr):
    names = re.findall(r'@?"([A-Za-z_][A-Za-z0-9_.]*)"', expr)
    names += re.findall(r"%c\(\s*([A-Za-z_]\w*)\s*\)", expr)
    names += re.findall(r"\[\s*([A-Z]\w*)\s+class\s*\]", expr)
    return names


def literal_sels(expr):
    sels = [s.replace(" ", "") for s in re.findall(r"@selector\(\s*([^)]+?)\s*\)", expr)]
    sels += re.findall(r'@?"([A-Za-z_][A-Za-z0-9_:]*)"', expr)
    return sels


def trace(text, pos, expr, extract, depth=0):
    """Literal names an argument can hold: direct literals, else follow its variable."""
    found = extract(expr)
    if found or depth > 2:
        return found
    before = text[max(0, pos - 20000):pos]
    for var in dict.fromkeys(re.findall(r"\b([A-Za-z_]\w*)\b", expr)):
        if var in TRACE_SKIP:
            continue
        hits = []
        v = re.escape(var)
        for m in re.finditer(r"\b" + v + r"\s*(?:\[\s*\w*\s*\])?\s*=(?!=)\s*(.+?);", before, flags=re.S):
            hits.append((m.start(), m.group(1)))
        for m in re.finditer(r"for\s*\([^;()]*?\b" + v + r"\s+in\s+(.+?)\)\s*(?:\{|\n)", before, flags=re.S):
            hits.append((m.start(), m.group(1)))
        if re.search(r"\b" + v + r"\s*\(", expr):  # helper function returning the value
            for m in re.finditer(r"\b" + v + r"\s*\(void\)\s*\{(.*?)\n\}", text, flags=re.S):
                hits.append((-1, m.group(1)))
        if not hits:
            continue
        _start, rhs = max(hits)
        found = trace(text, pos, rhs, extract, depth + 1)
        if found:
            return found
    return []


def theta_own_classes():
    names = set()
    for p in source_files():
        names |= set(re.findall(r"@(?:interface|implementation)\s+([A-Za-z_]\w*)\b(?!\s*\()",
                                read_source(p)))
    return names


def hook_sites():
    """[(file, line, class candidates, selector candidates, raw class arg, raw sel arg)]"""
    sites = []
    for p in source_files():
        text = read_source(p)
        for m in HOOK_CALL.finditer(text):
            args = call_args(text, m.end())
            if len(args) < 2 or args[0].startswith(("Class ", "NSArray")):
                continue  # the helper's own definition
            if p.name == "THGlobalsAndHooking.m" and args[0] in ("cls", "c") and args[1] in ("sel", "s"):
                continue  # forwarding inside the hook helpers themselves
            line = text.count("\n", 0, m.start()) + 1
            classes = trace(text, m.start(), args[0], literal_classes)
            sels = trace(text, m.start(), args[1], literal_sels)
            sites.append((p.relative_to(REPO), line, classes, sels, args[0], args[1]))
    return sites


def loose_refs():
    """Class lookups and '_ivar' strings: (kind, name) -> [file:line]."""
    refs = collections.defaultdict(list)
    for p in source_files():
        text = read_source(p)
        rel = p.relative_to(REPO)
        for pat, kind in ((r'objc_getClass\("([^"]+)"\)', "class"),
                          (r'NSClassFromString\(@"([^"]+)"\)', "class"),
                          (r'@"(_[A-Za-z][A-Za-z0-9_]+)"', "ivar")):
            for m in re.finditer(pat, text):
                refs[(kind, m.group(1))].append(f"{rel}:{text.count(chr(10), 0, m.start()) + 1}")
    return refs


# ---------------------------------------------------------------- checks

def check_pair(bundle, sdk, own, cls_name, sel):
    """(status, note) for one (class, selector) candidate."""
    if cls_name in own:
        return OK, "Theta class"
    runtime = bundle.resolve(cls_name)
    if not runtime:
        if cls_name in sdk.classes:
            ok = sel in sdk.sels or sel in bundle.external_sels.get(cls_name, ())
            return (OK, "SDK class") if ok else (SYSTEM, f"private selector on {cls_name}")
        if cls_name.startswith(SYSTEM_PREFIXES):
            return SYSTEM, "private system class"
        moved = bundle.swift_successors(cls_name)
        return CLASS_MISSING, (f"now Swift: {short(moved, 2)}" if moved else "")
    for start in runtime:
        cur, seen = start, set()
        while cur and cur not in seen:
            seen.add(cur)
            info = bundle.classes.get(cur)
            if info is None:  # reached an SDK superclass
                if sel in sdk.sels or sel in bundle.external_sels.get(cur, ()):
                    return OK, f"inherited from {cur}"
                break
            if sel in info["sels"]:
                return OK, ""
            cur = info["super"]
    return SEL_MISSING, ""


def check_site(bundle, sdk, own, classes, sels):
    if not classes or not sels:
        return UNRESOLVED, ""
    statuses = [check_pair(bundle, sdk, own, c, s) for c in classes for s in sels]
    if any(st == OK for st, _ in statuses):
        return OK, ""
    system = [n for st, n in statuses if st == SYSTEM]
    if system:
        return SYSTEM, system[0]
    if all(st == CLASS_MISSING for st, _ in statuses):
        notes = [n for _, n in statuses if n]
        return CLASS_MISSING, (notes[0] if notes else "")
    elsewhere = sorted({o for s in sels for o in bundle.sel_owners.get(s, ())})
    note = ""
    if elsewhere:
        shown = ", ".join(elsewhere[:3]) + (f" (+{len(elsewhere) - 3} more)" if len(elsewhere) > 3 else "")
        note = f"selector exists on: {shown}"
    return SEL_MISSING, note


def short(names, limit=3):
    names = list(dict.fromkeys(names))
    s = ", ".join(names[:limit])
    return s + (f" (+{len(names) - limit})" if len(names) > limit else "")


def main():
    argv = [a for a in sys.argv[1:] if a != "-v"]
    verbose = len(argv) != len(sys.argv) - 1
    if len(argv) not in (1, 2):
        sys.exit("usage: ./scripts/compat.py [-v] [<old-Instagram.app>] <Instagram.app>")

    print("indexing iOS SDK ...")
    sdk = SDK()
    bundles = []
    for app in argv:
        print(f"indexing {app} ...")
        b = Bundle(app)
        print(f"  {b.summary()}")
        bundles.append(b)
    own = theta_own_classes()
    sites = hook_sites()
    new = bundles[-1]
    old = bundles[0] if len(bundles) == 2 else None

    results = []
    for rel, line, classes, sels, raw_c, raw_s in sites:
        st, note = check_site(new, sdk, own, classes, sels)
        old_st = check_site(old, sdk, own, classes, sels)[0] if old else None
        results.append((rel, line, classes, sels, raw_c, raw_s, st, note, old_st))

    counts = collections.Counter(r[6] for r in results)
    print()
    print(f"Hook call sites: {len(results)}  " +
          "  ".join(f"{k}={counts.get(k, 0)}" for k in (OK, SEL_MISSING, CLASS_MISSING, SYSTEM, UNRESOLVED)))

    def show(title, rows):
        print()
        print("=" * 78)
        print(f"{title} ({len(rows)})")
        print("=" * 78)
        last = None
        for rel, line, classes, sels, raw_c, raw_s, st, note, old_st in rows:
            if rel != last:
                print(f"\n{rel}")
                last = rel
            cls = short(classes) or f"<{raw_c[:40]}>"
            sel = short(sels) or f"<{raw_s[:40]}>"
            tag = f" [{st}]" if st != OK else ""
            print(f"  :{line}{tag}  {cls}  {sel}")
            if note:
                print(f"         {note}")
        if not rows:
            print("  (none)")

    if old:
        show("BROKE: resolved in the old build, not in the new one",
             [r for r in results if r[8] == OK and r[6] != OK])
    else:
        show("MISSING: hooks that will not install on this build",
             [r for r in results if r[6] in (SEL_MISSING, CLASS_MISSING)])
    show("SYSTEM: private UIKit/Foundation API, cannot be checked offline",
         [r for r in results if r[6] == SYSTEM])
    show("UNRESOLVED: class or selector is computed at runtime; check by hand",
         [r for r in results if r[6] == UNRESOLVED])
    if verbose:
        show("OK", [r for r in results if r[6] == OK])

    # Loose class lookups and ivar strings, by name only.
    loose = []
    for (kind, name), where in sorted(loose_refs().items()):
        if kind == "ivar" and name.startswith("_TtC"):
            kind = "class"
        if kind == "class":
            present = (lambda b: bool(b.resolve(name)) or name in sdk.classes or name in own
                       or name.startswith(SYSTEM_PREFIXES))
        else:
            present = (lambda b: name in b.ivars or name in b.sel_owners or name in sdk.ivars
                       or name in sdk.sels)
        in_new = present(new)
        if old:
            if present(old) and not in_new:
                loose.append((kind, name, where))
        elif not in_new:
            loose.append((kind, name, where))
    print()
    print("=" * 78)
    print(f"Class lookups / ivar-or-selector strings not found by name ({len(loose)}) — lower confidence")
    print("=" * 78)
    for kind, name, where in loose:
        print(f"  [{'ivar/sel' if kind == 'ivar' else kind}] {name}  — {short(where, 2)}")
    if not loose:
        print("  (none)")

    missing = counts.get(SEL_MISSING, 0) + counts.get(CLASS_MISSING, 0)
    return 1 if (old and any(r[8] == OK and r[6] != OK for r in results)) or (not old and missing) else 0


if __name__ == "__main__":
    sys.exit(main())
