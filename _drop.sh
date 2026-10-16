#!/usr/bin/env bash
# =============================================================================
#  _drop.sh — 데이터셋에서 특정 에피소드를 지운다 (edu2-3 이 부른다) (미리보기 → 확인 → 실행)
#
#  사용:
#    bash _drop.sh blue_a1 3,5,6,8      # 에피소드를 직접 지정
#    bash _drop.sh blue_a1 --capped     # 시간상한에 걸린 에피소드를 골라준다
#    bash _drop.sh yellow_a3 --broken   # 영상↔데이터가 어긋난 에피소드
#    bash _drop.sh blue_a1 --capped --broken   # 둘 다 (합집합)
#    bash _drop.sh blue_a1 --capped --except 9
#    bash _drop.sh blue_a1 3,5 --dry-run   # 미리보기만
#    bash _drop.sh blue_a1 3,5 --yes       # 확인 건너뛰기
#
#  ⚠ 참가자가 직접 부르지 않는다 — edu2-3 이 확인을 받은 뒤 부른다.
#
#  하는 일
#    lerobot-edit-dataset 의 delete_episodes 를 **제자리 편집**으로 돌린다.
#    원본은 <세션>_old 로 자동 백업되고, 남은 에피소드는 0부터 다시 번호가 매겨진다.
#    지운 뒤 이어서 녹화할 명령을 task 문장까지 채워서 출력한다.
#
#  ⚠ 되돌리기 어려운 작업이라 **반드시 미리보기를 보여주고 y/N 을 받는다.**
#    자동 가드(hooks/guard.sh)는 rm·mv 만 보므로 이 경로는 걸리지 않는다.
#    확인 절차가 이 스크립트 안에 있어야 하는 이유다.
# =============================================================================

set -euo pipefail

# 같은 폴더의 config.sh 에서 값을 받는다 — 폴더째 옮겨도 돈다.
_SELF_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck disable=SC1091
source "$_SELF_DIR/config.sh"
BASE="${DROP_BASE:-$LEROBOT_HOME/data}"

usage() {
    # 주석 표시를 벗긴다. 빈 주석줄(`#` 하나)도 빈 줄이 되게 두 단계로 자른다
    sed -n '3,19p' "$0" | sed -e 's/^#//' -e 's/^  //'
    exit "${1:-2}"
}

[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage 0 ;; esac

NAME="$1"; shift

SPEC=""        # 직접 지정한 인덱스
CAPPED=0       # 시간상한에 걸린 에피소드 자동 선택
BROKEN=0       # 영상 구간 ↔ 데이터 행 수가 어긋난 에피소드 자동 선택
EXCEPT=""      # 그중 빼둘 인덱스
DRY=0
YES=0
while [ $# -gt 0 ]; do
    case "$1" in
        --capped)  CAPPED=1 ;;
        --broken)  BROKEN=1 ;;
        --except)  shift; EXCEPT="${1:?--except 뒤에 인덱스가 필요하다}" ;;
        --dry-run) DRY=1 ;;
        --yes|-y)  YES=1 ;;
        -h|--help) usage 0 ;;
        -*)        echo "❌ 모르는 옵션 : $1" >&2; usage ;;
        *)         SPEC="$1" ;;
    esac
    shift
done

if [ -z "$SPEC" ] && [ "$CAPPED" -eq 0 ] && [ "$BROKEN" -eq 0 ]; then
    echo "❌ 삭제할 에피소드 미지정 — 번호를 입력하거나 --capped · --broken 을 사용하세요." >&2
    usage
fi

# 이름꼬리(blue_a1)로도, 폴더 이름 그대로(so101_drum3_blue_a1)로도 받는다
if   [ -d "$BASE/$NAME" ];               then ROOT="$BASE/$NAME"
elif [ -d "$BASE/so101_drum3_$NAME" ];   then ROOT="$BASE/so101_drum3_$NAME"
else
    echo "❌ 세션 없음 : $NAME" >&2
    echo "   있는 것 :" >&2
    ls -1 "$BASE" 2>/dev/null | sed 's/^/     /' >&2
    exit 1
fi

# shellcheck disable=SC1091
source "$_SELF_DIR/_env.sh"; edu_activate || exit 1

PLAN="$(mktemp)"
trap 'rm -f "$PLAN"' EXIT

