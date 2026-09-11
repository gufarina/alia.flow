#!/usr/bin/env python3
# Alia Flow - Session Search (OPP-06): FTS5 recall over past session transcripts.
#
# Two modes:
#   index           read every *.jsonl transcript, extract user/assistant text,
#                   write it into a local SQLite FTS5 table. Idempotent.
#   search "<term>" run an FTS5 MATCH; DISCOVERY output = snippet + a window of
#                   +-5 events around each hit + bookends (first/last event of
#                   that session). --scroll <id> pages more context for one hit.
#
# Stdlib only (sqlite3, json, glob, argparse). No pip. Português correto, com acentos. Arquivo salvo em UTF-8 sem BOM; o único erro é caractere corrompido.
# The DB lives in memory/_index/ which is operator data (gitignored), so the
# transcript content (which may be non-ASCII) never lands in versioned code.
#
# This is RAW text recall (recall by word). It complements the graph, which is
# concept/relation recall. Use the graph for "what relates to what"; use this
# for "where did we literally say X".

import argparse
import glob
import json
import os
import sqlite3
import sys

# Default transcript directory: the Claude Code projects folder (all projects).
# Indexing recurses, so any project's transcripts under this folder are picked up.
DEFAULT_TRANSCRIPTS = os.path.join(
    os.path.expanduser("~"),
    ".claude",
    "projects",
)

# Default DB path: memory/_index/sessions.db, relative to the repo root.
# The repo root is the parent of this script's directory (scripts/).
_SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(_SCRIPT_DIR)
DEFAULT_DB = os.path.join(_REPO_ROOT, "memory", "_index", "sessions.db")

CONTEXT_WINDOW = 5  # +- events around a hit in discovery mode


