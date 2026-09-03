#!/usr/bin/env bash
# 2-1 · 녹화 연습 — 진짜와 똑같은 절차로 몇 편만 찍어 본다.
#      연습용 데이터셋에 저장하므로 실제 녹화본을 건드리지 않는다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

# 녹화 중 Ctrl+C 는 즉시 끝내지 않는다 — lerobot 이 영상을 마저 저장해야 한다.
trap 'echo; echo "중단 신호 — lerobot 이 저장을 마칠 때까지 기다린다. 창을 닫지 마라."' INT

banner "2-1 · 녹화 연습 (${TEST_EPISODES}편)" \
        "데이터셋 : $EDU_TEST_REPO_ID  ← 연습용, 나중에 지운다" \
        "녹화시간 ${EPISODE_TIME_S}초 · 대기시간 ${RESET_TIME_S}초"

# 명령 확인을 받은 뒤, 녹화가 시작되기 직전에 뜬다 (common.sh 의 run_cmd 가 쓴다)
RUN_NOTICE="──────────────────────────────────────────────────────
  녹화 중 조작
    →      한 편 일찍 끝내기
    ←      다시 찍기
    ESC    녹화 끝내기
──────────────────────────────────────────────────────"

need_ports "$FOLLOWER_PORT" "$LEADER_PORT"

if [[ -d "$EDU_TEST_ROOT" ]]; then
  ask_delete "$EDU_TEST_ROOT" "연습 데이터셋" || exit "$EDU_CANCEL"
fi

run_cmd lerobot-record \
  --robot.type=so101_follower \
  --robot.port="$FOLLOWER_PORT" \
  --robot.id="$FOLLOWER_ID" \
  --robot.cameras="$CAMERAS" \
  --teleop.type=so101_leader \
  --teleop.port="$LEADER_PORT" \
  --teleop.id="$LEADER_ID" \
  --display_data="$DISPLAY_DATA" \
  --dataset.repo_id="$EDU_TEST_REPO_ID" \
  --dataset.root="$EDU_TEST_ROOT" \
  --dataset.push_to_hub=false \
  --dataset.fps="$CAM_FPS" \
  --dataset.num_episodes="$TEST_EPISODES" \
  --dataset.single_task="$TASK" \
  --dataset.episode_time_s="$EPISODE_TIME_S" \
  --dataset.reset_time_s="$RESET_TIME_S" \
  "${EXTRA[@]+"${EXTRA[@]}"}"
rc=$?
[[ $rc -eq 0 ]] || { echo; echo "녹화가 정상 종료되지 않았다 (코드 $rc)."; exit "$rc"; }

echo
echo "찍은 것을 보려면 :  edu2-2 --test"
