#!/usr/bin/env python
# _fpsaudit.py — 녹화된 데이터셋에서 USB 프레임 드랍 흔적을 센다.
#
#   lerobot 은 카메라가 늦으면 read_latest() 가 "직전 프레임"을 그대로 돌려준다.
#   (cameras/opencv/camera_opencv.py:582 — 비차단, 500ms 넘으면 TimeoutError)
#   그래서 드랍은 데이터셋 안에서 '연속 중복 프레임'으로 남는다.
#   parquet 의 timestamp 는 frame_index/fps 로 만들어진 이상값이라 아무 정보가 없다.
#
#   쓰는 법 :
#     python _fpsaudit.py ~/.cache/huggingface/lerobot/data/<이름> [...]
#     LIMIT=8 python _fpsaudit.py ...      # 카메라당 앞쪽 8개 파일만 (빠르게)
#
#   보는 법 :
#     연속2+ 가 거의 0  → 정상.
#     연속3+ 가 수십~수백 회, 최장 6~15프레임 → USB 대역 부족. 학습에 쓰지 마라.
import glob, os, subprocess, sys
import numpy as np

W, H = 160, 120
N = W * H
STRICT, LOOSE = 0.05, 0.30      # 프레임간 평균 밝기차 (0~255)

def frame_diffs(path):
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", f"scale={W}:{H},format=gray",
         "-f", "rawvideo", "-"], capture_output=True)
    a = np.frombuffer(p.stdout, dtype=np.uint8)
    n = len(a) // N
    a = a[:n * N].reshape(n, N).astype(np.int16)
    return np.abs(np.diff(a, axis=0)).mean(axis=1)

def runs_of(mask):
    out, c = [], 0
    for x in mask:
        if x:
            c += 1
        elif c:
            out.append(c); c = 0
    if c:
        out.append(c)
    return np.array(out) if out else np.array([0])

def audit(root, limit=None, fps=30):
    print(f"\n=== {root}")
    if not os.path.isdir(root):
        print(f"  ✗ 폴더 없음: {os.path.abspath(root)}")
        print(f"    → 데이터 루트에서 실행하거나 전체 경로를 지정하세요:")
        print(f"      cd ~/.cache/huggingface/lerobot/data && python ~/edu_base/_fpsaudit.py <이름>")
        return
    cams = sorted(glob.glob(os.path.join(root, "videos", "*")))
    if not cams:
        print(f"  ✗ videos/ 폴더 비어 있음 — lerobot 데이터셋이 아니거나 녹화가 끝나지 않았습니다.")
        return
    for cam in cams:
        files = sorted(glob.glob(os.path.join(cam, "chunk-*", "*.mp4")))
        if limit:
            files = files[:limit]
        if not files:
            print(f"  ✗ {os.path.basename(cam)}: mp4 없음")
            continue
        d = np.concatenate([frame_diffs(f) for f in files])
        line = f"  {os.path.basename(cam):26s} {len(d):6d}프레임 ({len(d)/fps:.0f}초)"
        for name, thr in (("엄격", STRICT), ("느슨", LOOSE)):
            r = runs_of(d <= thr)
            n2, n3, n5 = int((r >= 2).sum()), int((r >= 3).sum()), int((r >= 5).sum())
            worst = int(r.max())
            line += (f"\n      [{name} thr={thr:.2f}] 중복률 {100*(d<=thr).mean():5.1f}%"
                     f" · 연속2+ {n2:5d}회 · 연속3+ {n3:5d}회 · 연속5+ {n5:4d}회"
                     f" · 최장 {worst:2d}프레임({worst*1000//fps:4d}ms)")
        print(line)

if __name__ == "__main__":
    lim = int(os.environ.get("LIMIT", "0")) or None
    for r in sys.argv[1:]:
        audit(r, lim)
