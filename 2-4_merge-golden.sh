#!/usr/bin/env bash
# 2-4 · 골든 데이터셋 병합 — 미리 녹화해 둔 기준 데이터를 이번 녹화본에 더한다.
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

banner "2-4 · 골든 데이터셋 병합" \
        "골든 + 이번 녹화본  →  병합본 (원본은 그대로 둔다)"

# ── 있는가 ────────────────────────────────────────────────────────
if [[ ! -f "$GOLDEN_ROOT/meta/info.json" ]]; then
  echo "  골든 데이터셋 없음"
  echo "    위치 : $GOLDEN_ROOT"
  echo "    lerobot 데이터셋 폴더를 위 위치에 복사하세요."
  echo "    (이름을 바꾸려면 config.sh 의 GOLDEN_NAME)"
  exit 1
fi
[[ -f "$EDU_ROOT/meta/info.json" ]] || {
  echo "  녹화본 없음: $EDU_ROOT"; echo "    → 먼저 edu2-3 으로 녹화하세요."; exit 1; }

# ── 겹침 검사 : 출력이 입력과 같거나 그 안이면 무조건 멈춘다 ──────
#   이게 없으면 MERGED_ROOT 를 원본으로 덮어썼을 때 "옛 병합본을 지울까?" 로
#   원본을 지우게 된다. 화면은 "원본은 그대로 둔다" 라고 하는데도.
_rp() { readlink -m -- "$1"; }
MR="$(_rp "$MERGED_ROOT")"; ER="$(_rp "$EDU_ROOT")"; GR="$(_rp "$GOLDEN_ROOT")"
for pair in "$ER:이번 녹화본" "$GR:골든"; do
  src="${pair%%:*}"; who="${pair##*:}"
  if [[ "$MR" == "$src" || "$MR" == "$src"/* || "$src" == "$MR"/* ]]; then
    echo "  ✘ 병합본 경로가 $who 과 겹침 — 원본 삭제 위험으로 중단" >&2
    echo "      병합본 : $MR" >&2
    echo "      $who   : $src" >&2
    echo "    config.sh 의 MERGED_NAME 을 다른 이름으로 바꾸세요." >&2
    exit 1
  fi
done
[[ "$ER" == "$GR" ]] && { echo "  ✘ 골든과 녹화본이 같은 폴더 — 병합 불가" >&2; exit 1; }

# ── 대조 ──────────────────────────────────────────────────────────
echo
echo "  ── 대조 ─────────────────────────────────────────"
BAD=0
chk() {  # chk <항목> <골든값> <녹화본값> [읽기실패여부]
  if [[ -z "$2" || -z "$3" ]]; then
    printf '    %-12s ✘ 읽기 실패 (메타 손상 또는 형식 불일치)\n' "$1"; BAD=1
  elif [[ "$2" == "$3" ]]; then printf '    %-12s %s\n' "$1" "$2"
  else printf '    %-12s ✘ 골든[%s]  ≠  녹화본[%s]\n' "$1" "$2" "$3"; BAD=1; fi
}
chk fps      "$(meta_num "$GOLDEN_ROOT" fps || true)"  "$(meta_num "$EDU_ROOT" fps || true)"
chk 카메라   "$(cams "$GOLDEN_ROOT" || true)"          "$(cams "$EDU_ROOT" || true)"
chk 로봇·차원 "$(shapes "$GOLDEN_ROOT" || true)"        "$(shapes "$EDU_ROOT" || true)"
chk 과제문장 "$(task "$GOLDEN_ROOT" || true)"          "$(task "$EDU_ROOT" || true)"

# ── 카메라 시점이 실제로 같은가 (이름만으로는 못 잡는다) ──────────
#   이름이 top·wrist 로 같아도 물리적으로 반대로 꽂힌 채 녹화됐으면
#   같은 키에 다른 시점이 들어간다. 학습이 조용히 망가진다.
if [[ "${SKIP_CAMVIEW:-0}" != "1" ]]; then
  GT="$(python3 "$EDU_DIR/_camview.py" dataset "$GOLDEN_ROOT" 2>/dev/null | sed -n 's/^SUGGEST_TOP=//p')"
  ET="$(python3 "$EDU_DIR/_camview.py" dataset "$EDU_ROOT"    2>/dev/null | sed -n 's/^SUGGEST_TOP=//p')"
  if [[ -n "$GT" && -n "$ET" ]]; then
    if [[ "$GT" == "$ET" ]]; then printf '    %-12s 일치 (넓은 화면 = %s)\n' "카메라 시점" "$GT"
    else
      printf '    %-12s ✘ 넓은 화면 불일치 골든[%s] · 녹화본[%s] — 카메라 뒤바뀜 의심\n' "카메라 시점" "$GT" "$ET"
      echo "      이대로 병합하면 시점이 섞여 학습이 실패합니다."
      echo "      edu1-2 로 화면을 확인하고 config.sh 의 CAM_TOP·CAM_WRIST 를 수정한 뒤 다시 녹화하세요."
      BAD=1
    fi
  fi
fi
echo "  ─────────────────────────────────────────────────"
(( BAD )) && { echo "  ✘ 불일치 항목 있음 — 병합하면 데이터가 어긋납니다."; exit 1; }

GN=$(meta_num "$GOLDEN_ROOT" total_episodes) || { echo "  골든 에피소드 수 읽기 실패"; exit 1; }
GF=$(meta_num "$GOLDEN_ROOT" total_frames)   || { echo "  골든 프레임 수 읽기 실패"; exit 1; }
EN=$(meta_num "$EDU_ROOT"    total_episodes) || { echo "  녹화본 에피소드 수 읽기 실패"; exit 1; }
EF=$(meta_num "$EDU_ROOT"    total_frames)   || { echo "  녹화본 프레임 수 읽기 실패"; exit 1; }

# ── 미리보기 ──────────────────────────────────────────────────────
echo
echo "  ── 병합 내용 (에피소드 수 · 프레임 수) ──────────"
printf '    골든    %4s개 %8s프레임   %s\n' "$GN" "$GF" "$GR"
printf '    녹화본  %4s개 %8s프레임   %s\n' "$EN" "$EF" "$ER"
printf '    ────────────────────────────────────────────\n'
printf '    병합본  %4s개 %8s프레임   %s\n' "$((GN+EN))" "$((GF+EF))" "$MR"
echo "  ─────────────────────────────────────────────────"
echo "    원본 2개 변경 없음 (겹침 검사 통과)"

if [[ -d "$MERGED_ROOT" ]]; then
  echo
  echo "  ⚠ 기존 병합본 있음 : $MR"
  ask_delete "$MERGED_ROOT" "옛 병합본" N || { echo "  변경 없이 중단"; exit "$EDU_CANCEL"; }
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
(( rc == 0 )) || { echo; echo "병합 실패 (코드 $rc)"; exit "$rc"; }
[[ -f "$MERGED_ROOT/meta/info.json" ]] || { echo "병합본 생성 실패"; exit 1; }

# ── 병합 index 교정 ───────────────────────────────────────────────
# lerobot 0.6.x 버그 : 병합 결과의 file_index 가 없는 파일을 가리켜,
# 그 데이터셋을 **다시 병합 소스로 쓰면** 죽는다. 학습에는 지장 없다.
echo
echo "── 병합 index 교정 ──"
FIXOK=1
python3 "$EDU_DIR/_fixmerge.py" "$MERGED_ROOT" || FIXOK=0

echo
echo "── 이름 교체 ──"
# 병합본이 녹화본 이름을 쓰고, 원래 녹화본은 _old 로 백업한다.
#   그래야 edu3-1 을 그냥 칠 수 있다 (긴 경로를 안 친다).
#   _drop.sh 가 에피소드를 지울 때 쓰는 방식과 같다.
OLD_ROOT="${ER}_old"
if [[ -e "$OLD_ROOT" ]]; then
  echo "  ⚠ 기존 백업 있음 : $OLD_ROOT"
  ask_delete "$OLD_ROOT" "옛 백업" N || { echo "  이름 교체 중단 — 병합본 위치 : $MR"; exit "$EDU_CANCEL"; }
fi
echo "  $ER"
echo "    → $OLD_ROOT            (원래 녹화본 백업)"
echo "  $MR"
echo "    → $ER   (병합본이 이 이름을 쓴다)"
if [[ "${EDU_YES:-0}" != "1" ]]; then
  read -r -p "  이름 교체? [Y/n] " a || a=n
  [[ -z "$a" || "$a" =~ ^[Yy]$ ]] || {
    echo "  교체 안 함. 병합본 위치 : $MR"
    echo "  병합본으로 학습 · 롤아웃 :"
    echo "    EDU_REPO_ID='$MERGED_REPO_ID' EDU_ROOT='$MR' RUN=2 edu3-1"
    echo "    RUN=2 edu4-1"
    exit 0; }
fi
mv -- "$ER" "$OLD_ROOT" && mv -- "$MERGED_ROOT" "$ER" || {
  echo "  ✘ 이름 교체 실패 — 폴더 상태를 직접 확인하세요." >&2; exit 1; }
echo "  교체 완료."

echo
echo "── 결과 ──"
printf '  %-14s %s개   %s\n' "골든(그대로)"  "$GN" "$GR"
printf '  %-14s %s개   %s\n' "녹화본_old"   "$EN" "$OLD_ROOT"
printf '  %-14s %s개   %s\n' "녹화본(병합본)" \
  "$(meta_num "$EDU_ROOT" total_episodes || echo '?')" "$ER"
if (( ! FIXOK )); then
  echo
  echo "  ⚠ index 교정 실패 — 학습에는 문제없지만, 이 병합본을"
  echo "     다시 병합에 쓰면 실패할 수 있습니다."
fi

echo
echo "다음 단계 (데이터셋 이름이 같아 경로 지정 불필요) :"
echo "  edu2-2            확인"
echo "  RUN=2 edu3-1      학습 (1차 결과 act_edu_r1 유지)"
echo "  RUN=2 edu4-1      롤아웃 — ⚠ RUN=2 를 빼면 1차 모델이 실행됩니다"
echo
echo "되돌리려면 :"
echo "  mv '$ER' '$MR' && mv '$OLD_ROOT' '$ER'"
