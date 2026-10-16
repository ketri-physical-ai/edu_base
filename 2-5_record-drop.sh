#!/usr/bin/env bash
# 2-5 · 에피소드 삭제 — edu2-2 로 확인한 에피소드를 녹화본에서 지운다.
#      사용법 :  edu2-5              오류 후보를 보고 번호 입력
#                edu2-5 3,17,42      바로 지정
#                edu2-5 3-6          3~6번
#                edu2-5 --test       연습 녹화본
#
#   실제 삭제는 _drop.sh 가 한다 (미리보기 → y/N → <녹화본>_old 백업 → 재번호).
#   ⚠ 지우면 뒤 번호가 앞으로 당겨진다. 지울 번호는 한 번에 모두 넣는다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

ROOT="$EDU_ROOT"; LABEL="실제 녹화본"; SPEC=""
for a in "$@"; do
  case "$a" in
    --test) ROOT="$EDU_TEST_ROOT"; LABEL="연습 녹화본" ;;
    -y|--yes) ;;
    *) SPEC+="${SPEC:+,}$a" ;;
  esac
done

if [[ ! -f "$ROOT/meta/info.json" ]]; then
  echo "녹화본 없음: $ROOT" >&2
  echo "  → 먼저 edu2-1 또는 edu2-3 으로 녹화하세요." >&2
  exit 1
fi

TOTAL_EP="$(edu_meta "$ROOT/meta/info.json" total_episodes)"
banner "2-5 · 에피소드 삭제 — $LABEL (${TOTAL_EP}개)" \
        "$ROOT" \
        "삭제 전 자동 백업 : $(basename "$ROOT")_old"

# ── 병합본 확인 ──────────────────────────────────────────────────
#   edu2-4 를 거치면 병합본이 녹화본 이름을 쓰고, 원래 녹화본은 _old 에 있다.
#   녹화본 + 골든 = 현재 개수 이면 병합본으로 본다.
#   이때 지우면 골든 에피소드까지 대상이 되고, _old(원래 녹화본 백업)가 새 백업으로 바뀐다.
OLD_ROOT="${ROOT}_old"
if [[ "$ROOT" == "$EDU_ROOT" && -f "$OLD_ROOT/meta/info.json" && -f "$GOLDEN_ROOT/meta/info.json" ]]; then
  ON="$(edu_meta "$OLD_ROOT/meta/info.json" total_episodes)"
  GN="$(edu_meta "$GOLDEN_ROOT/meta/info.json" total_episodes)"
  if (( ON > 0 && GN > 0 && ON + GN == TOTAL_EP )); then
    echo
    echo "  ⚠ 골든 데이터와 병합된 녹화본입니다 (녹화 ${ON}개 + 골든 ${GN}개)."
    echo "    삭제하면 원래 녹화본 백업($(basename "$OLD_ROOT"))이 새 백업으로 대체됩니다."
    echo "    삭제는 edu2-4 병합 전에 하는 것이 원칙입니다."
    read -r -p "  계속할까요? [y/N] " a || a=n
    [[ "$a" =~ ^[Yy]$ ]] || { echo "  취소됨 — 변경 사항 없음"; exit "$EDU_CANCEL"; }
  fi
fi

# ── 번호 받기 ────────────────────────────────────────────────────
if [[ -z "$SPEC" ]]; then
  echo
  bash "$EDU_DIR/_scan.sh" "$ROOT" 2>/dev/null | grep -v '^FLAGGED=\|^NOTED='
  echo
  echo "  번호는 edu2-2 화면의 ep 번호입니다.  예) 3,17,42   3-6"
  echo "  ⚠ 지우면 뒤 번호가 당겨지므로 지울 번호를 한 번에 모두 입력하세요."
  read -r -p "  삭제할 에피소드 번호 [Enter=취소] : " SPEC || SPEC=""
fi
SPEC="${SPEC//[[:space:]]/}"
[[ -z "$SPEC" ]] && { echo "  취소됨 — 변경 사항 없음"; exit 0; }

# 3-6 같은 범위를 3,4,5,6 으로 푼다 — _drop.sh 는 숫자만 뽑으므로 3-6 을 3,6 으로 읽는다.
IDX=""
IFS=',' read -r -a PARTS <<< "$SPEC"
for p in "${PARTS[@]}"; do
  [[ -z "$p" ]] && continue
  if [[ "$p" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    lo="${BASH_REMATCH[1]}"; hi="${BASH_REMATCH[2]}"
    (( lo <= hi )) || { echo "  ✘ 범위 오류 : $p (앞 번호가 더 큽니다)" >&2; exit 1; }
    for ((i=lo; i<=hi; i++)); do IDX+="${IDX:+,}$i"; done
  elif [[ "$p" =~ ^[0-9]+$ ]]; then
    IDX+="${IDX:+,}$p"
  else
    echo "  ✘ 번호 형식 오류 : $p   (예: 3,17,42 또는 3-6)" >&2; exit 1
  fi
done

DROP_BASE="$(dirname "$ROOT")" bash "$EDU_DIR/_drop.sh" "$(basename "$ROOT")" "$IDX"
rc=$?
# 개수가 줄었을 때만 — 취소했으면 번호가 그대로다
if [[ "$(edu_meta "$ROOT/meta/info.json" total_episodes)" != "$TOTAL_EP" ]]; then
  echo
  echo "  ⓘ 번호가 다시 매겨졌습니다. 열려 있는 edu2-2 화면은 옛 번호입니다."
  echo "    다시 지우기 전에 edu2-2 를 다시 실행해 새 번호를 확인하세요."
fi
exit "$rc"
