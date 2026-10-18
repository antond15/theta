#!/usr/bin/env python3
"""Dump ObjC classes (ivars, instance/class methods, superclass) and categories from an arm64 Mach-O.

    ./scripts/objcdump.py <Mach-O> [out.json]

Walks __objc_classlist -> class_t -> class_ro_t and __objc_catlist -> category_t.
Pointers are decoded for plain rebases and DYLD_CHAINED_PTR_64 / _64_OFFSET; binds
(e.g. a superclass that lives in UIKit) are resolved to their imported symbol name
through LC_DYLD_CHAINED_FIXUPS.

Based on scripts/objcdump.py by Nico Jan (github.com/nicojan/theta, branch
local-build-notes, commit 5fb3bd4); extended with class methods, categories,
superclasses and dylib (__TEXT at vmaddr 0) support.
"""
import json
import struct
import sys

MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19
LC_DYLD_CHAINED_FIXUPS = 0x80000034
CLASS_PREFIX = "_OBJC_CLASS_$_"
METACLASS_PREFIX = "_OBJC_METACLASS_$_"


def u64(b, o): return struct.unpack_from("<Q", b, o)[0]
def u32(b, o): return struct.unpack_from("<I", b, o)[0]


class Image:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        assert u32(self.data, 0) == MH_MAGIC_64, "not arm64 Mach-O"
        self.segs = []       # (vmaddr, vmsize, fileoff)
        self.base = None     # vmaddr of __TEXT; 0 for dylibs and frameworks
        self.sects = {}      # (seg, sect) -> (addr, size, offset)
        self.imports = []    # chained-fixup import ordinal -> symbol name
        ncmds = u32(self.data, 16)
        off = 32
        for _ in range(ncmds):
            cmd, cmdsize = u32(self.data, off), u32(self.data, off + 4)
            if cmd == LC_SEGMENT_64:
                segname = self.data[off+8:off+24].rstrip(b"\0").decode()
                vmaddr, vmsize, fileoff = u64(self.data, off+24), u64(self.data, off+32), u64(self.data, off+40)
                if segname != "__PAGEZERO":
                    if segname == "__TEXT":
                        self.base = vmaddr
                    self.segs.append((vmaddr, vmsize, fileoff))
                nsects = u32(self.data, off+64)
                so = off + 72
                for _s in range(nsects):
                    sn = self.data[so:so+16].rstrip(b"\0").decode()
                    sg = self.data[so+16:so+32].rstrip(b"\0").decode()
                    self.sects[(sg, sn)] = (u64(self.data, so+32), u64(self.data, so+40), u32(self.data, so+48))
                    so += 80
            elif cmd == LC_DYLD_CHAINED_FIXUPS:
                self._read_imports(u32(self.data, off + 8))
            off += cmdsize
        if self.base is None:
            self.base = min(v for v, _, _ in self.segs)

    def _read_imports(self, fo):
        _ver, _starts, imports_off, symbols_off, count, fmt, _symfmt = struct.unpack_from("<7I", self.data, fo)
        io, so = fo + imports_off, fo + symbols_off
        for i in range(count):
            if fmt == 1:      # DYLD_CHAINED_IMPORT
                name_off = u32(self.data, io + i * 4) >> 9
            elif fmt == 2:    # DYLD_CHAINED_IMPORT_ADDEND
                name_off = u32(self.data, io + i * 8) >> 9
            elif fmt == 3:    # DYLD_CHAINED_IMPORT_ADDEND64
                name_off = u32(self.data, io + i * 16 + 4)
            else:
                return
            end = self.data.find(b"\0", so + name_off)
            self.imports.append(self.data[so + name_off:end].decode(errors="replace"))

    def off_for(self, vmaddr):
        for v, sz, fo in self.segs:
            if v <= vmaddr < v + sz:
                return fo + (vmaddr - v)
        return None

    def mapped(self, vmaddr):
        return any(v <= vmaddr < v + sz for v, sz, _ in self.segs)

    def raw(self, vmaddr):
        o = self.off_for(vmaddr)
        return None if o is None else u64(self.data, o)

    def ptr(self, vmaddr):
        """Read a pointer, decoding chained-fixup rebase encodings. Binds read as 0."""
        raw = self.raw(vmaddr)
        if not raw or raw >> 63:
            return 0
        if self.mapped(raw):
            return raw
        # DYLD_CHAINED_PTR_64 rebase: target lives in the low 36 bits, either as a full
        # unslid vmaddr or as an offset from the image base.
        target = raw & 0xFFFFFFFFF
        if self.mapped(target):
            return target
        if self.mapped(self.base + target):
            return self.base + target
        return 0

    def bind_name(self, vmaddr):
        """Imported symbol a bound pointer refers to, or None."""
        raw = self.raw(vmaddr)
        if not raw or not raw >> 63:
            return None
        ordinal = raw & 0xFFFFFF
        return self.imports[ordinal] if ordinal < len(self.imports) else None

    def cstr(self, vmaddr):
        o = self.off_for(vmaddr)
        if o is None: return None
        end = self.data.find(b"\0", o)
        if end < 0 or end - o > 512: return None
        try: return self.data[o:end].decode()
        except UnicodeDecodeError: return None

    def section(self, name):
        for seg in ("__DATA_CONST", "__DATA"):
            if (seg, name) in self.sects:
                return self.sects[(seg, name)]
        return None

    def method_list(self, mp):
        sels = []
        if not mp: return sels
        o = self.off_for(mp)
        if o is None: return sels
        entsize, count = u32(self.data, o), u32(self.data, o + 4)
        small = bool(entsize & 0x80000000)
        esz = entsize & 0xFFFC
        if esz not in (12, 24) or count >= 8192: return sels
        for j in range(count):
            eo = o + 8 + j * esz
            ea = mp + 8 + j * esz
            if small:
                rel = struct.unpack_from("<i", self.data, eo)[0]
                n = self.cstr(self.ptr(ea + rel))
            else:
                n = self.cstr(self.ptr(ea))
            if n: sels.append(n)
        return sels

    def ro_name(self, cls):
        ro = self.ptr(cls + 32) & ~0x7
        return self.cstr(self.ptr(ro + 24)) if ro else None

    def class_ref_name(self, vmaddr):
        """Name of the class a class_t pointer field refers to (internal or imported)."""
        target = self.ptr(vmaddr)
        if target:
            return self.ro_name(target)
        sym = self.bind_name(vmaddr)
        if sym:
            for prefix in (CLASS_PREFIX, METACLASS_PREFIX):
                if sym.startswith(prefix):
                    return sym[len(prefix):]
        return None

    def read_class(self, cls):
        ro = self.ptr(cls + 32) & ~0x7
        if not ro: return None
        name = self.cstr(self.ptr(ro + 24))
        if not name: return None
        ivars = []
        iv = self.ptr(ro + 48)
        if iv:
            o = self.off_for(iv)
            if o is not None:
                entsize, count = u32(self.data, o), u32(self.data, o + 4)
                if entsize == 32 and count < 4096:
                    for j in range(count):
                        n = self.cstr(self.ptr(iv + 8 + j * 32 + 8))
                        if n: ivars.append(n)
        methods = self.method_list(self.ptr(ro + 32))
        class_methods = []
        meta = self.ptr(cls)
        if meta:
            mro = self.ptr(meta + 32) & ~0x7
            if mro:
                class_methods = self.method_list(self.ptr(mro + 32))
        return name, {
            "super": self.class_ref_name(cls + 8),
            "ivars": ivars,
            "methods": methods,
            "class_methods": class_methods,
        }

    def classes(self):
        out = {}
        sect = self.section("__objc_classlist")
        if not sect: return out
        addr, size, _ = sect
        for i in range(size // 8):
            cls = self.ptr(addr + i * 8)
            if not cls: continue
            info = self.read_class(cls)
            if info: out[info[0]] = info[1]
        return out

    def categories(self):
        """[(class name, category name, instance methods, class methods)]"""
        out = []
        sect = self.section("__objc_catlist")
        if not sect: return out
        addr, size, _ = sect
        for i in range(size // 8):
            cat = self.ptr(addr + i * 8)
            if not cat: continue
            cls = self.class_ref_name(cat + 8)
            if not cls: continue
            out.append((cls, self.cstr(self.ptr(cat)) or "",
                        self.method_list(self.ptr(cat + 16)),
                        self.method_list(self.ptr(cat + 24))))
        return out


if __name__ == "__main__":
    img = Image(sys.argv[1])
    cls = img.classes()
    cats = img.categories()
    if len(sys.argv) > 2:
        json.dump({"classes": cls, "categories": cats}, open(sys.argv[2], "w"))
    print(f"{sys.argv[1]}: {len(cls)} classes, {len(cats)} categories, "
          f"{sum(len(v['ivars']) for v in cls.values())} ivars, "
          f"{sum(len(v['methods']) + len(v['class_methods']) for v in cls.values())} methods")
