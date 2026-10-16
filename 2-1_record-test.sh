#!/usr/bin/env bash
# 2-1 · 녹화 연습 — 실제 녹화와 같은 절차로 에피소드 몇 개만 녹화해 본다.
#      연습용 데이터셋에 저장하므로 실제 녹화본을 건드리지 않는다.
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/common.sh"
parse_args "$@"

# 녹화 중 Ctrl+C 는 즉시 끝내지 않는다 — lerobot 이 영상을 마저 저장해야 한다.
trap 'echo; echo "중단 요청됨 — 저장 중입니다. 완료될 때까지 터미널을 닫지 마세요."' INT

banner "2-1 · 녹화 연습 (에피소드 ${TEST_EPISODES}개)" \
        "데이터셋 : $EDU_TEST_REPO_ID  ← 연습용, 학습에 사용 안함." \
        "녹화시간 ${EPISODE_TIME_S}초 · 대기시간 ${RESET_TIME_S}초"

# 명령 확인을 받은 뒤, 녹화가 시작되기 직전에 뜬다 (common.sh 의 run_cmd 가 쓴다)
RUN_NOTICE="──────────────────────────────────────────────────────
  녹화 중 조작
    →      현재 에피소드 조기 종료
    ←      현재 에피소드 재녹화
    ESC    녹화 종료
──────────────────────────────────────────────────────"

# 에피소드 경계 표시 — 2-3 과 같은 rec_filter (common.sh) 를 쓴다
RUN_FILTER=rec_filter
FROM=0; TO=$(( TEST_EPISODES - 1 )); TOTAL="$TEST_EPISODES"

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
[[ $rc -eq 0 ]] || { echo; echo "녹화 비정상 종료 (코드 $rc)"; exit "$rc"; }

echo
echo "에피소드 확인 :  edu2-2 --test"
