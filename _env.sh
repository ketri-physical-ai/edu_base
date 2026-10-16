#!/usr/bin/env bash
# _env.sh — 파이썬 환경을 잡는다. **값은 config.sh 에, 잡는 방법은 여기에.**
#   이 파일을 직접 실행하지 않는다. config.sh 를 읽은 뒤 source 한다.
#
#   찾는 순서
#     ① 이미 쓸 만한 환경이 켜져 있나
#     ② PATH 에 lerobot 명령이 있나 (venv·pipx·시스템 설치)
#     ③ config.sh 의 CONDA_SH → 흔한 conda 설치 위치
#     ④ conda 가 있으면 **환경 목록을 뒤져** lerobot 이 든 환경을 찾는다
#     ⑤ 흔한 venv 자리
#     ⑥ conda 가 없어도 지금 파이썬이 쓸 만하면 그대로
#   ⚠ 못 찾았다고 조용히 넘어가지 않는다. 무엇을 하면 되는지 알려준다.

_edu_py_ok() { command -v python3 >/dev/null && python3 -c 'import pandas, pyarrow' 2>/dev/null; }
_edu_note()  { [[ -n "${EDU_ENV_WARNED:-}" ]] || { echo "  ⓘ $*" >&2; export EDU_ENV_WARNED=1; }; }

# 무엇이 없는지 이름으로 돌려준다 (있으면 빈 문자열)
_edu_missing() {
  local m out=""
  command -v python3 >/dev/null || { printf 'python3'; return; }
  # 이름이 다른 것 : rerun-sdk 는 import 이름이 rerun 이다
  for m in pandas pyarrow rerun; do python3 -c "import $m" 2>/dev/null || out="$out $m"; done
  printf '%s' "${out# }"
}

# 모자란 꾸러미를 그 자리에서 채운다. **미리보기 → y/N → 설치.**
#   ⚠ pandas·pyarrow 는 lerobot 의 **핵심 의존성이 아니라 `dataset` extra 소속**이다.
#      최소 설치(`pip install lerobot`)면 빠진다 — 설치가 깨진 게 아니다.
#      rerun 은 `viz` extra 다.
edu_install_deps() {
  local miss; miss="$(_edu_missing)"
  [[ -z "$miss" ]] && return 0
  [[ "$miss" == "python3" ]] && return 1
  # 한 번 물었으면 그만 묻는다 (탐색 단계마다 되묻지 않게)
  [[ -n "${EDU_DEPS_TRIED:-}" ]] && return 1
  export EDU_DEPS_TRIED=1
  echo
  echo "  ── 파이썬 패키지 부족 ────────────────────────────"
  echo "     없는 것 : $miss"
  echo "     파이썬  : $(command -v python3)  ($(python3 -V 2>&1))"
  echo "     환경    : ${CONDA_DEFAULT_ENV:-${VIRTUAL_ENV:-시스템}}"
  echo "     lerobot 최소 설치 시 빠지는 패키지입니다 (설치 오류 아님)."
  echo "       pandas·pyarrow → dataset extra    rerun → viz extra"
  echo "     설치할 명령 — extra 로 한 번에 (권장) :"
  echo "       python3 -m pip install \"lerobot[dataset,viz,feetech,smolvla]\""
  echo "     ⓘ 4-2 안정본(SmolVLA)을 쓰려면 smolvla 가 필요합니다."
  echo "       'all' 은 extra 43개(시뮬레이터·정책 전체)를 모두 설치하므로 권장하지 않습니다."
  echo "  ──────────────────────────────────────────────────"
  if [[ "${EDU_YES:-0}" != "1" ]]; then
    local a
    read -r -p "  지금 설치할까요? [y/N] " a || { echo "  입력 없음"; return 1; }
    [[ "$a" =~ ^[Yy]$ ]] || { echo "  설치 안 함"; return 1; }
  fi
  # ⚠ 인터넷이 없으면 pip 이 재시도로 오래 멈춘다 — 먼저 확인하고, 짧게 끊는다.
  if ! timeout 4 python3 -c "
import socket,sys
try: socket.create_connection(('pypi.org',443),3); sys.exit(0)
except Exception: sys.exit(1)" 2>/dev/null; then
    echo "  ✘ 인터넷 연결 없음 — pip 설치 불가" >&2
    echo "     인터넷이 되는 환경에서 미리 설치하세요 :" >&2
    echo "       pip install \"lerobot[dataset,viz,feetech,smolvla]\"" >&2
    echo "     또는 다른 PC 에서 내려받아 복사하세요 :" >&2
    echo "       pip download <꾸러미> -d wheels/  →  pip install --no-index --find-links wheels/ <꾸러미>" >&2
    return 1
  fi
  local PIPQ=(--timeout 10 --retries 1)
  # extra 로 먼저 시도하고, lerobot 이 pip 로 안 잡히면 개별 꾸러미로 물러선다.
  python3 -m pip install "${PIPQ[@]}" "lerobot[dataset,viz,feetech,smolvla]" \
    || python3 -m pip install "${PIPQ[@]}" "pandas>=2.0.0,<3.0.0" "pyarrow>=21.0.0,<30.0.0" rerun-sdk || {
    echo "  ✘ 설치 실패 — 인터넷 연결 또는 권한을 확인하세요." >&2
    echo "     인터넷이 없으면 다른 PC 에서 내려받아 복사하세요 :" >&2
    echo "       pip download pandas pyarrow -d wheels/   →  pip install --no-index --find-links wheels/ pandas pyarrow" >&2
    return 1; }
  if _edu_py_ok; then echo "  설치 완료 ✔"; return 0; fi
  echo "  ✘ 설치 후에도 불러오기 실패" >&2; return 1
}

