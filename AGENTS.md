# AGENTS.md — ChobiFlow agent handoff

> Read this file first. It contains everything a new agent needs to resume
> work on ChobiFlow without rediscovering hard-won facts. The user-facing
> story lives in `README.md`; this file is the **operator's manual**.

## 1. What this is

**ChobiFlow** — an offline-first Flutter screenshot organizer ("Chobi" =
picture). Auto-imports the device Screenshots folders, reads text inside
each shot (ML Kit OCR), lets a vision model invent categories (MobileCLIP2
+ clustering), all on-device. No accounts, no servers, no fees.

- Project root: `C:\Users\Rubu\Desktop\ChobiFlow`
- Package: `chobiflow`, app id `com.chobiflow.chobiflow`, display name **ChobiFlow**
- Flutter: `C:\flutter\bin\flutter.bat` (3.44 / Dart 3.12) — use full path, no PATH reliance
- Status: installed + verified on the user's physical **Samsung S22 Ultra**
  (`adb` serial `R5CT33FRFMR`, ~300 real screenshots). Emulator exists but the
  phone is the source of truth.

## 2. Architecture map

```
lib/main.dart                  bootstrap, splash, themeMode, onboarding gate
lib/chobi_theme.dart           "Marigold Flow on Ink" theme + FlowRibbon painter
lib/models.dart                ShotItem (+ocrText/ocrDone), ShotCollection (+isAuto)
lib/flow_store.dart            ChangeNotifier store: CRUD, search/filter/sort,
                               importDeviceShots (batched), runOcrBatch,
                               runSmartAnalysis, applySmartProposals, emb cache
lib/device_import.dart         MediaStore scan (ALL screenshot albums), norm(),
                               keywords(), guessFromText(), guessCollectionId()
lib/smart_stacks.dart          MobileCLIP2 embedder, cosine/jaccard,
                               discoverClusters(), refineLargeGroups(),
                               nameCluster(), SmartProposal, SmartEngine
lib/widgets/flow_widgets.dart  ShotThumb (480px thumbs), ShotMasonrySliver
                               (VIRTUALIZED — never shrinkWrap big grids),
                               Entrance (first 12 only), FanStack, EmptyFlow
lib/screens/onboarding.dart    3-page intro
lib/screens/home_shell.dart    bottom nav: Flow/Stacks/Search/Vault,
                               CollectionPage, _AddSheet, _SettingsSheet,
                               _DeviceBanner, import/OCR/smart sheets
lib/screens/detail.dart        Hero detail + actions + move rail + OCR card
tool/sync_readme.dart          README feature-table generator (SOURCE OF TRUTH)
tool/dev/                      vendored device-lab helper scripts
test/                          widget_test, identify_test, smart_test
assets/icon/                   chobiflow_icon.png + android mipmaps
```

Key pipelines (all in `flow_store.dart`, all batched single-notify+single-persist):
`scan → importDeviceShots → runOcrBatch → runSmartAnalysis → applySmartProposals`

## 3. Commands (Windows PowerShell 5.1)

```powershell
C:\flutter\bin\flutter.bat pub get
C:\flutter\bin\flutter.bat analyze          # must be clean
C:\flutter\bin\flutter.bat test            # must pass
dart tool/sync_readme.dart                  # after ANY feature change
C:\flutter\bin\flutter.bat build apk --debug
C:\Users\Rubu\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
```

- Do NOT `flutter run` for verification (blocks); build + `install -r` + monkey-launch:
  `adb shell monkey -p com.chobiflow.chobiflow -c android.intent.category.LAUNCHER 1`
- `install -r` preserves app data (prefs). `force-stop` before launch for a cold start.
- Emulator (rarely needed): `"...\Sdk\emulator\emulator.exe" -avd Medium_Phone_API_36.1`
  launched via `Start-Process` (never open Android Studio). Has no screenshots.

## 4. Device lab — patterns that WORK

- **adb binary:** `C:\Users\Rubu\AppData\Local\Android\Sdk\platform-tools\adb.exe`
- **PowerShell mangles adb quoting and binary redirects.** For MediaStore
  queries or any tricky quoting, write a `.py` file and run it with `python`
  (subprocess list-args bypass PowerShell parsing). See `tool/dev/mscheck.py`
  pattern (recreate if needed — temp was wiped once already).
- **Screenshots (binary-safe):**
  `adb shell screencap -p /sdcard/x.png` → `adb pull ...` → thumbnail with
  `tool/dev/thumb.py <src> <dst>` (480px) → `read` the thumbnail (full-size
  exceeds the image limit). NEVER `exec-out ... > file` in PowerShell.
