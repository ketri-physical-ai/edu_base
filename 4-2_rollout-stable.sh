#!/usr/bin/env bash
# 4-2 · 안정본 롤아웃 — 미리 검증해 둔 모델로 실제 로봇팔을 구동한다.
#      당일 학습이 잘 안 나왔을 때의 대비책이자, 잘 된 결과의 본보기다.
#      ⚠ 쓰기 전에 config.sh 의 STABLE_CKPT 를 채운다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

if [[ -z "$STABLE_CKPT" ]]; then
  banner "4-2 · 안정본 미지정"
  echo "config.sh 의 STABLE_CKPT 를 아래 형식으로 설정하세요 :"
  echo
  echo '  STABLE_CKPT="$LEROBOT_HOME/outputs/train/<학습이름>/checkpoints/last/pretrained_model"'
  echo
  echo "사용 가능한 학습 결과 :"
  ls -1d "$LEROBOT_HOME"/outputs/train/*/checkpoints/last/pretrained_model 2>/dev/null \
    | sed "s|$LEROBOT_HOME/outputs/train/|  |" | head -20 || echo "  (없음)"
  echo
  echo "SmolVLA 계열이면 아래 값도 함께 수정하세요 :"
  echo "  STABLE_INFERENCE_TYPE=rtc"
  echo "  STABLE_RENAME_MAP='{\"observation.images.top\":\"observation.images.camera1\",\"observation.images.wrist\":\"observation.images.camera2\"}'"
  exit 1
fi

if [[ ! -f "${STABLE_CKPT%/}/config.json" ]]; then
  echo "체크포인트 없음: $STABLE_CKPT" >&2
  echo "  → config.sh 의 STABLE_CKPT 경로를 확인하세요." >&2
  exit 1
fi

# SmolVLA 계열인데 rename_map 이 비면 카메라 미스매치로 죽는다.
if [[ "$STABLE_INFERENCE_TYPE" == "rtc" && -z "$STABLE_RENAME_MAP" ]]; then
  echo "⚠ rtc 추론이지만 STABLE_RENAME_MAP 이 비어 있음" >&2
  echo "  SmolVLA 계열이면 카메라 이름 불일치로 실행이 실패합니다. config.sh 를 확인하세요." >&2
  read -r -p "계속할까요? [y/N] " a || exit "$EDU_CANCEL"
  [[ "$a" =~ ^[Yy]$ ]] || { echo "취소됨"; exit "$EDU_CANCEL"; }
fi

OPT=()
[[ -n "$STABLE_RENAME_MAP" ]] && OPT+=(--rename_map="$STABLE_RENAME_MAP")
if [[ "$STABLE_INFERENCE_TYPE" == "rtc" ]]; then
  OPT+=(--inference.rtc.execution_horizon="$RTC_HORIZON" --interpolation_multiplier="$RTC_INTERP")
fi

banner "4-2 · 안정본 롤아웃" \
        "모델 : $STABLE_CKPT" \
        "추론 : $STABLE_INFERENCE_TYPE" \
        "과제 : $STABLE_TASK" \
        "${STABLE_RENAME_MAP:+rename_map 적용됨}" \
        "" \
        "종료 : Ctrl+C."

need_ports "$FOLLOWER_PORT"
gpu_guard

run_cmd lerobot-rollout \
  --strategy.type=base \
  --inference.type="$STABLE_INFERENCE_TYPE" \
  "${OPT[@]+"${OPT[@]}"}" \
  --policy.path="$STABLE_CKPT" \
  --robot.type=so101_follower \
  --robot.port="$FOLLOWER_PORT" \
  --robot.id="$FOLLOWER_ID" \
  --robot.cameras="$CAMERAS" \
  --task="$STABLE_TASK" \
  --fps="$CAM_FPS" \
  --duration="$DURATION" \
  --display_data="$DISPLAY_DATA" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
