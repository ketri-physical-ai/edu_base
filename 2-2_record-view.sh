#!/usr/bin/env bash
# 2-2 · 녹화 내용 확인 — 녹화한 에피소드를 브라우저에서 하나씩 본다.
#      사용법 :  edu2-2            실제 녹화본 전체
#                edu2-2 --test     연습 녹화본
#                edu2-2 5          5번 에피소드만
#                edu2-2 3-6        3~6번 에피소드
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

ROOT="$EDU_ROOT"; LABEL="실제 녹화본"
ARGS=()
for a in "$@"; do
  case "$a" in
    --test) ROOT="$EDU_TEST_ROOT"; LABEL="연습 녹화본" ;;
    -y|--yes) ;;
    *) ARGS+=("$a") ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  echo "녹화본 없음: $ROOT" >&2
  echo "  → 먼저 edu2-1 또는 edu2-3 으로 녹화하세요." >&2
  exit 1
fi

banner "2-2 · 녹화 내용 확인 — $LABEL" \
        "$ROOT" \
        "Chrome 탭 열림 · 에피소드마다 해당 구간 반복 재생"

VIEW_BASE="$(dirname "$ROOT")" \
  bash "$EDU_DIR/_view.sh" "$(basename "$ROOT")" "${ARGS[@]+"${ARGS[@]}"}"