- **Wake first:** `adb shell input keyevent KEYCODE_WAKEUP` (+ `wm dismiss-keyguard`;
  secure PIN can't be bypassed — if you see the lockscreen, stop and tell user).
- **Inspect app-private data (debug build):**
  `adb shell run-as com.chobiflow.chobiflow ls -la app_flutter/` (model file!),
  `... cat shared_prefs/FlutterSharedPreferences.xml` (decode utf-8 w/
  errors=replace; keys are HTML-escaped). See `tool/dev/diag_smart2.py`.
- **MediaStore checks:** `content query --uri content://media/external/images/media
  --projection _display_name --where "_display_name='X.png'"` (via Python).
  Media-indexing of pushed files is racy — broadcasts help but real
  camera screenshots index instantly. Folder_truth: `ls /sdcard/DCIM/Screenshots`
  (real shots) and `/sdcard/Pictures/Screenshots`.
- **Library forensics:** `tool/dev/diag_lib.py` dumps per-collection counts +
  samples + corpus keywords from the app's JSON. Run this BEFORE redesigning
  any organization logic.
- **Device comes and goes** (USB drops when the user grabs the phone). Poll
  `adb devices` for `R5CT33FRFMR` before long jobs; never force-stop/relaunch
  over an active user session without need. Prefer `install -r` without
  relaunch when they're using it.

## 5. SharedPreferences keys (exact names)

`chobiflow_shots_v1` (ShotItem JSON list), `chobiflow_cols_v1`
(ShotCollection JSON list), `chobiflow_seen_onboarding_v1`,
`chobiflow_theme_v1`, `chobiflow_density_v1`, `chobiflow_autoimport_v1`
(default true), `chobiflow_autoidentify_v1` (default true),
`chobiflow_autosmart_v1` (default true), `chobiflow_smartran_v1`,
`chobiflow_smartgen_v1` (migration generation, current **3**),
`chobiflow_emb_v1` (shot-id → base64 f32-512; `""` = failed attempt,
purged on load so failures retry).

## 6. Gotchas — learn these once, not twice

1. **Binder limit (CRITICAL):** never send a large `List<double>` through
   `flutter_onnxruntime`'s `OrtValue.fromList`. Pass the `Float32List`
   directly (~786KB typed-data). A 196608-elem list fails every inference.
2. **Batch-dim output:** MobileCLIP output is `[1,512]` — use
   `asFlattenedList()`, NOT `asList()` (which keeps `[[...]]` and the
   `as num` cast throws). Always dispose input/output `OrtValue`s per image.
3. **Never `shrinkWrap` big grids.** `ShotMasonrySliver` (SliverMasonryGrid)
   + entrance animations for first 12 cells only + 480px `ResizeImage`
   thumbs. Full-res `Image.file` per cell was jank #1.
4. **Batch persistence.** One notify + one persist per batch job
   (import/OCR/smart). Per-item persist of ~300 JSON rewrites froze the UI.
5. **Tall-portrait→Chats heuristic DELETED** (it once dumped 249 shots into
   Chats). First-pass filename guessing stays conservative (`recent`
   default); vision + OCR do the real sorting.
6. **Scan ALL screenshot albums** (Samsung: `DCIM/Screenshots` real shots +
   `Pictures/Screenshots`). A `break` after the first album once orphaned a
   whole folder. Dedupe by `norm()`ed path (`/sdcard` ≡ `/storage/emulated/0`).
7. **Eligibility:** Smart Stacks may reorganize machine-made stacks
   (builtin + auto) but NEVER user-created custom stacks, trashed, or archived.
8. **Empty-string emb cache = retryable.** `_loadEmbCache` drops `""`
   markers. `smartEverRan` is set only on genuine completion; `repairSmartState`
   + `smartgen` migration re-arm auto-runs after engine upgrades.
9. **`image` package v4 API:** `copyResize(src, width:/height:)`,
   `copyCrop(src, x:, y:, width:, height:)`, `getPixel().r/.g/.b`.
10. **minSdk is 24** (`android/app/build.gradle.kts`, required by
    onnxruntime-android). `proguard-rules.pro` exists per plugin README
    (debug builds unaffected).
11. **Model:** `felixhrdyn/mobileclip2-s0-onnx`, FP32 `vision_model.onnx`
    (~43MB, downloaded on demand to app docs). INT8 is FORBIDDEN for this
    backbone: dynamic quantization on FastViT = ~12x slower AND near-random
    embeddings (purity 0.14 on labeled probes). Input contract measured, not
    assumed: shortest-edge 256 **bicubic** resize, center crop, **/255 with NO
    mean/std** — OpenAI-CLIP stats measurably hurt (purity 0.94/cov 0.69 vs
    1.00/1.00). S0-fp32 == S2-fp32 quality on probes; do not "upgrade" to S2
    (3x size). Thresholds 0.78→0.72→0.66 adaptive + `refineLargeGroups`
    (re-split >60 at +0.08). Names from OCR keywords with shared
    `stopwords` ("screenshot" can never be a stack name); collisions prefer
    the 3-word variant over numeric suffixes. `image` package `copyResize`
    defaults to `Interpolation.nearest` — always pass `Interpolation.cubic`
    for photo resizes.
12. **Offline eval loop (repeat this pattern):** `tool/dev`-style scripts in
    temp: `mk_probes.py` (9x5 labeled synthetic screenshots +
    manifest.json), `eval_stacks.py` / `cross_test.py` (onnxruntime grid
    over model x preprocessing x fusion), `eval_device.py` (pulls app prefs
    via run-as, computes probe purity). Fix "quality" claims with numbers.
13. **README discipline:** `tool/sync_readme.dart` owns the features table —
    register every feature there and re-run it. CI-style rule, no exceptions.

## 7. Definition of done (every change)

1. `flutter analyze` — zero issues. 2. `flutter test` — all pass (add unit
   tests for pure logic: clustering, naming, guessing). 3. `dart
   tool/sync_readme.dart`. 4. `build apk --debug` succeeds. 5. `install -r`
   on the S22 + screenshot-verify the affected screen. 6. Report honestly:
   what's proven on-device vs. by test vs. by reasoning.

## 8. Current state (2026-10-17)

- Deployed: **Smart Stacks gen 4** — vision recalibrated (FP32 S0,
  bicubic + /255-only input contract, INT8 removed, emb-cache purges on
  engine-gen change), verified on the Medium_Phone_API_36.1 EMULATOR with
  45 synthetic labeled probes: **9/9 stacks, 45/45 shots in their exact
  category stack (purity 1.00)**, applied through the approval sheet UI.
- Phone (S22, `R5CT33FRFMR`) carries gen-3 data — NOT yet rebuilt with gen
  4. **Next phone launch triggers one re-embed pass (~300 shots, minutes,
  cancellable)** because the migration purges the embedding cache. Do not
  assume the phone run the new engine yet; prefer `install -r` when the
  user plugs in, and don't interrupt their session to force it.
- Emulator keeps the eval setup: 45 probes in `/sdcard/DCIM/Screenshots`
  (filenames `probe_<category>_0..4.png` = ground truth), app installed
  with applied AI stacks (15 collections). Wiped once this session —
  `install -r` + data survived subsequent reinstalls.
- Probe/eval scripts in `%TEMP%\opencode\`: `mk_probes.py`, `eval_stacks.py`,
  `cross_test.py`, `eval_device.py`, `mscan_probes.py`; models in
  `%TEMP%\opencode\models\` (s0/s2 fp32 + int8 variants for future studies).
- Phone library scale: ~300 shots, 279 in Screenshots folders, 272
  OCR-identified; user-applied gen-3 stacks ("Chat • Reply 2",
  "Chat • Browser", …) still in the phone's prefs.
- Also fixed this session: FanStack placeholder overflow (RenderFlex
  bottom-overflow 50px in 92x104 fan cards — compact mock below 118px;
  regression test `test/fan_overflow_test.dart`).
- Test probes in `/sdcard/Pictures/Screenshots` (phone, user may delete
  anytime): `Screenshot_flight_boarding_pass/chat_with_aarav/groceries_receipt/hotel_booking_confirm/standup_thread.png`.
- Watch items: S22 battery often low (15–27%) during heavy one-time passes;
  all long jobs are cancellable/resumable by design — keep it that way.
- Privacy rule: the phone holds real personal screenshots. Verify with
  counts/banners/stacks UI; do NOT scroll through, screenshot, or describe
  personal image content.

## 9. Suggested next steps (if asked)

Semantic search via the text encoder, cloud-LLM stack summaries (opt-in,
text-only), near-duplicate detection (pHash), burst/event grouping,
homescreen widget. Do NOT start these unasked — propose first.
