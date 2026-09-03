#!/usr/bin/env bash
# 3-1 · 학습 — 찍은 데이터로 정책을 만든다.
#      ⚠ 데이터를 더 찍은 뒤 다시 돌릴 때는 --resume 을 쓰지 않는다.
#         처음부터 새로 돌리고 출력 폴더 이름만 바꾼다 (OUT_NAME).
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

if [[ ! -f "$EDU_ROOT/meta/info.json" ]]; then
  echo "학습할 데이터가 없다: $EDU_ROOT" >&2
  echo "  → 먼저 edu2-3 을 돌린다." >&2
  exit 1
fi
EP="$(edu_meta "$EDU_ROOT/meta/info.json" total_episodes)"
FR="$(edu_meta "$EDU_ROOT/meta/info.json" total_frames)"
# 분당 스텝수는 config.sh 의 RATE_B8 / RATE_B16 에서 온다.
[[ "$BATCH_SIZE" -le 8 ]] && MIN=$(( STEPS / RATE_B8 )) || MIN=$(( STEPS / RATE_B16 ))
EPOCH="-"
[[ "${FR:-0}" -gt 0 ]] && EPOCH="$(awk -v s="$STEPS" -v b="$BATCH_SIZE" -v f="$FR" 'BEGIN{printf "%.1f", s*b/f}')"

banner "3-1 · 학습" \
        "데이터 : $EDU_REPO_ID  (${EP}편 · ${FR}프레임)" \
        "정책   : $POLICY_TYPE" \
        "스텝   : $STEPS · 배치 $BATCH_SIZE  → 약 ${EPOCH} 에폭" \
        "예상   : 약 ${MIN}분" \
        "출력   : $OUT_DIR  (회차 $RUN)" \
        "" \
        "학습이 도는 동안 GPU 를 쓰는 다른 작업을 띄우지 않는다."

gpu_guard

if [[ -d "$OUT_DIR" ]]; then
  echo
  echo "⚠ 출력 폴더가 이미 있다. lerobot 은 덮어쓰지 않고 오류를 낸다."
  echo "  1차 결과를 남기려면 회차를 올린다 :  RUN=2 edu3-1"
  echo "  (롤아웃도 같이 따라간다 :  RUN=2 edu4-1)"
  ask_delete "$OUT_DIR" "학습 출력" N || exit "$EDU_CANCEL"
fi

mkdir -p "$LOG_DIR"
EDU_LOG="${EDU_LOG:-$LOG_DIR/${OUT_NAME}-$(date +%Y%m%d-%H%M%S).log}"
echo "로그 : $EDU_LOG"

run_cmd lerobot-train \
  --policy.type="$POLICY_TYPE" \
  --policy.push_to_hub=false \
  --dataset.repo_id="$EDU_REPO_ID" \
  --dataset.root="$EDU_ROOT" \
  --output_dir="$OUT_DIR" \
  --steps="$STEPS" \
  --batch_size="$BATCH_SIZE" \
  --num_workers="$NUM_WORKERS" \
  --save_freq="$SAVE_FREQ" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
rc=$?
[[ $rc -eq 0 ]] || { echo; echo "학습이 정상 종료되지 않았다 (코드 $rc)."; exit "$rc"; }

echo
echo "지표를 보려면 :  edu3-2"
echo "굴려 보려면   :  edu4-1"
