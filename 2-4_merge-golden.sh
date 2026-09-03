#!/usr/bin/env bash
# 2-4 · 골든 데이터셋 합치기 — 미리 찍어 둔 기준 데이터를 이번 녹화본에 더한다.
#
#   골든(golden/) + 이번 녹화본(2-3)  →  병합본  →  그걸로 학습(3-1)
#
#   ⚠ 원본 둘은 건드리지 않는다. 새 데이터셋을 따로 만든다.
#     그 약속을 지키려고 아래 「겹침 검사」를 먼저 한다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

# ── 메타 읽기 : 값과 성공 여부를 나눠 돌려준다 ────────────────────
#   ⚠ 실패를 0·빈문자로 뭉개면 "둘 다 실패" 가 "둘이 같다" 로 보인다.
meta_num() {  # meta_num <루트> <키>  →  숫자만. 없거나 이상하면 실패(1)
  local v; v="$(edu_meta "$1/meta/info.json" "$2")"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$v"
}
cams() { python3 - "$1/meta/info.json" <<'PY' 2>/dev/null || return 1
import json,sys
i=json.load(open(sys.argv[1]))
k=[x for x in i["features"] if x.startswith("observation.images.")]
if not k: raise SystemExit(1)
print(",".join(sorted(f'{x[len("observation.images."):]}:'
                      f'{"x".join(map(str,i["features"][x].get("shape",[])))}' for x in k)))
PY
}
shapes() { python3 - "$1/meta/info.json" <<'PY' 2>/dev/null || return 1
import json,sys
i=json.load(open(sys.argv[1]))
f=i["features"]
if "observation.state" not in f or "action" not in f: raise SystemExit(1)
print(f'{i.get("robot_type","?")} state{f["observation.state"]["shape"]} action{f["action"]["shape"]}')
PY
}
task() { python3 - "$1" <<'PY' 2>/dev/null || return 1
import glob,sys,pandas as pd
f=sorted(glob.glob(sys.argv[1]+"/meta/tasks*"))
if not f: raise SystemExit(1)
d=pd.read_parquet(f[0])
col="task" if "task" in d.columns else (d.index.name or None)
v=sorted(set(d[col].tolist() if col in d.columns else d.index.tolist()))
if not v: raise SystemExit(1)
print(" | ".join(v))
PY
}

banner "2-4 · 골든 데이터셋 합치기" \
        "골든 + 이번 녹화본  →  병합본 (원본은 그대로 둔다)"

# ── 있는가 ────────────────────────────────────────────────────────
if [[ ! -f "$GOLDEN_ROOT/meta/info.json" ]]; then
  echo "  골든 데이터셋이 아직 없다."
  echo "    두는 자리 : $GOLDEN_ROOT"
  echo "    lerobot 데이터셋 폴더를 통째로 그 이름으로 넣는다."
  echo "    (이름을 바꾸려면 config.sh 의 GOLDEN_NAME)"
  exit 1
fi
[[ -f "$EDU_ROOT/meta/info.json" ]] || {
  echo "  이번 녹화본이 없다: $EDU_ROOT"; echo "    → 먼저 edu2-3 으로 찍는다."; exit 1; }