# ── 미리보기 ────────────────────────────────────────────────────────────────
ROOT="$ROOT" SPEC="$SPEC" CAPPED="$CAPPED" BROKEN="$BROKEN" EXCEPT="$EXCEPT" PLAN="$PLAN" python3 <<'PY'
import os, json, glob, re, sys
from pathlib import Path
import pandas as pd

root   = Path(os.environ["ROOT"])
spec   = os.environ["SPEC"]
capped = os.environ["CAPPED"] == "1"
broken = os.environ["BROKEN"] == "1"
excep  = os.environ["EXCEPT"]
plan   = os.environ["PLAN"]

def parse(s):
    return sorted({int(x) for x in re.findall(r"\d+", s)})

info = json.load(open(root / "meta" / "info.json"))
fps  = info["fps"]
df = pd.concat(
    [pd.read_parquet(p) for p in sorted(glob.glob(str(root / "meta/episodes/**/*.parquet"), recursive=True))]
).sort_values("episode_index")

lengths = {int(r.episode_index): int(r.length) for _, r in df.iterrows()}
tasks   = sorted({t for _, r in df.iterrows() for t in list(r.tasks)})

# 영상 구간(초 → 프레임)과 데이터 행 수의 차이. 0 이 아니면 어긋난 에피소드다.
# 이어서 녹화·재녹화 중 취소된 시도의 영상 프레임이 인코더에 남고 데이터만 버려지면 생긴다.
vkeys = [k for k in info["features"] if k.startswith("observation.images.")]
gap = {}
for _, r in df.iterrows():
    i, n = int(r.episode_index), int(r.length)
    d = 0
    for k in vkeys:
        seg = round((float(r[f"videos/{k}/to_timestamp"]) - float(r[f"videos/{k}/from_timestamp"])) * fps)
        if abs(seg - n) > abs(d):
            d = seg - n
    gap[i] = d if abs(d) > 1 else 0

# 시간상한 판정 : 최대 길이를 두 에피소드 이상이 정확히 공유하면 그게 상한이다
# (자연히 끝낸 에피소드는 → / n 로 넘겨서 어중간한 값이 나온다)
mx = max(lengths.values())
cap = mx if list(lengths.values()).count(mx) >= 2 else None

# 선택자를 여러 개 주면 합집합이다. 하나가 빈손이어도 바로 죽이지 않는다 —
# --capped --broken 처럼 섞어 쓸 때 한쪽만 걸리는 게 정상이라서다.
target, notes = set(parse(spec)) if spec else set(), []
if capped:
    if cap is None:
        notes.append("--capped : 시간상한에 걸린 에피소드 없음")
    else:
        target |= {i for i, n in lengths.items() if n == cap}
if broken:
    hit = {i for i, d in gap.items() if d}
    if not hit:
        notes.append("--broken : 어긋난 에피소드 없음")
    else:
        target |= hit
target = sorted(target)

if excep:
    target = [i for i in target if i not in parse(excep)]

bad = [i for i in target if i not in lengths]
if bad:
    sys.exit(f"❌ 없는 에피소드 : {bad}  (있는 것 0~{max(lengths)})")
if not target:
    sys.exit("❌ 삭제할 에피소드 없음" + ("\n   " + "\n   ".join(notes) if notes else ""))
for note in notes:
    print(f"  ※ {note}")
if len(target) >= len(lengths):
    sys.exit("❌ 전체 삭제 불가 — 데이터셋 폴더를 직접 삭제하세요.")

W = 68
print()
print("━" * W)
print(f"  {root.name}   현재 에피소드 {info['total_episodes']}개 / {info['total_frames']:,}프레임 · {fps}fps")
if cap:
    print(f"  시간상한 {cap}프레임 ({cap/fps:.2f}초) — 에피소드 {list(lengths.values()).count(cap)}개 해당")
nbroken = sum(1 for d in gap.values() if d)
if nbroken:
    print(f"  ⚠ 영상↔데이터가 어긋난 에피소드 {nbroken}개 — 영상과 동작이 어긋난 채 학습됩니다")
