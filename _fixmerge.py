#!/usr/bin/env python3
"""병합(merge/aggregate) 후 meta/episodes/file_index 스테일 값 교정.

lerobot 0.6.x aggregate 버그:
  병합 시 aggregate.py 가 meta/episodes/file_index 에 소스별 오프셋을 누적해
  [0,1,...] 로 기록하지만, 실제 메타는 크기가 작아 file-000.parquet 하나로 합쳐
  저장된다. 그 결과 "존재하지 않는 file-001" 을 가리키는 인덱스가 남고, 이 데이터셋을
  다시 병합 소스로 쓰면 FileNotFoundError 로 죽는다. (학습은 이 컬럼을 안 봐서 정상.)

교정: 실제 meta/episodes parquet 이 1개면, 모든 행의
      meta/episodes/{chunk_index,file_index} 를 0 으로 되돌린다.

사용:
  python fix_merge_index.py <dataset_root> [<dataset_root2> ...]
  # 예: python fix_merge_index.py /..._HOME/data/so101_cylinder_v6
"""
import glob
import os, re, time, hashlib
import shutil
import sys

import pandas as pd

CHUNK = "meta/episodes/chunk_index"
FILE = "meta/episodes/file_index"


def fix_one(root: str) -> int:
    root = root.rstrip("/")
    name = os.path.basename(root)
    metas = sorted(glob.glob(os.path.join(root, "meta/episodes/**/*.parquet"), recursive=True))
    if not metas:
        print(f"[{name}] meta/episodes parquet 없음 — 건너뜀")
        return 0
    if len(metas) > 1:
        print(f"[{name}] ⚠️ meta/episodes 파일이 {len(metas)}개. 이 스크립트는 단일 파일 케이스만 "
              f"안전하게 교정함(대부분 그럼). 여러 개면 수동 확인 필요 — 건너뜀.")
        return 2
    f = metas[0]
    df = pd.read_parquet(f)
    if FILE not in df.columns:
        print(f"[{name}] file_index 컬럼 없음 — 대상 아님")
        return 0
    fi = sorted(int(x) for x in df[FILE].unique())
    ci = sorted(int(x) for x in df[CHUNK].unique()) if CHUNK in df.columns else [0]

    # ⚠ 파일이 하나라고 그 위치가 0/0 이라는 보장은 없다.
    #    실제 경로(.../chunk-003/file-007.parquet)에서 읽어 그 값으로 맞춘다.
    #    예상 형식이 아니면 손대지 않는다 — 잘못 고치면 더 나빠진다.
    m = re.search(r"chunk-(\d+)/file-(\d+)\.parquet$", f)
    if not m:
        print(f"[{name}] 파일 경로 형식이 예상과 다름 — 건너뜀: {f}")
        return 2
    want_c, want_f = int(m.group(1)), int(m.group(2))
    if fi == [want_f] and ci == [want_c]:
        print(f"[{name}] 이미 정상 (chunk={want_c} file={want_f}) — 교정 불필요")
        return 0

    # 백업: 데이터셋 폴더 '밖' 에 (안에 두면 glob 이 중복으로 읽어 학습/병합이 꼬임)
    #   root = .../data/<name>  →  백업 = .../_merge_index_backups/<name>.file-000.parquet
    data_dir = os.path.dirname(root)              # .../data
    home_dir = os.path.dirname(data_dir)          # .../lerobot (HF_LEROBOT_HOME)
    bkp_dir = os.path.join(home_dir, "_merge_index_backups")
    os.makedirs(bkp_dir, exist_ok=True)
    # 폴더 이름만 쓰면 다른 데이터셋의 백업을 덮어쓴다 — 루트 해시와 시각을 붙인다
    tag = hashlib.sha1(os.path.realpath(root).encode()).hexdigest()[:8]
    stamp = time.strftime("%Y%m%d-%H%M%S")
    bkp = os.path.join(bkp_dir, f"{name}.{tag}.{stamp}.meta_episodes.parquet.bak")
    shutil.copy2(f, bkp)

    df[FILE] = want_f
    if CHUNK in df.columns:
        df[CHUNK] = want_c
    # 원자적 쓰기: 임시파일에 먼저 완성 → 원본 자리에 한 방에 교체.
    # 쓰다 죽어도 원본이 반쯤 깨지지 않는다(백업은 '잘못 고쳤을 때 되돌리기'용).
    tmp = f + ".tmp"
    df.to_parquet(tmp, index=False)
    os.replace(tmp, f)  # 같은 디스크에서 원자적 교체

    chk = pd.read_parquet(f)
    now = sorted(int(x) for x in chk[FILE].unique())
    print(f"[{name}] 교정 완료: file_index {fi} → {now}  (백업: {bkp})")
    return 0 if now == [0] else 1


def main(argv):
    if not argv:
        print(__doc__)
        return 1
    rc = 0
    for root in argv:
        rc |= fix_one(root)
    return rc


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
