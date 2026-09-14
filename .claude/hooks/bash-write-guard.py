#!/usr/bin/env python3
"""bash-write-guard -- a PreToolUse hook on Bash for a repository's dispatch envelope.

Why it exists. A headless coding session runs under the repository's committed
`.claude/settings.json`, whose allow list pre-approves interpreters (`python3:*`,
`node:*`, `uv run:*`, ...) and readers (`cat:*`, `sed -n:*`, ...). A permission rule
matches the tool call as written, never what the process goes on to do, so a session
that is refused `echo x > docs/report.md` can write the identical file through
`python3 - <<'EOF' ... open(path, "w") ... EOF`, and on 2026-09-05 one did. A write the
envelope cannot see is a write the work order's Edit-or-Write rule cannot enforce, and
one the transcript never records as a file change. This hook closes the plain routes: it
reads the Bash command's text and refuses it when the text opens a file for writing,
copies, moves or deletes a file, edits one in place, or redirects output into one. The
session is told to use the Edit or Write tool instead, which the transcript records and
the envelope's deny rules govern. The same file is committed in every repository the
Build Dispatcher dispatches into; keep the copies identical.

What it refuses (the command text, nothing else):
  * a shell redirection `>` or `>>` into anything but /dev/null, /dev/stdout, /dev/stderr
    or a file-descriptor duplicate (`2>&1`);
  * the write commands `tee cp mv rsync install dd truncate ln rm rmdir unlink shred`
    as a command word -- `git mv` and `git rm` are git's own, tracked, and allowed;
  * `sed`/`perl` with an in-place flag, `find` with `-delete` or `-exec`, `curl`/`wget`
    with an output flag;
  * a shell spawned from a string (`sh -c '...'`, `eval`, `xargs`), whose string is
    checked by the same rules;
  * inside any interpreter invocation (`python3`, a venv's `python`, `uv run`, `node`,
    `npx`, `pytest` and the like) and any heredoc body: `open(` with a write mode
    (`w`, `a`, `x`, `+`), `os.open` with a write flag, pathlib `write_text`/`write_bytes`,
    `shutil.copy*`/`move`/`rmtree`, `os.rename`/`replace`/`remove`/`unlink`,
    `subprocess`/`os.system`/`os.popen`/`os.exec*`, and Node's `writeFile*`,
    `appendFile*`, `copyFile*`, `rename*`, `child_process`.

What it leaves alone: every read, the test suite however it is run, `git add`,
`git commit -m ...` (a commit message is never scanned, so prose may mention
`open(path, "w")` or `tee`), `git push origin main`, and a tool that writes its own
output (`npm install`, `osacompile -o`, `sips --out`, a script run as a file): the guard
reads the command's text, not what the program it names does. A command whose quoting
the tokenizer cannot parse falls back to a coarser whole-text scan.

Posture: it decides on the command text alone, it refuses through the hook protocol's
`permissionDecision: deny` with a reason the session can act on, and it fails open --
any error inside the guard allows the call, and the settings entry appends `|| exit 0`
so a missing interpreter allows too. It is a guard against the plain forms, not a
boundary against intent: an obfuscated call passes it. `--self-test` runs the fixture
table below and exits non-zero on any miss, which is how the guard is proven before it
is relied on.
"""
import json
import os
import re
import shlex
import sys

WRITE_CMDS = {"tee", "cp", "mv", "rsync", "install", "dd", "truncate", "ln",
              "rm", "rmdir", "unlink", "shred"}
INPLACE_CMDS = {"sed", "perl"}
SHELL_CMDS = {"sh", "bash", "zsh", "dash", "ksh"}
INTERPRETERS = {"python", "python3", "node", "nodejs", "deno", "bun", "ruby", "perl",
                "php", "uv", "npx", "npm", "pytest", "tsx", "ts-node"}
PREFIX_WORDS = {"env", "sudo", "nohup", "time", "command", "exec", "builtin", "nice",
                "caffeinate", "stdbuf"}
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;"}
NULL_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr"}