def connect(db_path):
    """Open the DB, creating the parent folder if needed."""
    parent = os.path.dirname(db_path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    conn = sqlite3.connect(db_path)
    return conn


def ensure_schema(conn):
    """Create the FTS5 table if absent.

    Only `text` is indexed/searchable; the metadata columns are UNINDEXED so
    MATCH targets the transcript text and the metadata just rides along.
    `seq` is a stable global event order used for context windows and scroll.
    """
    conn.execute(
        "CREATE VIRTUAL TABLE IF NOT EXISTS events USING fts5("
        "  event_id UNINDEXED,"   # stable id: <source_file>:<line_no>
        "  source_file UNINDEXED," # basename of the .jsonl
        "  seq UNINDEXED,"         # global order across all files (for window/scroll)
        "  line_no UNINDEXED,"     # 1-based line within the source file
        "  role UNINDEXED,"        # user | assistant
        "  text"                   # the searchable transcript text
        ")"
    )
    conn.commit()


def _flatten_content(content):
    """Pull readable text out of a message `content` field.

    Handles the two shapes seen in Claude Code JSONL:
      - a plain string (early user turns)
      - a list of blocks (text / thinking / tool_use / tool_result / ...)
    Binary noise (images, opaque tool payloads) is skipped: we only keep
    real text blocks, thinking, tool names, and string tool_result content.
    """
    parts = []
    if isinstance(content, str):
        if content.strip():
            parts.append(content)
        return parts
    if not isinstance(content, list):
        return parts
    for block in content:
        if not isinstance(block, dict):
            if isinstance(block, str) and block.strip():
                parts.append(block)
            continue
        btype = block.get("type")
        if btype in ("text", "thinking"):
            val = block.get("text") or block.get("thinking")
            if isinstance(val, str) and val.strip():
                parts.append(val)
        elif btype == "tool_use":
            name = block.get("name")
            if isinstance(name, str) and name.strip():
                parts.append("[tool_use: " + name + "]")
        elif btype == "tool_result":
            inner = block.get("content")
            if isinstance(inner, str):
                if inner.strip():
                    parts.append(inner)
            elif isinstance(inner, list):
                for sub in inner:
                    if isinstance(sub, dict) and sub.get("type") == "text":
                        t = sub.get("text")
                        if isinstance(t, str) and t.strip():
                            parts.append(t)
        # images and other binary/opaque blocks are intentionally ignored.
    return parts


def extract_events(path):
    """Yield (line_no, role, text) for each user/assistant message in a JSONL."""
    line_no = 0
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line_no += 1
            raw = raw.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
            except (ValueError, TypeError):
                continue
            if not isinstance(obj, dict):
                continue
            etype = obj.get("type")
            if etype not in ("user", "assistant"):
                continue
            message = obj.get("message")
            if not isinstance(message, dict):
                continue
            role = message.get("role") or etype
            text = "\n".join(_flatten_content(message.get("content")))
            text = text.strip()
            if not text:
                continue
            yield (line_no, role, text)


def cmd_index(args):
    """Read all transcripts and (re)build the FTS5 table. Idempotent."""
    tdir = args.transcripts
    if not os.path.isdir(tdir):
        sys.stderr.write("ERROR: transcript dir not found: " + tdir + "\n")
        return 1

    pattern = os.path.join(tdir, "**", "*.jsonl")
    files = sorted(glob.glob(pattern, recursive=True))
    if not files:
        sys.stderr.write("ERROR: no .jsonl transcripts in: " + tdir + "\n")
        return 1

    conn = connect(args.db)
    ensure_schema(conn)
    # Idempotent: clear and regrab. Stable ids mean the table never duplicates.
    conn.execute("DELETE FROM events")
    conn.commit()

    seq = 0
    file_count = 0
    event_count = 0
    for path in files:
        base = os.path.basename(path)
        file_count += 1
        rows = []
        for (line_no, role, text) in extract_events(path):
            seq += 1
            event_id = base + ":" + str(line_no)
            rows.append((event_id, base, seq, line_no, role, text))
        if rows:
            conn.executemany(
                "INSERT INTO events"
                " (event_id, source_file, seq, line_no, role, text)"
                " VALUES (?, ?, ?, ?, ?, ?)",
                rows,
            )
            event_count += len(rows)
        print("  indexed " + str(len(rows)) + " events from " + base)

    conn.commit()
    conn.close()

    print("")
    print("INDEX DONE")
    print("  files indexed:  " + str(file_count))
    print("  events indexed: " + str(event_count))
    print("  db:             " + args.db)
    return 0


def _one_line(text, width=140):
    """Collapse whitespace and clip a string for a single console line."""
    flat = " ".join(text.split())
    if len(flat) > width:
        flat = flat[: width - 3] + "..."
    return flat


def _fetch_row(conn, seq):
    cur = conn.execute(
        "SELECT seq, line_no, role, source_file, text"
        " FROM events WHERE seq = ?",
        (seq,),
    )
    return cur.fetchone()


def _print_event(row, marker=" "):
    """Print one event as: <marker> #seq [role] text..."""
    seq, line_no, role, _source, text = row
    tag = "[" + role + "]"
    print("  " + marker + " #" + str(seq) + " " + tag.ljust(11) + " " + _one_line(text))


def _bookends(conn, source_file):
    """First and last event of a session (its source file), to situate a hit."""
    first = conn.execute(
        "SELECT seq, line_no, role, source_file, text"
        " FROM events WHERE source_file = ? ORDER BY seq ASC LIMIT 1",
        (source_file,),
    ).fetchone()
    last = conn.execute(
        "SELECT seq, line_no, role, source_file, text"
        " FROM events WHERE source_file = ? ORDER BY seq DESC LIMIT 1",
        (source_file,),
    ).fetchone()
    return first, last


def _print_window(conn, source_file, center_seq, radius):
    """Print events within +-radius of center_seq, staying inside the session."""
    rows = conn.execute(
        "SELECT seq, line_no, role, source_file, text"
        " FROM events WHERE source_file = ? AND seq BETWEEN ? AND ?"
        " ORDER BY seq ASC",
        (source_file, center_seq - radius, center_seq + radius),
    ).fetchall()
    for row in rows:
        marker = ">>" if row[0] == center_seq else "  "
        _print_event(row, marker)


def cmd_search(args):
    """Run an FTS5 MATCH and print discovery output (or scroll one hit)."""
    if not os.path.isfile(args.db):
        sys.stderr.write(
            "ERROR: index db not found: " + args.db
            + "\n  Run 'index' first.\n"
        )
        return 1

    conn = connect(args.db)

    # Scroll mode: widen the context window around a single known event id (seq).
    if args.scroll is not None:
        center = _fetch_row(conn, args.scroll)
        if center is None:
            sys.stderr.write("ERROR: no event with id #" + str(args.scroll) + "\n")
            conn.close()
            return 1
        radius = args.radius if args.radius is not None else CONTEXT_WINDOW * 2
        source_file = center[3]
        print("SCROLL around #" + str(args.scroll)
              + " in " + source_file + " (radius " + str(radius) + ")")
        print("")
        _print_window(conn, source_file, args.scroll, radius)
        conn.close()
        return 0

    if not args.term:
        sys.stderr.write("ERROR: provide a search term, e.g. search \"loops\"\n")
        conn.close()
        return 1

    try:
        hits = conn.execute(
            "SELECT seq, line_no, role, source_file,"
            " snippet(events, 5, '[', ']', ' ... ', 12) AS snip"
            " FROM events WHERE events MATCH ?"
            " ORDER BY rank LIMIT ?",
            (args.term, args.limit),
        ).fetchall()
    except sqlite3.OperationalError as exc:
        sys.stderr.write("ERROR: bad FTS5 query: " + str(exc) + "\n")
        conn.close()
        return 1

    if not hits:
        print("No hits for: " + args.term)
        conn.close()
        return 0

    print("SEARCH \"" + args.term + "\" - " + str(len(hits)) + " hit(s)")
    print("(discovery: snippet + context window +-" + str(CONTEXT_WINDOW)
          + " + bookends; scroll a hit with: --scroll <id>)")

    for (seq, line_no, role, source_file, snip) in hits:
        print("")
        print("=" * 72)
        print("HIT #" + str(seq) + " [" + role + "] in " + source_file)
        print("  snippet: " + _one_line(snip, 160))

        first, last = _bookends(conn, source_file)
        if first is not None:
            print("  session opens:")
            _print_event(first, "..")
        print("  context window:")
        _print_window(conn, source_file, seq, CONTEXT_WINDOW)
        if last is not None:
            print("  session closes:")
            _print_event(last, "..")
        print("  scroll more: python scripts/session-search.py search"
              " --scroll " + str(seq))

    conn.close()
    return 0


def build_parser():
    parser = argparse.ArgumentParser(
        prog="session-search",
        description="FTS5 recall over past Alia Flow session transcripts.",
    )
    sub = parser.add_subparsers(dest="mode")

    p_index = sub.add_parser("index", help="(re)build the FTS5 index")
    p_index.add_argument("--transcripts", default=DEFAULT_TRANSCRIPTS,
                         help="dir with *.jsonl transcripts")
    p_index.add_argument("--db", default=DEFAULT_DB, help="sqlite db path")
    p_index.set_defaults(func=cmd_index)

    p_search = sub.add_parser("search", help="search the index (discovery/scroll)")
    p_search.add_argument("term", nargs="?", help="FTS5 query, e.g. \"loops\"")
    p_search.add_argument("--db", default=DEFAULT_DB, help="sqlite db path")
    p_search.add_argument("--limit", type=int, default=5, help="max hits")
    p_search.add_argument("--scroll", type=int, default=None,
                          help="page more context around event id <seq>")
    p_search.add_argument("--radius", type=int, default=None,
                          help="scroll window radius (default 10)")
    p_search.set_defaults(func=cmd_search)

    return parser


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv)
    if not getattr(args, "mode", None):
        parser.print_help()
        return 1
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
