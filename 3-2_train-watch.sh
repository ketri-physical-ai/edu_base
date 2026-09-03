#!/usr/bin/env bash
# 3-2 · 지표 확인 — 학습 손실 곡선을 브라우저 그래프로 본다.
#      학습이 도는 중에 켜도 된다. GPU 를 쓰지 않는다.
#      사용법 :  edu3-2              최신 로그, 20초마다 갱신
#                edu3-2 --once       한 번만 그린다
#                edu3-2 <로그파일>   특정 로그
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

FOLLOW="--follow"
LOGS=(); PASS=()
for a in "$@"; do
  case "$a" in
    --once) FOLLOW="" ;;
    -y|--yes) ;;
    -*) PASS+=("$a") ;;
    *) LOGS+=("$a") ;;
  esac
done

if [[ ${#LOGS[@]} -eq 0 ]]; then
  mapfile -t FOUND < <(ls -1t "$LOG_DIR/${OUT_NAME}"-*.log 2>/dev/null)
  if [[ ${#FOUND[@]} -eq 0 ]]; then
    echo "학습 로그가 없다: $LOG_DIR/${OUT_NAME}-*.log" >&2
    echo "  → 먼저 edu3-1 을 돌린다." >&2
    exit 1
  fi
  LOGS=("${FOUND[0]}")
fi

banner "3-2 · 지표 확인" \
        "로그 : ${LOGS[0]}" \
        "" \
        "loss 가 내려가면 배우고 있다는 뜻이다." \
        "곡선이 평평해지면 더 돌려도 크게 안 나아진다." \
        "${FOLLOW:+갱신이 멈추면 스스로 종료한다. Ctrl+C 로도 끝낸다.}"

bash "$EDU_DIR/_watch.sh" "${LOGS[@]}" "${PASS[@]+"${PASS[@]}"}" ${FOLLOW:+$FOLLOW}
