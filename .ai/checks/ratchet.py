#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""棘轮检查 —— 存量豁免，新增拦死。纯标准库，不依赖任何第三方包。

    ratchet.py lines --baseline F --limit 500 --paths 'server/src/*.rs' ...
    ratchet.py grep  --baseline F --pattern 'fetch\\(|axios\\.' --paths 'web/src/*.vue' [--exclude PREFIX ...]

RATCHET_REFRESH=1 重新生成基线（= 认可现状，需要人工确认，不是 Agent 能自己做的事）。

为什么不用 shell 写：同样的扫描 bash 要 2.4 秒（每个文件 fork 一次 wc），这里 50 毫秒；
更重要的是 shell 版的失效模式是**静默返回空 = 假绿**，而这里空结果直接判失败。
"""
import sys, os, re, subprocess, io, fnmatch

def die(msg, code=2):
    sys.stderr.write("ratchet: %s\n" % msg); sys.exit(code)

def repo_root():
    try:
        r = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True)
    except OSError as e:
        die("找不到 git: %s" % e)
    if r.returncode != 0:
        die("不在 git 仓库里: %s" % r.stderr.strip())
    return r.stdout.strip()

def list_files(paths):
    """已跟踪 + 新建未提交（Developer 刚写的新文件不能漏检）"""
    cmd = ["git", "ls-files", "--cached", "--others", "--exclude-standard", "--"] + list(paths)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        die("git ls-files 失败: %s" % r.stderr.strip())
    out = []
    seen = set()
    for f in r.stdout.split("\n"):
        f = f.strip()
        if f and f not in seen and os.path.isfile(f):
            seen.add(f); out.append(f)
    return out

def read_baseline(path):
    rows = {}
    if os.path.isfile(path):
        for line in io.open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line or line.startswith("#"): continue
            if "\t" in line:
                k, v = line.split("\t", 1); rows[k] = v.strip()
            else:
                rows[line] = ""
    return rows

def write_baseline(path, rows, header):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d): os.makedirs(d)
    with io.open(path, "w", encoding="utf-8") as f:
        f.write(u"# %s\n" % header)
        f.write(u"# 刷新基线 = 认可现状，需要人工确认。不准为了让守卫闭嘴而刷新。\n")
        for k in sorted(rows):
            f.write(u"%s\t%s\n" % (k, rows[k]) if rows[k] != "" else u"%s\n" % k)

def arg(name, default=None, many=False):
    a = sys.argv
    if name not in a:
        if default is None and not many: die("缺少参数 %s" % name)
        return [] if many else default
    i = a.index(name) + 1
    if many:
        out = []
        while i < len(a) and not a[i].startswith("--"):
            out.append(a[i]); i += 1
        return out
    if i >= len(a): die("参数 %s 没有值" % name)
    return a[i]

def main():
    if len(sys.argv) < 2: die(__doc__)
    mode = sys.argv[1]
    os.chdir(repo_root())
    baseline = arg("--baseline")
    paths = arg("--paths", many=True)
    if not paths: die("--paths 不能为空")
    refresh = os.environ.get("RATCHET_REFRESH", "0") == "1"
    files = list_files(paths)

    # 空结果即可疑：shell 版最严重的事故就是扫不到文件却报 PASS
    if not files:
        die("扫描到 0 个文件（paths=%s）—— 路径写错或 cwd 不对，判失败而不是放行" % " ".join(paths))

    if mode == "lines":
        limit = int(arg("--limit", "500"))
        cur = {}
        for f in files:
            try:
                with io.open(f, "rb") as fh:
                    n = sum(1 for _ in fh)
            except IOError:
                continue
            if n > limit: cur[f] = str(n)
        if refresh:
            write_baseline(baseline, cur, u"超过 %d 行的存量文件，只许变短。" % limit)
            print(u"↻ [linecount] 基线已刷新：%d 个超阈文件" % len(cur)); return 0
        base = read_baseline(baseline)
        bad = []
        for f, n in sorted(cur.items()):
            n = int(n)
            if f not in base:
                bad.append(u"%s: %d 行，首次超过 %d 行上限\n     → 按职责拆成新文件，不要按行数硬切" % (f, n, limit))
            elif n > int(base[f]):
                bad.append(u"%s: %d 行，比基线 %s 行更长了（+%d）\n     → 超阈文件只许变短。先把它拆开，再往拆出来的地方加"
                           % (f, n, base[f], n - int(base[f])))
        if bad:
            print(u"── %-20s FAIL" % "linecount")
            for b in bad: print(u"      ❌ " + b)
            return 1
        shrunk = [f for f in base if f in cur and int(cur[f]) < int(base[f])]
        note = u"（%d 个文件变短了，可刷新基线收紧）" % len(shrunk) if shrunk else ""
        print(u"── %-20s PASS  %s" % ("linecount", note)); return 0

    if mode == "grep":
        pattern = re.compile(arg("--pattern"))
        excl = arg("--exclude", many=True)
        name = arg("--name", "grep")
        cur = {}
        for f in files:
            if any(f.startswith(x) for x in excl): continue
            try:
                txt = io.open(f, encoding="utf-8", errors="replace").read()
            except IOError:
                continue
            if pattern.search(txt): cur[f] = ""
        if refresh:
            write_baseline(baseline, cur, u"%s 的存量违规，只许减少。" % name)
            print(u"↻ [%s] 基线已刷新：%d 项" % (name, len(cur))); return 0
        base = read_baseline(baseline)
        new = [f for f in sorted(cur) if f not in base]
        if new:
            print(u"── %-20s FAIL" % name)
            for f in new: print(u"      ❌ 新增违规: %s" % f)
            return 1
        print(u"── %-20s PASS" % name); return 0

    die("未知模式 %s" % mode)

sys.exit(main())
