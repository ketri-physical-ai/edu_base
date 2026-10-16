#!/usr/bin/env bash
# 3-2 · 지표 확인 — 학습 손실 곡선을 브라우저 그래프로 본다.
#      학습이 도는 중에 켜도 된다. GPU 를 쓰지 않는다.
#      사용법 :  edu3-2              최신 로그, 20초마다 갱신
#                edu3-2 --once       한 번만 그린다
#                edu3-2 <로그파일>   특정 로그
#                edu3-2 --golden     골든 모델을 만든 학습의 기준 곡선
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"

FOLLOW="--follow"
GOLDEN=0
LOGS=(); PASS=()
for a in "$@"; do
  case "$a" in
    --once) FOLLOW="" ;;
    --golden) GOLDEN=1; FOLLOW="" ;;
    -y|--yes) ;;
    -*) PASS+=("$a") ;;
    *) LOGS+=("$a") ;;
  esac
done

# 골든 곡선은 이미 끝난 학습이다 — 따라갈 게 없으므로 --follow 를 켜지 않는다.
if [[ "$GOLDEN" -eq 1 && ${#LOGS[@]} -eq 0 ]]; then
  if [[ -n "${GOLDEN_LOG:-}" && -f "$GOLDEN_LOG" ]]; then
    LOGS=("$GOLDEN_LOG")
  else
    echo "골든 학습 로그 없음: ${GOLDEN_LOG:-(미지정)}" >&2
    echo "  → config.sh 의 GOLDEN_LOG 를 확인하세요." >&2
    exit 1
  fi
fi

if [[ ${#LOGS[@]} -eq 0 ]]; then
  mapfile -t FOUND < <(ls -1t "$LOG_DIR/${OUT_NAME}"-*.log 2>/dev/null)
  if [[ ${#FOUND[@]} -eq 0 ]]; then
    echo "학습 로그 없음: $LOG_DIR/${OUT_NAME}-*.log" >&2
    echo "  → 먼저 edu3-1 로 학습하세요." >&2
    exit 1
  fi
  LOGS=("${FOUND[0]}")
fi

banner "3-2 · 지표 확인" \
        "로그 : ${LOGS[0]}" \
        "" \
        "loss 가 내려가면 배우고 있다는 뜻이다." \
        "곡선이 평평해지면 더 돌려도 크게 안 나아진다." \
        "${FOLLOW:+갱신이 멈추면 자동 종료 · 수동 종료 : Ctrl+C}"

bash "$EDU_DIR/_watch.sh" "${LOGS[@]}" "${PASS[@]+"${PASS[@]}"}" ${FOLLOW:+$FOLLOW}
