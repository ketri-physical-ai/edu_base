#!/usr/bin/env bash
# 4-1 · 롤아웃 — 방금 학습한 모델로 실제 로봇팔을 구동한다.
#      리더암은 쓰지 않는다. 로봇이 혼자 움직인다.
#      ⚠ 처음 몇 초는 손을 팔 근처에 두고 언제든 끊을 준비를 한다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

if [[ ! -f "${CKPT%/}/config.json" ]]; then
  echo "체크포인트 없음: $CKPT" >&2
  echo "  → 먼저 edu3-1 로 학습하세요." >&2
  echo "  → 중간 체크포인트를 쓰려면 config.sh 의 CKPT 를 수정하세요." >&2
  echo "     (예: .../checkpoints/010000/pretrained_model)" >&2
  exit 1
fi

RTC_ARGS=()
if [[ "$INFERENCE_TYPE" == "rtc" ]]; then
  RTC_ARGS=(--inference.rtc.execution_horizon="$RTC_HORIZON" --interpolation_multiplier="$RTC_INTERP")
fi

banner "4-1 · 롤아웃 (방금 학습한 모델)" \
        "모델 : $CKPT  (회차 $RUN)" \
        "추론 : $INFERENCE_TYPE" \
        "과제 : $TASK" \
        "" \
        "원통 위치를 바꿔 가며 실패하는 위치를 기록하세요." \
        "종료 : Ctrl+C."

need_ports "$FOLLOWER_PORT"
gpu_guard

run_cmd lerobot-rollout \
  --strategy.type=base \
  --inference.type="$INFERENCE_TYPE" \
  "${RTC_ARGS[@]+"${RTC_ARGS[@]}"}" \
  --policy.path="$CKPT" \
  --robot.type=so101_follower \
  --robot.port="$FOLLOWER_PORT" \
  --robot.id="$FOLLOWER_ID" \
  --robot.cameras="$CAMERAS" \
  --task="$TASK" \
  --fps="$CAM_FPS" \
  --duration="$DURATION" \
  --display_data="$DISPLAY_DATA" \
  "${EXTRA[@]+"${EXTRA[@]}"}"

echo
echo "관찰 기록 :  $EDU_DIR/rollout-기록.md"
