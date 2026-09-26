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

Every rule but the interpreter scan applies per simple command. The command is split as
a shell splits it, on `;`, `&&`, `||`, `|`, `&`, parentheses and an unquoted newline,
after heredoc bodies and `#` comments are taken out and backslash-newline continuations
joined, so a write on any line of a multi-line command is checked and a heredoc's prose is
never read as commands. An escaped double quote inside a double-quoted string stays inside
it, as it does in a shell, so a commit message quoting a value in escaped quotes is still
one argument. Until 2026-09-26 (finding ams-37) a newline read as whitespace, and a whole
multi-line command was judged by its first line's command word alone; until the same day
an escaped double quote closed its string, and a commit message's `; { } < >` was read as
commands and a redirection.

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
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "|&", ";;", "\n"}
#: The characters the lexer groups as punctuation. A newline is one of them, so an
#: unquoted newline ends one command and starts the next, as it does in a shell.
PUNCTUATION = "();<>|&\n"
SEPARATOR_CHARS = ";&|()\n"
NULL_TARGETS = {"/dev/null", "/dev/stdout", "/dev/stderr"}

MODE_LITERAL = re.compile(r"""['"]([rwaxbtU+]{1,4})['"]""")
MODE_KWARG = re.compile(r"""mode\s*=\s*['"]([^'"]*)['"]""")
ESCAPED_QUOTE = re.compile(r"""\\(['"])""")
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
    """The mode literal of an `open(` call that opens for writing, or None.

    An escaped quote is read as the quote it stands for, so `open(\\"x\\", \\"w\\")`
    inside a double-quoted `python3 -c` string shows its mode as plainly as
    `open('x', 'w')` does. A positional mode is looked for after the first comma
    only, since the first argument is the path and a path such as `"x"` or `"a"`
    is no mode.
    """
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
        args = ESCAPED_QUOTE.sub(r"\1", text[start:i + 1])
        comma = args.find(",")
        for lit in MODE_LITERAL.findall(args[comma + 1:] if comma >= 0 else ""):
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


#: A heredoc operator and its delimiter word: `<<EOF`, `<<-EOF`, `<<'EOF'`, `<< "EOF"`,
#: `<<\EOF`. A here-string (`<<<`) is excluded by the caller.
HEREDOC_OP = re.compile(r"""<<(-?)[ \t]*(?:'([^'\n]*)'|"([^"\n]*)"|\\?([^\s;&|()<>'"]+))""")


def split_heredocs(command):
    """The command with every heredoc body taken out, and the bodies in operator order.

    Read as a shell reads it, outside quotes only: a heredoc's body runs from the line
    after its operator to the line holding its delimiter alone (leading tabs stripped
    for `<<-`), and both leave the command text, so commit-message and scratch-file
    prose is never read as commands once a newline separates them. The same pass drops
    a `#` comment up to, never including, its newline, and joins a backslash-newline
    line continuation, which a shell reads as no separator at all. An escaped double
    quote inside a double-quoted string becomes `\\'`, which the lexer (it has no escape
    handling) reads as content rather than as the string's end, and which the
    interpreter scan reads back as the quote it stands for when matching an open mode
    (`open_write_mode`). It never raises: a quote left open simply runs to the end, and
    the lexer then decides.
    """
    outer, bodies, pending = [], [], []
    i, n, quote = 0, len(command), None
    while i < n:
        c = command[i]
        if quote == "'":
            outer.append(c)
            i += 1
            if c == "'":
                quote = None
            continue
        if c == "\\" and i + 1 < n:
            if command[i + 1] == "\n":
                i += 2                        # a line continuation, not a separator
                continue
            if quote == '"' and command[i + 1] == '"':
                outer.append("\\'")           # an escaped quote stays inside its string
                i += 2
                continue
            outer.append(command[i:i + 2])
            i += 2
            continue
        if quote == '"':
            outer.append(c)
            i += 1
            if c == '"':
                quote = None
            continue
        if c in "'\"":
            quote = c
            outer.append(c)
            i += 1
            continue
        if c == "#" and (i == 0 or command[i - 1] in " \t\n;&|()"):
            j = command.find("\n", i)
            i = n if j < 0 else j            # the comment goes; its newline stays
            continue
        if command.startswith("<<", i) and not command.startswith("<<<", i) and (i == 0 or command[i - 1] != "<"):
            m = HEREDOC_OP.match(command, i)
            if m:
                word = next(g for g in m.groups()[1:] if g is not None)
                pending.append((word, m.group(1) == "-"))
                outer.append(m.group(0))
                i = m.end()
                continue
        if c == "\n" and pending:
            outer.append(c)
            i += 1
            for word, strip_tabs in pending:
                body = []
                while i < n:
                    j = command.find("\n", i)
                    line = command[i:] if j < 0 else command[i:j]
                    i = n if j < 0 else j + 1
                    if (line.lstrip("\t") if strip_tabs else line) == word:
                        break
                    body.append(line)
                bodies.append("\n".join(body))
            pending = []
            continue
        outer.append(c)
        i += 1
    bodies.extend("" for _ in pending)       # an operator with no line after it
    return "".join(outer), bodies


