#!/usr/bin/env bash
# Mirror the jamovi documentation locally so it can be grepped instead of clicked.
#
#   ./mirror-jamovi-docs.sh [outdir]        # default: ./jamovi-docs
#
# Produces  <outdir>/html/  (the raw mirror) and <outdir>/txt/ (plain text,
# one .txt per page) — the text copy is what you grep.
set -euo pipefail

OUT="${1:-jamovi-docs}"
mkdir -p "$OUT/html"

for site in dev.jamovi.org docs.jamovi.org; do
    echo "mirroring $site ..."
    wget --quiet --mirror --no-parent --adjust-extension --convert-links \
         --reject 'png,jpg,jpeg,gif,svg,woff,woff2,ttf,ico,mp4,webm' \
         --exclude-directories='/_static' \
         -P "$OUT/html" "https://$site/" || true
done

python3 - "$OUT/html" "$OUT/txt" <<'PY'
import html, os, re, sys

root, out = sys.argv[1], sys.argv[2]

BODY = re.compile(r'<(?:main|article)\b[^>]*>(.*?)</(?:main|article)>', re.S | re.I)
DROP = re.compile(r'<(script|style|nav|header|footer)\b[^>]*>.*?</\1>', re.S | re.I)
PRE  = re.compile(r'<pre\b[^>]*>(.*?)</pre>', re.S | re.I)
TAG  = re.compile(r'<[^>]+>')

def convert(path):
    raw = open(path, encoding='utf-8', errors='replace').read()
    m = BODY.search(raw)
    body = m.group(1) if m else raw
    body = DROP.sub(' ', body)
    body = PRE.sub(lambda m: '\n```\n' + TAG.sub('', m.group(1)) + '\n```\n', body)
    body = re.sub(r'</(p|div|li|tr|h[1-6])>', '\n', body, flags=re.I)
    body = re.sub(r'<li\b[^>]*>', '- ', body, flags=re.I)
    body = re.sub(r'<h([1-6])\b[^>]*>',
                  lambda m: '\n' + '#' * int(m.group(1)) + ' ', body, flags=re.I)
    body = re.sub(r'</t[dh]>', ' | ', body, flags=re.I)
    body = html.unescape(TAG.sub('', body))
    body = re.sub(r'[ \t]+', ' ', body)
    return re.sub(r'\n\s*\n\s*\n+', '\n\n', body).strip()

n = 0
for dirpath, _, names in os.walk(root):
    for name in names:
        if not name.endswith('.html'):
            continue
        src = os.path.join(dirpath, name)
        rel = os.path.relpath(src, root)
        if rel.endswith('/index.html'):      # duplicate of the sibling page
            continue
        dst = os.path.join(out, rel[:-5] + '.txt')
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        open(dst, 'w', encoding='utf-8').write(convert(src))
        n += 1
print(f'{n} pages -> {out}')
PY

echo
echo "grep it, e.g.:  grep -rin 'setSize2' $OUT/txt"
