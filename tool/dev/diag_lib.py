import subprocess, json, re
from collections import Counter
adb = r"C:\Users\Rubu\AppData\Local\Android\Sdk\platform-tools\adb.exe"

def shb(args):
    r = subprocess.run([adb, "shell"] + args, capture_output=True)
    return r.stdout.decode("utf-8", errors="replace")

xml = shb(["run-as com.chobiflow.chobiflow cat shared_prefs/FlutterSharedPreferences.xml"])
open(r"C:\Users\Rubu\AppData\Local\Temp\opencode\prefs2.xml", "w", encoding="utf-8").write(xml)
print("prefs bytes:", len(xml))

def get_str(key):
    m = re.search(re.escape(key) + r".{0,40}?>(.*?)</string>", xml, re.S)
    if not m:
        return None
    return (m.group(1).replace("&quot;", '"').replace("&amp;", "&")
            .replace("&lt;", "<").replace("&gt;", ">").replace("&#10;", "\n"))

shots = json.loads(get_str("chobiflow_shots_v1"))
cols = {c["id"]: c["name"] for c in json.loads(get_str("chobiflow_cols_v1"))}
print("collections:", cols)
print("total shots:", len(shots))

by_col = Counter()
no_ocr = 0
empty_ocr = 0
titles = {}
for s in shots:
    by_col[s.get("collectionId")] += 1
    if not s.get("ocrDone"):
        no_ocr += 1
    if not (s.get("ocrText") or "").strip():
        empty_ocr += 1
    titles.setdefault(s.get("collectionId"), []).append(
        (s.get("title", ""), s.get("tags", []), (s.get("ocrText") or "")[:80].replace("\n", " ")))
print("\n-- per-collection counts --")
for cid, n in by_col.most_common():
    print(f"{cols.get(cid, cid)}: {n}")
print(f"\nno ocrDone: {no_ocr}, empty ocrText: {empty_ocr}")

print("\n-- sample titles per builtin stack --")
for cid in ["recent", "work", "chats", "travel", "personal", "notes"]:
    print(f"\n== {cols.get(cid, cid)} ==")
    for t, tags, ocr in (titles.get(cid) or [])[:10]:
        print(f"  - {t[:60]!r} tags={tags}")

# corpus-wide top words from titles+ocr (what categories exist?)
from collections import Counter as C
freq = C()
for s in shots:
    text = ((s.get("title") or "") + " " + (s.get("ocrText") or "")).lower()
    for w in re.split(r"[^a-z]+", text):
        if len(w) >= 5 and w not in {"screenshot", "screenshots"}:
            freq[w] += 1
print("\n-- top corpus words --")
print(freq.most_common(40))