def lex_tokens(text):
    """Tokenise a command whose heredoc bodies are already out (`split_heredocs`).

    An unquoted newline is punctuation rather than whitespace, so it separates two
    commands, while a newline inside a quoted string stays content. `commenters` is
    empty so no `#` swallows the newline after it.
    """
    lex = shlex.shlex(text, posix=False, punctuation_chars=PUNCTUATION)
    lex.whitespace_split = True
    lex.commenters = ""
    lex.whitespace = lex.whitespace.replace("\n", "")
    return list(lex)


def tokens_of(command):
    return lex_tokens(split_heredocs(command)[0])


def simple_commands(toks):
    """Split a token list into simple commands on the shell's separators, an unquoted
    newline among them."""
    out, cur = [], []
    for t in toks:
        if t in SEPARATORS or all(c in SEPARATOR_CHARS for c in t):
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
        if t.startswith(">") and i and cmd[i - 1].endswith("="):
            continue                          # `=>`, an arrow function, not a redirection
        nxt = unquote(cmd[i + 1]) if i + 1 < len(cmd) else ""
        if t.endswith(">&") or t.endswith(">>&"):
            if re.fullmatch(r"\d+|-", nxt):
                continue                      # 2>&1, a descriptor duplicate
            return "the redirection `%s %s`" % (t, nxt)
        if nxt in NULL_TARGETS or nxt.startswith("/dev/fd/") or re.fullmatch(r"&\d+", nxt):
            continue
        return "the redirection `%s %s`" % (t, nxt)
    return None


def check_tokens(toks, raw, depth=0, bodies=None):
    """The refusal reason for a tokenised command, or None.

    `bodies` are the heredoc bodies `split_heredocs` took out, in operator order, which
    the interpreter scan reads beside `raw` -- every body but a git message's. None means
    `raw` still carries its bodies, as it does for the string a spawned shell runs.
    """
    if depth > 3:
        return None
    scan_raw = False
    opened, prose = 0, set()                  # heredoc operators met; which bodies are prose
    for cmd in simple_commands(toks):
        word, at = command_word(cmd)
        rest = cmd[at + 1:]
        first, opened = opened, opened + sum(1 for t in cmd if t == "<<")
        if word == "git" and rest and unquote(rest[0]) in {"commit", "tag", "notes", "merge"}:
            # git's own writes, and a message never scanned: a heredoc message's body is
            # already out of the tokens and is kept out of the interpreter scan, while the
            # commands after its delimiter line are read like any others (finding ams-37).
            prose.update(range(first, opened))
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
    if not scan_raw:
        return None
    if bodies is None:
        return interpreter_reason(raw)
    if opened != len(bodies):
        prose = set()                         # operators and bodies disagree: scan every body
    return interpreter_reason("\n".join([raw] + [b for i, b in enumerate(bodies) if i not in prose]))


