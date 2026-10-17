import subprocess, json, re
adb = r"C:\Users\Rubu\AppData\Local\Android\Sdk\platform-tools\adb.exe"

def shb(args):
    r = subprocess.run([adb, "shell"] + args, capture_output=True)
    return r.stdout.decode("utf-8", errors="replace")

xml = shb(["run-as com.chobiflow.chobiflow cat shared_prefs/FlutterSharedPreferences.xml"])
open(r"C:\Users\Rubu\AppData\Local\Temp\opencode\prefs.xml", "w", encoding="utf-8").write(xml)
print("prefs bytes:", len(xml))
for key in ["smartran", "autosmart", "emb_v1"]:
    print(key, "present:", key in xml)

m = re.search(r"chobiflow_emb_v1.{0,30}?>((?:(?!</string>).)*)</string>", xml, re.S)
if m:
    val = m.group(1).replace("&quot;", '"').replace("&amp;", "&").replace("&#10;", "")
    try:
        d = json.loads(val)
        tot, ok = len(d), sum(1 for v in d.values() if v)
        print("emb entries:", tot, "non-empty:", ok)
    except Exception as e:
        print("emb json fail:", str(e)[:120], "head:", val[:120])
else:
    print("no emb string node")

log = shb(["logcat -d | grep -i -E 'onnx|E/Flutter|chobiflow|TextRecognition' | tail -30"])
open(r"C:\Users\Rubu\AppData\Local\Temp\opencode\logcat_rel.txt", "w", encoding="utf-8").write(log)
print("--- relevant log tail ---")
print(log[-3000:] if log else "(empty)")
