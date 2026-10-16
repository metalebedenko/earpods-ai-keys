#!/usr/bin/python3
"""Original, bounded offline layout writer for this project's Finder template.

Uses only Python's standard library. Does not mount images, run Finder, create
aliases or touch app bundles. Supports the observed Bud1 / one-leaf layout only;
unexpected allocator/tree shapes fail before output. Output is always a new file.
"""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import sys


MAX_FILE = 8 * 1024 * 1024
POOL = 1 << 31
LEAF_POSITION = 8192
LEAF_SIZE = 4096


def require(condition, message):
    if not condition:
        raise ValueError(message)


def uint(data, offset):
    require(0 <= offset <= len(data) - 4, "truncated integer")
    return struct.unpack_from(">I", data, offset)[0]


def word(value):
    return struct.pack(">I", value)


def encoded_record(name, code, kind, payload):
    name_bytes = name.encode("utf-16be")
    return word(len(name_bytes) // 2) + name_bytes + code.encode("ascii") + kind.encode("ascii") + payload


def blob_record(name, code, payload):
    return encoded_record(name, code, "blob", word(len(payload)) + payload)


class Template:
    def __init__(self, data):
        require(36 <= len(data) <= MAX_FILE, "unexpected file size")
        require(data[:8] == b"\0\0\0\1Bud1", "not a version-1 Bud1 file")
        self.data = data
        allocator, size, duplicate = struct.unpack_from(">III", data, 8)
        require((allocator, size, duplicate) == (4096, 2048, 4096), "unsupported allocator location")
        base = allocator + 4
        require(base + size <= len(data), "truncated allocator")
        require(uint(data, base) == 3 and uint(data, base + 4) == 0, "unsupported allocation table")
        self.addresses = [uint(data, base + 8 + 4 * i) for i in range(3)]
        require(self.addresses[:2] == [0x100B, 0x45], "unsupported allocator/superblock allocation")
        toc = base + 8 + 4 * 256
        require(uint(data, toc) == 1 and data[toc + 4:toc + 9] == b"\4DSDB" and uint(data, toc + 9) == 1,
                "unsupported allocator directory")
        self.free_lists = []
        cursor = toc + 13
        for exponent in range(32):
            count = uint(data, cursor); cursor += 4
            require(count <= 128 and cursor + 4 * count <= base + size, "invalid free-list size")
            self.free_lists.append([uint(data, cursor + 4 * i) for i in range(count)])
            cursor += 4 * count
        self.superblock = self.block(1)
        root, levels, count, nodes, page_size = struct.unpack_from(">IIIII", self.superblock)
        require((root, levels, nodes, page_size) == (2, 0, 1, 4096), "only the observed single-leaf tree is supported")
        leaf = self.block(root)
        require(uint(leaf, 0) == 0 and uint(leaf, 4) == count and count <= 64, "invalid leaf header")
        self.records = {}
        cursor = 8
        for _ in range(count):
            start = cursor
            chars = uint(leaf, cursor); cursor += 4
            require(chars <= 1024 and cursor + 2 * chars + 8 <= len(leaf), "invalid record name")
            name = leaf[cursor:cursor + chars * 2].decode("utf-16be"); cursor += chars * 2
            code = leaf[cursor:cursor + 4].decode("ascii"); cursor += 4
            kind = leaf[cursor:cursor + 4].decode("ascii"); cursor += 4
            value_start = cursor
            if kind == "bool":
                cursor += 1
            elif kind in ("long", "shor", "type"):
                cursor += 4
            elif kind in ("comp", "dutc"):
                cursor += 8
            elif kind in ("blob", "ustr"):
                length = uint(leaf, cursor); cursor += 4
                cursor += length * (2 if kind == "ustr" else 1)
            else:
                raise ValueError("unsupported record kind: " + repr(kind))
            require(cursor <= len(leaf), "truncated record payload")
            key = (name, code)
            require(key not in self.records, "duplicate record key")
            self.records[key] = {"kind": kind, "payload": leaf[value_start:cursor], "raw": leaf[start:cursor]}
        require(not any(leaf[cursor:]), "nonzero unparsed leaf bytes")
        self.used_leaf_bytes = cursor
        self.validate_allocation()

    def block(self, index):
        address = self.addresses[index]
        exponent = address & 31
        position = address & ~31
        require(5 <= exponent <= 20 and position % (1 << exponent) == 0, "invalid block allocation")
        start, end = position + 4, position + 4 + (1 << exponent)
        require(end <= len(self.data), "allocated block beyond file")
        return self.data[start:end]

    def validate_allocation(self):
        occupied = [(0, 32)]
        for address in self.addresses:
            position, length = address & ~31, 1 << (address & 31)
            occupied.append((position, position + length))
        spans = list(occupied)
        for exponent, offsets in enumerate(self.free_lists):
            for position in offsets:
                length = 1 << exponent
                require(position % length == 0 and position + length <= POOL, "invalid free block")
                spans.append((position, position + length))
        cursor = 0
        for start, end in sorted(spans):
            require(start == cursor and end > start, "allocator gap or overlapping blocks")
            cursor = end
        require(cursor == POOL, "allocator does not cover expected address pool")


def free_lists(occupied):
    result = [[] for _ in range(32)]
    cursor = 0
    for start, end in sorted(occupied) + [(POOL, POOL)]:
        require(cursor <= start <= end <= POOL, "overlapping output allocations")
        while cursor < start:
            exponent = min((start - cursor).bit_length() - 1,
                           (cursor & -cursor).bit_length() - 1 if cursor else 31)
            result[exponent].append(cursor)
            cursor += 1 << exponent
        cursor = end
    return result


def describe(template):
    records = []
    for (name, code), record in template.records.items():
        kind, payload = record["kind"], record["payload"]
        info = {"name": name, "code": code, "type": kind}
        if kind == "blob":
            value = payload[4:]
            info["bytes"] = len(value)
            if code == "Iloc" and len(value) == 16:
                info["xy"] = list(struct.unpack_from(">II", value))
            elif value.startswith(b"bplist00"):
                def safe(obj):
                    if isinstance(obj, bytes):
                        return {"bytes": len(obj), "sha256": hashlib.sha256(obj).hexdigest()}
                    if isinstance(obj, dict):
                        return {key: safe(item) for key, item in obj.items()}
                    if isinstance(obj, list):
                        return [safe(item) for item in obj]
                    return obj
                info["plist"] = safe(plistlib.loads(value))
        elif kind in ("long", "shor"):
            info["value"] = uint(payload, 0)
        elif kind == "type":
            info["value"] = payload.decode("ascii")
        records.append(info)
    return {"leaf_bytes_used": template.used_leaf_bytes, "records": records}


def build(template, args):
    records = {key: record["raw"] for key, record in template.records.items()}
    old_bwsp = template.records.get((".", "bwsp"))
    require(old_bwsp is not None and old_bwsp["kind"] == "blob", "native bwsp template is required")
    bwsp = plistlib.loads(old_bwsp["payload"][4:])
    require(isinstance(bwsp, dict), "bwsp is not a dictionary")
    bwsp.update(ShowStatusBar=False, ShowToolbar=False, ShowTabView=False,
                ContainerShowSidebar=False, ShowSidebar=False,
                WindowBounds="{{%d, %d}, {%d, %d}}" % (args.window_x, args.window_y, args.width, args.height))
    records[(".", "bwsp")] = blob_record(".", "bwsp", plistlib.dumps(bwsp, fmt=plistlib.FMT_BINARY))
    alias = args.background_alias.read_bytes()
    require(1 <= len(alias) <= 2048, "background alias must be 1..2048 bytes")
    icvp = dict(viewOptionsVersion=1, backgroundType=2, backgroundImageAlias=alias,
                backgroundColorRed=1.0, backgroundColorGreen=1.0, backgroundColorBlue=1.0,
                iconSize=float(args.icon_size), textSize=13.0, gridSpacing=100.0,
                gridOffsetX=0.0, gridOffsetY=0.0, scrollPositionX=0.0, scrollPositionY=0.0,
                showIconPreview=False, showItemInfo=False, labelOnBottom=True, arrangeBy="none")
    records[(".", "icvp")] = blob_record(".", "icvp", plistlib.dumps(icvp, fmt=plistlib.FMT_BINARY))
    records[(".", "vstl")] = encoded_record(".", "vstl", "type", b"icnv")
    positions = {args.app_name: (args.app_x, args.app_y), "Applications": (args.applications_x, args.applications_y)}
    # Finder generated this localized key in the author's Russian environment.
    # Retain it at the same location; the physical Applications key stays portable.
    if ("Программы", "Iloc") in records:
        positions["Программы"] = positions["Applications"]
    for name, (x, y) in positions.items():
        records[(name, "Iloc")] = blob_record(name, "Iloc", struct.pack(">II", x, y) + b"\xff\xff\xff\xff\xff\xff\0\0")
    ordered = [records[key] for key in sorted(records, key=lambda key: (key[0].casefold(), key[1]))]
    leaf = word(0) + word(len(ordered)) + b"".join(ordered)
    require(len(leaf) <= LEAF_SIZE, "layout exceeds the supported 4096-byte single leaf")
    allocator = word(3) + word(0) + word(0x100B) + word(0x45) + word(LEAF_POSITION | 12) + bytes(4 * 253)
    allocator += word(1) + b"\4DSDB" + word(1)
    for offsets in free_lists([(0, 32), (64, 96), (4096, 6144), (LEAF_POSITION, LEAF_POSITION + LEAF_SIZE)]):
        allocator += word(len(offsets)) + b"".join(word(offset) for offset in offsets)
    require(len(allocator) <= 2048, "allocator exceeds native template capacity")
    output = bytearray(LEAF_POSITION + LEAF_SIZE + 4)
    output[:36] = template.data[:36]
    output[68:100] = template.superblock
    struct.pack_into(">IIIII", output, 68, 2, 0, len(ordered), 1, 4096)
    output[4100:4100 + len(allocator)] = allocator
    output[LEAF_POSITION + 4:LEAF_POSITION + 4 + len(leaf)] = leaf
    checked = Template(bytes(output))
    require({key: value["raw"] for key, value in checked.records.items()} == records, "output roundtrip differs")
    return bytes(output), checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect"); inspect.add_argument("input", type=Path)
    write = commands.add_parser("write")
    write.add_argument("template", type=Path)
    write.add_argument("background_alias", type=Path)
    write.add_argument("output", type=Path)
    write.add_argument("--app-name", default="EarPods AI Keys.app")
    for name, default in [("width", 720), ("height", 478), ("window-x", 240), ("window-y", 180),
                          ("icon-size", 128), ("app-x", 190), ("app-y", 245),
                          ("applications-x", 530), ("applications-y", 245)]:
        write.add_argument("--" + name, type=int, default=default)
    argv = sys.argv[1:]
    if argv and argv[0] not in ("inspect", "write", "-h", "--help"):
        argv.insert(0, "write")
    args = parser.parse_args(argv)
    if args.command == "inspect":
        result = describe(Template(args.input.read_bytes()))
    else:
        output = args.output.resolve()
        require(not output.is_relative_to(Path("/Volumes")), "output must be an offline file, outside /Volumes")
        require(not any(part.endswith(".app") for part in output.parts), "output must be outside app bundles")
        require(output != args.template.resolve(), "output must differ from the template")
        for name in ("width", "height", "window_x", "window_y", "icon_size", "app_x", "app_y", "applications_x", "applications_y"):
            require(0 <= getattr(args, name) <= 4096, "layout values must be in 0..4096")
        data, checked = build(Template(args.template.read_bytes()), args)
        with output.open("xb") as handle:
            handle.write(data)
        require(output.read_bytes() == data, "written bytes differ")
        result = describe(checked)
        result["output_bytes"] = len(data)
        result["output_sha256"] = hashlib.sha256(data).hexdigest()
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, UnicodeError, struct.error, plistlib.InvalidFileException) as error:
        raise SystemExit("Layout refused: " + str(error))
