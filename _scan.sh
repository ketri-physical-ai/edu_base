#!/usr/bin/env bash
# _scan.sh — 데이터셋을 훑어 이상한 판을 찾아 표로 찍는다. **지우지 않는다.**
#   사용 :  bash _scan.sh <데이터셋경로> [시작ep] [끝ep]
#   출력 :  사람이 읽는 표 + 마지막 줄에 `FLAGGED=3,7,12` (2-3 이 이 줄을 읽는다)
#
# ⚠ 판정 규칙은 _view.sh 의 것과 같아야 한다. 한쪽을 고치면 다른 쪽도 고칠 것.
#   (시간상한 · 너무 짧다 · 너무 길다 · 어긋난 판 · 영상 중복)
set -uo pipefail
_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"
# shellcheck disable=SC1091
source "$_SELF_DIR/_env.sh"; edu_activate || exit 1

ROOT="${1:?사용법: _scan.sh <데이터셋경로> [시작ep] [끝ep]}"
LO="${2:-}" HI="${3:-}"

ROOT="$ROOT" LO="$LO" HI="$HI" \
SHORT_R="${VIEW_SHORT_RATIO:-0.55}" LONG_R="${VIEW_LONG_RATIO:-1.45}" \
EP_TIME_S="${EPISODE_TIME_S:-0}" python3 <<'PY'
import os, json, glob
from pathlib import Path
import pandas as pd

root = Path(os.environ["ROOT"])
lo   = os.environ.get("LO") or None
hi   = os.environ.get("HI") or None
SHORT_R = float(os.environ["SHORT_R"]); LONG_R = float(os.environ["LONG_R"])

info = json.load(open(root / "meta" / "info.json")); fps = info["fps"]
df = pd.concat([pd.read_parquet(p) for p in
                sorted(glob.glob(str(root / "meta/episodes/**/*.parquet"), recursive=True))]
               ).sort_values("episode_index")
vkeys = [k for k in info["features"] if k.startswith("observation.images.")]

# 두 등급으로 나눈다.
#   err  = 데이터가 깨졌거나 과제를 못 끝낸 판 — 대체로 지운다
#   note = 길이 편차일 뿐 — 영상을 봐야 안다. 미리 지우자고 권하지 않는다
ERRS, NOTES = {}, {}
def flag(i, why, lvl="err"):
    d = ERRS if lvl == "err" else NOTES
    d.setdefault(int(i), [])
    if why not in d[int(i)]: d[int(i)].append(why)

lens = {int(r.episode_index): int(r.length) for _, r in df.iterrows()}
MED  = float(pd.Series(list(lens.values())).median()) if lens else 0.0
# 시간상한 판정 — 두 갈래로 본다.
#   ① 녹화 설정을 아는 경우 : 상한 프레임에 닿은 판이 상한이다.
#   ② 모르는 경우 : 최대 길이를 두 판 이상이 공유하고, **그 값이 중앙값보다
#      뚜렷이 클 때만** 상한으로 본다. 우연히 길이가 겹친 것을 상한이라 부르면
#      멀쩡한 판이 걸린다 (실제로 7.8초를 20초 상한이라 오판한 적이 있다).
_EPT  = float(os.environ.get("EP_TIME_S", "0") or 0)
_CAPF = round(_EPT * fps) if _EPT > 0 else 0
CAPPED = set()
#   상한에 걸린 판은 그 값을 **넘지 않고 정확히 닿는다**. 넘었으면 그 설정이 아니다.
if _CAPF and lens and any(abs(L - _CAPF) <= 2 for L in lens.values()):
    CAPPED = {i for i, L in lens.items() if abs(L - _CAPF) <= 2}
if not CAPPED and lens:
    _mx = max(lens.values())
    if list(lens.values()).count(_mx) >= 2 and MED and _mx > MED * LONG_R:
        CAPPED = {i for i, L in lens.items() if L == _mx}

for i, L in lens.items():
    if i in CAPPED:
        flag(i, f"시간상한 {L/fps:.1f}s")
    elif MED and L < MED * SHORT_R:
        flag(i, f"너무 짧다 {L/fps:.1f}s", "note")
    elif MED and L > MED * LONG_R:
        flag(i, f"너무 길다 {L/fps:.1f}s", "note")

for _, r in df.iterrows():
    i, n = int(r.episode_index), int(r.length)
    hits = {}
    for k in vkeys:
        try:
            seg = round((float(r[f"videos/{k}/to_timestamp"]) -
                         float(r[f"videos/{k}/from_timestamp"])) * fps)
        except KeyError: continue
        if abs(seg - n) > 1: hits[k.rsplit(".", 1)[-1]] = seg
    if not hits: continue
    segs = set(hits.values())
    if len(segs) == 1 and len(hits) == len(vkeys):
        flag(i, f"어긋남 데이터{n}/영상{segs.pop()}")
    else:
        flag(i, "어긋남 카메라불일치 " + " ".join(f"{c}{v-n:+d}" for c, v in sorted(hits.items())))

dup = {}
for k in vkeys:
    try:
        seg = [(int(r.episode_index), int(r[f"videos/{k}/chunk_index"]),
                int(r[f"videos/{k}/file_index"]),
                float(r[f"videos/{k}/from_timestamp"]),
                float(r[f"videos/{k}/to_timestamp"])) for _, r in df.iterrows()]
    except KeyError: continue
    seg.sort(key=lambda x: (x[1], x[2], x[3]))
    for (i1,c1,f1,a1,b1),(i2,c2,f2,a2,b2) in zip(seg, seg[1:]):
        if (c1,f1) != (c2,f2): continue
        ov = min(b1,b2) - max(a1,a2)
        if ov > 0.05:
            dup.setdefault((i1,i2), []).append(ov)
for (i1,i2), ovs in dup.items():
    flag(i1, f"영상중복 ep{i2}"); flag(i2, f"영상중복 ep{i1}")

def pick(d):
    k = sorted(d)
    return [i for i in k if int(lo) <= i <= int(hi)] if lo is not None else k

err, note = pick(ERRS), pick(NOTES)
if err or note:
    if err:
        print("  ── ⚠ 오류 — 지우는 쪽을 권한다 ─────────────────")
        for i in err:
            print(f"    ep {i:<4d} {' · '.join(ERRS[i])}")
    if note:
        print("  ── ? 확인 — 영상을 보고 판단한다 ───────────────")
        for i in note:
            print(f"    ep {i:<4d} {' · '.join(NOTES[i])}")
    print("  ───────────────────────────────────────────────")
else:
    print("  이상한 판 없음 ✔")
print("FLAGGED=" + ",".join(str(i) for i in err))
print("NOTED="   + ",".join(str(i) for i in note))
PY