edu_activate() {
  local env="${CONDA_ENV:-lerobot}" c p

  # ⓪ 사용자가 직접 지목한 파이썬이 있으면 그것부터
  if [[ -n "${EDU_PY:-}" && -x "$EDU_PY" ]]; then
    PATH="$(dirname "$EDU_PY"):$PATH"; export PATH
    _edu_py_ok && { _edu_note "EDU_PY 지정 파이썬 사용 : $EDU_PY"; return 0; }
  fi

  # ① 이미 켜져 있나
  [[ "${CONDA_DEFAULT_ENV:-}" == "$env" ]] && _edu_py_ok && return 0
  [[ -n "${VIRTUAL_ENV:-}" ]] && _edu_py_ok && { _edu_note "활성화된 venv 사용 : $VIRTUAL_ENV"; return 0; }

  # ② lerobot 명령이 PATH 에 있으면 그 환경이 이미 맞다.
  #    꾸러미만 모자란 경우가 흔하다 — 그때는 그 자리에서 채운다.
  if command -v lerobot-train >/dev/null; then
    _edu_py_ok && return 0
    edu_install_deps && return 0
  fi

  # ③ conda 초기화 스크립트 후보
  for c in "${CONDA_SH:-}" \
           "$HOME/miniforge3/etc/profile.d/conda.sh" \
           "$HOME/miniconda3/etc/profile.d/conda.sh" \
           "$HOME/anaconda3/etc/profile.d/conda.sh" \
           "$HOME/mambaforge/etc/profile.d/conda.sh" \
           "/opt/conda/etc/profile.d/conda.sh" \
           "/usr/share/miniconda3/etc/profile.d/conda.sh"; do
    [[ -n "$c" && -f "$c" ]] || continue
    # shellcheck disable=SC1090
    source "$c" 2>/dev/null || continue
    conda activate "$env" 2>/dev/null && _edu_py_ok && return 0

    # ④ 이름이 다를 수 있다 — lerobot 이 든 환경을 직접 찾는다
    local envdir
    while read -r envdir; do
      [[ -x "$envdir/bin/lerobot-train" ]] || continue
      conda activate "$envdir" 2>/dev/null || PATH="$envdir/bin:$PATH"
      export PATH
      if _edu_py_ok; then
        _edu_note "conda 환경 '$env' 대신 찾은 환경 사용 : $envdir"
        return 0
      fi
    done < <(conda env list 2>/dev/null | awk '!/^#/ && NF {print $NF}')
  done

  # ⑤ 흔한 venv 자리
  for p in "$HOME/lerobot/.venv" "$HOME/.venv" "$HOME/venv" "./.venv" "./venv" \
           "$HOME/so101_lerobot_env" "$HOME/lerobot_env"; do
    [[ -x "$p/bin/python3" ]] || continue
    PATH="$p/bin:$PATH"; export PATH
    _edu_py_ok && { _edu_note "venv 사용 : $p"; return 0; }
  done

  # ⑥ 지금 파이썬이 쓸 만하면 그대로
  _edu_py_ok && { _edu_note "conda 환경 '$env' 없음 — 현재 파이썬 사용"; return 0; }
  command -v python3 >/dev/null && edu_install_deps && return 0

  echo "파이썬 환경 설정 실패 — pandas · pyarrow 가 필요합니다." >&2
  echo "  가장 쉬운 방법 — 사용하던 환경을 먼저 활성화한 뒤 다시 실행하세요 :" >&2
  echo "      conda activate <환경이름>   (또는  source <venv>/bin/activate)" >&2
  echo "      bash edu-set.sh" >&2
  echo "  또는 아래 중 하나 :" >&2
  echo "    · config.sh 의 CONDA_ENV 를 실제 환경 이름으로 수정  (현재 : $env)" >&2
  echo "    · config.sh 의 CONDA_SH 를 실제 conda.sh 경로로 수정" >&2
  echo "    · 파이썬 직접 지정 :  EDU_PY=/경로/python3 bash edu-set.sh" >&2
  command -v conda >/dev/null && {
    echo "  이 PC 의 conda 환경 목록 :" >&2
    conda env list 2>/dev/null | awk '!/^#/ && NF {print "      "$0}' >&2; }
  return 1
}

# 브라우저를 연다. 없는 PC 도 있으므로 차례로 찾고, 다 없으면 경로만 알려준다.
edu_open() {
  local url="$1" b
  for b in ${EDU_BROWSER:-} google-chrome chromium chromium-browser firefox xdg-open; do
    command -v "$b" >/dev/null || continue
    if [[ "$b" == "xdg-open" ]]; then "$b" "$url" >/dev/null 2>&1 &
    else "$b" --new-window "$url" >/dev/null 2>&1 & fi
    echo "  브라우저로 열림 ($b) : $url"; return 0
  done
  echo "  브라우저 없음 — 아래 파일을 직접 여세요 :" >&2
  echo "    $url" >&2
  return 0
}