def check_raw(command):
    """Coarse whole-text fallback for a command the tokenizer cannot parse."""
    if re.match(r"^\s*git\s+(commit|tag|notes|merge)\b", command):
        return None                           # a commit message's prose is never scanned
    # `=` joins the lookbehind so `=>` reads as an arrow function rather than a redirection:
    # inline JavaScript reaches this fallback whenever its quoting defeats the tokenizer.
    if re.search(r"(?<![-<>&|=])>{1,2}(?!&)\s*(?!/dev/null|/dev/stdout|/dev/stderr)\S", command):
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
    for text in (command, stripped):
        outer, bodies = split_heredocs(text)
        try:
            toks = lex_tokens(outer)
        except ValueError:
            continue
        return check_tokens(toks, strip_messages(outer), bodies=bodies)
    return check_raw(stripped)


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
    # an escaped quote stands for the quote around an open mode: the mode is still seen
    (r'''python3 -c "open(\"x\", \"w\")"''', True),
    (r'''python3 -c "open(\"x\", \"a\")"''', True),
    (r'''python3 -c 'open("out.txt", '"\"w\""')' ''', True),
    ("echo x | tee docs/hook-probe.txt", True),
    ("cat kb.py > copy.py", True),
    ("cat kb.py >> copy.py", True),
    ("echo x 2> err.txt", True),
    ("echo x >file", True),
    ("echo x > file", True),
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
    # an unquoted newline separates two commands, so a write on a later line is still seen
    # (finding ams-37): shlex read it as whitespace, and the whole text became one command
    # whose command word was the first line's `git` or `ls`
    ("git status --short\npython3 -c \"open('x', 'w')\"", True),
    ("ls\nfind . -name '*.orig' -delete", True),
    ("ls\nsh -c 'echo x > y'", True),
    # a trailing comment cannot swallow the newline that ends it
    ("ls # tidy\nrm -rf x", True),
    # a heredoc commit's body is prose, but the command after its terminator is a command
    ("git commit -q -F - <<'EOF'\nprose that says rm x\nEOF\nrm x", True),
    # allowed
    ("""python3 -c "print(open('kb.py').read()[:10])" """, False),
    ("""python3 -c "print(open('kb.py', 'rb').read()[:10])" """, False),
    # a read whose path is a mode letter, in escaped quotes: the first argument is no mode
    (r'''python3 -c "print(open(\"x\").read())"''', False),
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
    # an arrow function is not a redirection: the run-log command this guard refused on
    # 2026-09-22, whose escaped quotes defeated the tokenizer and reached check_raw until
    # split_heredocs kept an escaped double quote inside its string (2026-09-26)
    (r'''cd /private/tmp/claude-501/-Users-marcoramo-hq-code-base-build-dispatcher/f4ac6278-c0c8-4f34-9b47-87a0a200676a/scratchpad/appserver-schema && node -e "const s=require('./codex_app_server_protocol.v2.schemas.json'); const cr=s.definitions?.ClientRequest||s.\$defs?.ClientRequest; console.log(Object.keys(s.definitions||s.\$defs||{}).length); const j=JSON.stringify(s); const ms=[...j.matchAll(/\"method\":\{[^}]*\"const\":\"([^\"]+)\"/g)].map(m=>m[1]); console.log(JSON.stringify([...new Set(ms)],null,1))"''', False),
    ("node -e 'xs.map(m=>m[1])'", False),
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
    # a comment line is no command, and a `>` inside one is no redirection
    ("# count\nls tests", False),
    ("# a > b\nwc -l index.html", False),
    # a commit message is never a redirection: the aa-design-lab fix leg's commit this
    # guard refused on 2026-09-26, whose escaped double quotes (`\"12px\"`) the tokenizer
    # read as closing the message, leaving `; { } < > or` outside it
    (r'''git commit -m "Route the studio's switches and words box by exact name, and make the words box refuse what no save could write, fixing SUFFIX-01 and TEXTVAL-01 from the bug sweep of 2026-09-26. SUFFIX-01: makeControl tested the suffixes -arrow, -display, -mesh and -text before a token's type, so --font-display got the tape's off/on switch in place of its typeface menu, --gap-title-arrow and --opacity-title-arrow got off/↗ switches writing none and a quoted glyph into a margin and an opacity, and --gap-icon-text got a words box writing a quoted \"12px\", on all fifteen variations. The choice now lives in studio-tokens.js as controlKindOf(name, value): --title-arrow is the arrow switch, --tape-display the display switch, --header-text and --tape-text the words box, a name ending in -mesh keeps the mesh gate (it catches only --bg-mesh and --bg-content-mesh), and every other token takes typeOf's answer; typeOf, RE_LEN and RE_NUM move from studio.html into studio-tokens.js with it, and the studio loads studio-tokens.js?v=2. TEXTVAL-01: the box's writer is now quoteText(words), which returns null for words holding ; { } < > or quoting to more than 200 code points, the save helper's and the live relay's ^[^;{}<>]{1,200}$; the box then shows the reason beside itself and applies nothing, where before one such value made save answer 400 and write none of the session's edits and made the relay drop every later push. TOKENS.md's two sentences on suffix routing now name the tokens. tests/control-kind.test.js and tests/quote-text.test.js failed before the fix (controlKindOf and quoteText not functions, no words branch in studio.html) and pass after; replaying the shipped suffix order gives display, words, arrow and arrow for the four ordinary tokens, and replaying the shipped writer emits Read > Listen, a; b and a 199-character line unchanged into values both servers refuse." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"''', False),
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