MODE_LITERAL = re.compile(r"""['"]([rwaxbtU+]{1,4})['"]""")
MODE_KWARG = re.compile(r"""mode\s*=\s*['"]([^'"]*)['"]""")
OPEN_CALL = re.compile(r"(?<![\w.])open\s*\(")
INTERP_FORMS = [
    (re.compile(r"\bos\.open\s*\([^)]*O_(WRONLY|RDWR|CREAT|APPEND|TRUNC)"), "os.open with a write flag"),
    (re.compile(r"\.write_(text|bytes)\s*\("), "pathlib write_text/write_bytes"),
    (re.compile(r"\bshutil\.(copy\w*|move|rmtree)\s*\("), "shutil copy/move/rmtree"),
    (re.compile(r"\bos\.(rename|replace|remove|unlink|renames)\s*\("), "os rename/replace/remove/unlink"),
    (re.compile(r"\b(subprocess\.|os\.system\s*\(|os\.popen\s*\(|os\.exec\w*\s*\()"), "a shell spawned from inside the interpreter"),
    (re.compile(r"\b(writeFile|appendFile|copyFile|rename|rm|unlink|mkdir)(Sync)?\s*\("), "a Node file write"),
    (re.compile(r"child_process"), "a shell spawned from inside Node"),
]


def deny(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "dispatch envelope write guard: refused -- " + reason + ". A file written from "
                "the shell is a write the transcript does not record and the envelope cannot "
                "see; write it with the Edit or Write tool instead. Reads, the test suite, "
                "`git commit` and `git push origin main` are unaffected."
            ),
        }
    }))
    sys.exit(0)


def open_write_mode(text):
    """The mode literal of an `open(` call that opens for writing, or None."""
    for m in OPEN_CALL.finditer(text):
        depth, i, start = 0, m.end() - 1, m.end() - 1
        while i < len(text) and i < start + 400:
            if text[i] == "(":
                depth += 1
            elif text[i] == ")":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        args = text[start:i + 1]
        for lit in MODE_LITERAL.findall(args):
            if set(lit) & set("wax+"):
                return lit
        for kw in MODE_KWARG.findall(args):
            if set(kw) & set("wax+"):
                return kw
    return None


def interpreter_reason(text):
    mode = open_write_mode(text)
    if mode is not None:
        return "`open(` with mode %r" % mode
    for rx, what in INTERP_FORMS:
        if rx.search(text):
            return what
    return None


def tokens_of(command):
    lex = shlex.shlex(command, posix=False, punctuation_chars=True)
    lex.whitespace_split = True
    return list(lex)


def simple_commands(toks):
    """Split a token list into simple commands on the shell's separators."""
    out, cur = [], []
    for t in toks:
        if t in SEPARATORS or all(c in ";&|()" for c in t):
            if cur:
                out.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        out.append(cur)
    return out