# ── 겹침 검사 : 출력이 입력과 같거나 그 안이면 무조건 멈춘다 ──────
#   이게 없으면 MERGED_ROOT 를 원본으로 덮어썼을 때 "옛 병합본을 지울까?" 로
#   원본을 지우게 된다. 화면은 "원본은 그대로 둔다" 라고 하는데도.
_rp() { readlink -m -- "$1"; }
MR="$(_rp "$MERGED_ROOT")"; ER="$(_rp "$EDU_ROOT")"; GR="$(_rp "$GOLDEN_ROOT")"
for pair in "$ER:이번 녹화본" "$GR:골든"; do
  src="${pair%%:*}"; who="${pair##*:}"
  if [[ "$MR" == "$src" || "$MR" == "$src"/* || "$src" == "$MR"/* ]]; then
    echo "  ✘ 병합본 자리가 $who 과 겹친다 — 원본이 지워질 수 있어 멈춘다." >&2
    echo "      병합본 : $MR" >&2
    echo "      $who   : $src" >&2
    echo "    config.sh 의 MERGED_NAME 을 다른 이름으로 바꾼다." >&2
    exit 1
  fi
done
[[ "$ER" == "$GR" ]] && { echo "  ✘ 골든과 녹화본이 같은 폴더다 — 합칠 것이 없다." >&2; exit 1; }

# ── 대조 ──────────────────────────────────────────────────────────
echo
echo "  ── 대조 ─────────────────────────────────────────"
BAD=0
chk() {  # chk <항목> <골든값> <녹화본값> [읽기실패여부]
  if [[ -z "$2" || -z "$3" ]]; then
    printf '    %-12s ✘ 읽지 못했다 (메타가 깨졌거나 형식이 다르다)\n' "$1"; BAD=1
  elif [[ "$2" == "$3" ]]; then printf '    %-12s %s\n' "$1" "$2"
  else printf '    %-12s ✘ 골든[%s]  ≠  녹화본[%s]\n' "$1" "$2" "$3"; BAD=1; fi
}
chk fps      "$(meta_num "$GOLDEN_ROOT" fps || true)"  "$(meta_num "$EDU_ROOT" fps || true)"
chk 카메라   "$(cams "$GOLDEN_ROOT" || true)"          "$(cams "$EDU_ROOT" || true)"
chk 로봇·차원 "$(shapes "$GOLDEN_ROOT" || true)"        "$(shapes "$EDU_ROOT" || true)"
chk 과제문장 "$(task "$GOLDEN_ROOT" || true)"          "$(task "$EDU_ROOT" || true)"

# ── 카메라 시점이 실제로 같은가 (이름만으로는 못 잡는다) ──────────
#   이름이 top·wrist 로 같아도 물리적으로 반대로 꽂혀 찍혔으면
#   같은 키에 다른 시점이 들어간다. 학습이 조용히 망가진다.
if [[ "${SKIP_CAMVIEW:-0}" != "1" ]]; then
  GT="$(python3 "$EDU_DIR/_camview.py" dataset "$GOLDEN_ROOT" 2>/dev/null | sed -n 's/^SUGGEST_TOP=//p')"
  ET="$(python3 "$EDU_DIR/_camview.py" dataset "$EDU_ROOT"    2>/dev/null | sed -n 's/^SUGGEST_TOP=//p')"
  if [[ -n "$GT" && -n "$ET" ]]; then
    if [[ "$GT" == "$ET" ]]; then printf '    %-12s 화면으로도 같다 (넓은 쪽 = %s)\n' "카메라 시점" "$GT"
    else
      printf '    %-12s ✘ 넓은 화면이 골든[%s] · 녹화본[%s] — 카메라가 뒤바뀐 것 같다\n' "카메라 시점" "$GT" "$ET"
      echo "      같은 이름에 다른 시점이 들어가 학습이 망가진다."
      echo "      edu1-2 로 화면을 보고 config.sh 의 CAM_TOP·CAM_WRIST 를 바로잡은 뒤 다시 찍는다."
      BAD=1
    fi
  fi
fi
echo "  ─────────────────────────────────────────────────"
(( BAD )) && { echo "  ✘ 맞지 않는 항목이 있다 — 합치면 데이터가 어긋난다."; exit 1; }

GN=$(meta_num "$GOLDEN_ROOT" total_episodes) || { echo "  골든 편수를 못 읽었다"; exit 1; }
GF=$(meta_num "$GOLDEN_ROOT" total_frames)   || { echo "  골든 프레임을 못 읽었다"; exit 1; }
EN=$(meta_num "$EDU_ROOT"    total_episodes) || { echo "  녹화본 편수를 못 읽었다"; exit 1; }
EF=$(meta_num "$EDU_ROOT"    total_frames)   || { echo "  녹화본 프레임을 못 읽었다"; exit 1; }

# ── 미리보기 ──────────────────────────────────────────────────────
echo
echo "  ── 합칠 내용 ────────────────────────────────────"
printf '    골든    %4s편 %8s프레임   %s\n' "$GN" "$GF" "$GR"
printf '    녹화본  %4s편 %8s프레임   %s\n' "$EN" "$EF" "$ER"
printf '    ────────────────────────────────────────────\n'
printf '    병합본  %4s편 %8s프레임   %s\n' "$((GN+EN))" "$((GF+EF))" "$MR"
echo "  ─────────────────────────────────────────────────"
echo "    원본 둘은 그대로 둔다 (겹침 검사 통과)."

if [[ -d "$MERGED_ROOT" ]]; then
  echo
  echo "  ⚠ 병합본이 이미 있다 : $MR"
  ask_delete "$MERGED_ROOT" "옛 병합본" N || { echo "  그대로 두고 멈춘다."; exit "$EDU_CANCEL"; }
fi

# ── 리스트 인자는 파이썬으로 만든다 (따옴표 사고 방지) ────────────
IDS="$(python3 -c 'import sys;print(str([sys.argv[1],sys.argv[2]]))' "$GOLDEN_NAME" "$EDU_REPO_ID")"
ROOTS="$(python3 -c 'import sys;print(str([sys.argv[1],sys.argv[2]]))' "$GR" "$ER")"

run_cmd lerobot-edit-dataset \
  --operation.type=merge \
  --operation.repo_ids="$IDS" \
  --operation.roots="$ROOTS" \
  --new_repo_id="$MERGED_REPO_ID" \
  --new_root="$MERGED_ROOT" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
rc=$?
(( rc == 0 )) || { echo; echo "병합이 실패했다 (코드 $rc)."; exit "$rc"; }
[[ -f "$MERGED_ROOT/meta/info.json" ]] || { echo "병합본이 만들어지지 않았다."; exit 1; }

# ── 병합 index 교정 ───────────────────────────────────────────────
# lerobot 0.6.x 버그 : 병합 결과의 file_index 가 없는 파일을 가리켜,
# 그 데이터셋을 **다시 병합 소스로 쓰면** 죽는다. 학습에는 지장 없다.
echo
echo "── 병합 index 교정 ──"
FIXOK=1
python3 "$EDU_DIR/_fixmerge.py" "$MERGED_ROOT" || FIXOK=0

echo
echo "── 자리 바꾸기 ──"
# 합본이 녹화본 이름을 차지하고, 원래 녹화본은 _old 로 밀어 둔다.
#   그래야 edu3-1 을 그냥 칠 수 있다 (긴 경로를 안 친다).
#   _drop.sh 가 판을 지울 때 쓰는 방식과 같다.
OLD_ROOT="${ER}_old"
if [[ -e "$OLD_ROOT" ]]; then
  echo "  ⚠ 이미 있다 : $OLD_ROOT"
  ask_delete "$OLD_ROOT" "옛 백업" N || { echo "  자리 바꾸기를 멈춘다 — 합본은 $MR 에 그대로 있다."; exit "$EDU_CANCEL"; }
fi
echo "  $ER"
echo "    → $OLD_ROOT            (원래 녹화본을 밀어 둔다)"
echo "  $MR"
echo "    → $ER   (합본이 그 이름을 차지한다)"
if [[ "${EDU_YES:-0}" != "1" ]]; then
  read -r -p "  자리를 바꿀까? [Y/n] " a || a=n
  [[ -z "$a" || "$a" =~ ^[Yy]$ ]] || {
    echo "  바꾸지 않았다. 합본은 여기 있다 : $MR"
    echo "  그걸로 학습하려면 :"
    echo "    EDU_REPO_ID='$MERGED_REPO_ID' EDU_ROOT='$MR' RUN=2 edu3-1"
    exit 0; }
fi
mv -- "$ER" "$OLD_ROOT" && mv -- "$MERGED_ROOT" "$ER" || {
  echo "  ✘ 자리 바꾸기 실패 — 손으로 확인한다." >&2; exit 1; }
echo "  바꿨다."

echo
echo "── 결과 ──"
printf '  %-14s %s편   %s\n' "골든(그대로)"  "$GN" "$GR"
printf '  %-14s %s편   %s\n' "녹화본_old"   "$EN" "$OLD_ROOT"
printf '  %-14s %s편   %s\n' "녹화본(합본)" \
  "$(meta_num "$EDU_ROOT" total_episodes || echo '?')" "$ER"
if (( ! FIXOK )); then
  echo
  echo "  ⚠ index 교정을 못 했다 — **학습은 되지만** 이 합본을"
  echo "     다시 병합 소스로 쓰면 실패할 수 있다."
fi

echo
echo "이름이 그대로라 다음은 이렇게만 하면 된다 :"
echo "  RUN=2 edu3-1      학습"
echo "  edu2-2            확인"
echo
echo "되돌리려면 :"
echo "  mv '$ER' '$MR' && mv '$OLD_ROOT' '$ER'"