print("━" * W)
# 목록을 보여줄 범위 — 뷰어에서 세션 하나만 열었으면 그 세션만 보여준다.
# ⚠ 지우는 대상(target)은 좁히지 않는다. 화면에 안 보여도 지정되면 지워진다.
_lo, _hi = os.environ.get("LIST_LO", ""), os.environ.get("LIST_HI", "")
show = sorted(lengths)
if _lo and _hi:
    lo, hi = int(_lo), int(_hi)
    show = [i for i in show if lo <= i <= hi]
    outside = [i for i in target if not (lo <= i <= hi)]
    print(f"  세션 ep {lo}~{hi} 표시 (전체 {len(lengths)}개)")
    if outside:
        print(f"  ⚠ 이 범위 밖인데 삭제 대상으로 지정된 에피소드 : {outside}")
    print("━" * W)
for i in show:
    n = lengths[i]
    mark = "  ✘ 지움" if i in target else ""
    tag  = ""
    if cap and n == cap:
        tag += " ←상한"
    if gap[i]:
        tag += f" ←어긋남 {gap[i]:+d}"
    print(f"   ep{i:<2d} {n:4d}프레임  {n/fps:5.2f}초{tag}{mark}")
print("━" * W)
keep = [i for i in sorted(lengths) if i not in target]
print(f"  삭제 {len(target)}개 {target}   →   남음 {len(keep)}개 (0~{len(keep)-1} 로 재번호)")

backup = root.with_name(root.name + "_old")
if backup.exists():
    print(f"  ⚠ 기존 백업 {backup.name} 은 삭제되고 새 백업으로 대체됩니다")
else:
    print(f"  백업 : {backup.name} (자동 생성)")
print("━" * W)
print()

with open(plan, "w") as f:
    f.write(json.dumps({
        "indices": target,
        "n": len(target),
        "task": tasks[0] if len(tasks) == 1 else "",
        "tasks": tasks,
        "repo_id": f"data/{root.name}",
        "suffix": root.name.replace("so101_drum3_", ""),
    }))
PY

IDX=$(python3 -c "import json;print(json.load(open('$PLAN'))['indices'])")
NDEL=$(python3 -c "import json;print(json.load(open('$PLAN'))['n'])")
TASK=$(python3 -c "import json;print(json.load(open('$PLAN'))['task'])")
SUFFIX=$(python3 -c "import json;print(json.load(open('$PLAN'))['suffix'])")
REPO=$(python3 -c "import json;print(json.load(open('$PLAN'))['repo_id'])")

if [ "$DRY" -eq 1 ]; then
    echo "미리보기만 실행됨 (--dry-run). 실제로 삭제하려면 --dry-run 없이 다시 실행하세요."
    exit 0
fi

# ── 확인 ────────────────────────────────────────────────────────────────────
if [ "$YES" -eq 0 ]; then
    read -r -p "삭제할까요? [y/N] " ans
    case "$ans" in
        y|Y|yes|YES) ;;
        *) echo "취소됨 — 변경 사항 없음"; exit 0 ;;
    esac
fi

# ── 실행 ────────────────────────────────────────────────────────────────────
LD_LIBRARY_PATH="$CONDA_PREFIX/lib" lerobot-edit-dataset \
    --repo_id="$REPO" --root="$ROOT" \
    --new_repo_id="$REPO" --new_root="$ROOT" \
    --operation.type delete_episodes \
    --operation.episode_indices "$IDX"

echo
echo "── 결과 ──"
ROOT="$ROOT" python3 - <<'PY'
import os, json, glob
from pathlib import Path
import pandas as pd
root = Path(os.environ["ROOT"])
info = json.load(open(root / "meta" / "info.json"))
df = pd.concat(
    [pd.read_parquet(p) for p in sorted(glob.glob(str(root / "meta/episodes/**/*.parquet"), recursive=True))]
).sort_values("episode_index")
print(f"  에피소드 {info['total_episodes']}개 / {info['total_frames']:,}프레임")
print("  길이 :", [int(r.length) for _, r in df.iterrows()])
PY

echo
echo "── 이어서 녹화 ──"
echo "  edu2-3               # 부족한 만큼 이어서 녹화 (--resume 자동)"
if [ -z "$TASK" ]; then
    echo "  ⚠ 이 세션은 task 문장이 여러 개라 자동으로 읽을 수 없습니다. 직접 지정하세요."
fi
echo
echo "  확인 : edu2-2"
echo "  ⚠ 백업 ${ROOT##*/}_old 가 남아 있습니다. 확인이 끝나면 삭제하세요."