def unquote(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
        return tok[1:-1]
    return tok


def command_word(cmd):
    i = 0
    while i < len(cmd):
        w = unquote(cmd[i])
        if w in PREFIX_WORDS or re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            i += 1
            continue
        return w, i
    return "", len(cmd)


def is_interpreter(word):
    base = os.path.basename(word)
    return base in INTERPRETERS or re.match(r"^python\d(\.\d+)?$", base) is not None


def redirect_reason(cmd):
    for i, t in enumerate(cmd):
        if ">" not in t or not all(c in "<>&|0123456789" for c in t):
            continue
        nxt = unquote(cmd[i + 1]) if i + 1 < len(cmd) else ""
        if t.endswith(">&") or t.endswith(">>&"):
            if re.fullmatch(r"\d+|-", nxt):
                continue                      # 2>&1, a descriptor duplicate
            return "the redirection `%s %s`" % (t, nxt)
        if nxt in NULL_TARGETS or nxt.startswith("/dev/fd/") or re.fullmatch(r"&\d+", nxt):
            continue
        return "the redirection `%s %s`" % (t, nxt)
    return None


def check_tokens(toks, raw, depth=0):
    if depth > 3:
        return None
    scan_raw = False
    for cmd in simple_commands(toks):
        word, at = command_word(cmd)
        rest = cmd[at + 1:]
        if word == "git" and rest and unquote(rest[0]) in {"commit", "tag", "notes", "merge"}:
            # git's own writes, and a message never scanned: a heredoc message runs to the
            # end of the command, and its prose may hold `<scope>/x`, `tee` or `rm`.
            if any(unquote(a).startswith("<<") for a in rest):
                break
            continue
        r = redirect_reason(cmd)
        if r:
            return r
        if word in WRITE_CMDS:
            return "`%s`, which writes, copies, moves or deletes a file" % word
        if word in INPLACE_CMDS and any(re.match(r"^(-[a-zA-Z]*i|--in-place)", unquote(a)) for a in rest):
            return "`%s` with an in-place flag" % word
        if word == "find" and any(unquote(a) in {"-delete", "-exec", "-execdir", "-ok", "-okdir"} for a in rest):
            return "`find` with a deleting or executing action"
        if word in {"curl", "wget"} and any(re.match(r"^-(o|O)|^--output|^--remote-name", unquote(a)) for a in rest):
            return "`%s` writing its output to a file" % word
        if word in SHELL_CMDS | {"eval", "xargs"}:
            inner = " ".join(unquote(a) for a in rest if unquote(a) not in {"-c", "-lc", "-e", "-x"})
            try:
                r = check_tokens(tokens_of(inner), inner, depth + 1) if inner else None
            except ValueError:
                r = check_raw(inner)
            if r:
                return r + " (inside `%s`)" % word
        if is_interpreter(word) or any(unquote(a).startswith("<<") for a in rest):
            scan_raw = True
    # An interpreter's program and a heredoc's body are scanned as text: the tokenizer
    # splits a Python body on its parentheses, so the forms are read off the raw command.
    return interpreter_reason(raw) if scan_raw else None


def check_raw(command):
    """Coarse whole-text fallback for a command the tokenizer cannot parse."""
    if re.match(r"^\s*git\s+(commit|tag|notes|merge)\b", command):
        return None                           # a commit message's prose is never scanned
    if re.search(r"(?<![-<>&|])>{1,2}(?!&)\s*(?!/dev/null|/dev/stdout|/dev/stderr)\S", command):
        return "a redirection into a file"
    for w in WRITE_CMDS:
        if re.search(r"(^|[\s;|&(])" + re.escape(w) + r"(\s|$)", command) and not re.search(r"\bgit\s+" + w + r"\b", command):
            return "`%s`, which writes, copies, moves or deletes a file" % w
    return interpreter_reason(command)


HEREDOC_MSG = re.compile(r"""(-m|--message)\s+"\$\(\s*cat\s+<<-?'?(\w+)'?\n.*?\n\2\s*\)"\s*""", re.S)
QUOTED_MSG = re.compile(r"""(-m|--message)(=|\s+)("(?:[^"\\]|\\.)*"|'[^']*')""", re.S)


def strip_messages(command):
    """A git commit message is prose and never scanned: blank the -m argument."""
    command = HEREDOC_MSG.sub(r"\1 MESSAGE ", command)
    return QUOTED_MSG.sub(r"\1 MESSAGE", command)


def reason_for(command):
    stripped = strip_messages(command)
    try:
        toks = tokens_of(command)
    except ValueError:
        try:
            toks = tokens_of(stripped)
        except ValueError:
            return check_raw(stripped)
    return check_tokens(toks, stripped)


FIXTURES = [
    # (command, refused?)
    ("""python3 -c "open('docs/hook-probe.txt', 'w').write('x')" """, True),
    ("""python3 - <<'EOF'\nfrom pathlib import Path\nwith open("docs/reviews/x.md", "w") as f:\n    f.write("hi")\nEOF""", True),
    ("""python3 -c "open('kb.py', mode='a')" """, True),
    ("""python3 -c "open('kb.py', 'r+')" """, True),
    ("""python3 -c "from pathlib import Path; Path('x').write_text('y')" """, True),
    ("""python3 -c "import shutil; shutil.copy('a', 'b')" """, True),
    ("""python3 -c "import subprocess; subprocess.run(['tee', 'x'])" """, True),
    ("""python3 -c "import os; os.system('echo x > y')" """, True),
    ("""node -e "require('fs').writeFileSync('x', 'y')" """, True),
    ("""uv run python -c "open('x', 'w')" """, True),
    (""".venv/bin/python -c "open('x', 'w')" """, True),
    ("""/Users/me/repo/.venv/bin/python -c "open('x', 'w')" """, True),
    ("""npx tsx -e "require('fs').writeFileSync('x', 'y')" """, True),
    ("echo x | tee docs/hook-probe.txt", True),
    ("cat kb.py > copy.py", True),
    ("cat kb.py >> copy.py", True),
    ("echo x 2> err.txt", True),
    ("cp kb.py kb2.py", True),
    ("mv kb.py kb2.py", True),
    ("rm -rf __pycache__", True),
    ("sed -i '' 's/a/b/' kb.py", True),
    ("perl -pi -e 's/a/b/' kb.py", True),
    ("find . -name '*.pyc' -delete", True),
    ("curl -s http://127.0.0.1:7842/api/kb -o out.json", True),
    ("sh -c 'echo x > y'", True),
    ("bash -c \"cat a | tee b\"", True),
    ("ls | xargs rm", True),
    ("cat <<'EOF' > docs/x.md\nhello\nEOF", True),
    ("FOO=1 tee x", True),
    # allowed
    ("""python3 -c "print(open('kb.py').read()[:10])" """, False),
    ("""python3 -c "print(open('kb.py', 'rb').read()[:10])" """, False),
    ("python3 -m unittest discover -s tests", False),
    ("python3 -m unittest discover -s tests 2>&1 | tail -3", False),
    ("python3 -c \"import kb; print(len(kb.note_paths()))\"", False),
    ("python3 scripts/bake.py --all", False),
    ("uv run pytest -q", False),
    ("worker/.venv/bin/pytest tests/", False),
    ("npm test", False),
    ("npm run build", False),
    ("npx vitest run", False),
    ("npx tsc --noEmit", False),
    ("node --check dist/cli.js", False),
    ("sh tests/run.sh", False),
    ("osacompile -o dist/x.app src.applescript", False),
    ("sed -n '1,40p' kb.py", False),
    ("cat kb.py | head -20", False),
    ("grep -n 'def _group_of' kb.py", False),
    ("rg _group_of kb.py tests/", False),
    ("ls -la docs/reviews", False),
    ("find . -name '*.py' -not -path './.git/*'", False),
    ("wc -l kb.py", False),
    ("diff <(sort a) <(sort b)", False),
    ("git status -sb", False),
    ("git diff --stat", False),
    ("git log --oneline -5", False),
    ("git add kb.py tests/test_kb.py", False),
    ("git commit -m \"Read every folder on a note's path in _group_of\"", False),
    ("git commit -m \"$(cat <<'EOF'\nA message that mentions open(path, \"w\") and tee > x in prose\nEOF\n)\"", False),
    ("git commit -m 'Marco'\"'\"'s ruling of 2026-09-05 -> applied'", False),
    ("git commit -F - <<'EOF'\nRead <scope>/handoff/orders/x.md; a (rm) and tee > nothing in prose\nEOF", False),
    ("git commit -F - <<'EOF'\nMarco's ruling: a > b, it's prose\nEOF", False),
    ("git commit -q -F - <<'EOF'\nprose\nEOF\ngit push origin main", False),
    ("git push origin main", False),
    ("git mv old.py new.py", False),
    ("curl -s http://127.0.0.1:7842/api/kb | python3 -c \"import json,sys; print(len(json.load(sys.stdin)['scopes']))\"", False),
    ("launchctl kickstart -k gui/501/com.marco.hq-dashboard", False),
    ("echo done > /dev/null", False),
    ("echo done >/dev/null 2>&1", False),
    ("cd /Users/marcoramo/hq/code-base/hq-dashboard && python3 -m unittest discover -s tests", False),
]


def self_test():
    bad = 0
    for command, refused in FIXTURES:
        reason = reason_for(command)
        got = reason is not None
        mark = "ok  " if got == refused else "MISS"
        bad += got != refused
        shown = command.replace("\n", "\\n")
        print("%s %-8s %s%s" % (mark, "refused" if got else "allowed", shown[:96],
                                ("  <- " + reason) if reason else ""))
    print("%d fixtures, %d misses" % (len(FIXTURES), bad))
    return 1 if bad else 0


def main():
    if "--self-test" in sys.argv[1:]:
        sys.exit(self_test())
    try:
        data = json.loads(sys.stdin.read() or "{}")
        if data.get("tool_name") not in (None, "Bash"):
            return
        command = ((data.get("tool_input") or {}).get("command")) or ""
        if not command.strip():
            return
        reason = reason_for(command)
        if reason:
            deny(reason)
    except SystemExit:
        raise
    except Exception:
        return                                # fail open


if __name__ == "__main__":
    main()
