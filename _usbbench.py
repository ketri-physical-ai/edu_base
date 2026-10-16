#!/usr/bin/env python
# _usbbench.py — 로봇 없이, USB 연결 구성만 30초 만에 판정한다.
#
#   두 카메라를 lerobot 과 똑같은 설정(640x480@30, 백그라운드 스레드)으로 동시에 열고
#   실제로 도착한 프레임 수와 도착 간격을 센다. 사람 조작이 안 들어가므로
#   구성끼리 비교할 때 변수가 없다.
#
#   쓰는 법 :  python _usbbench.py [초]        기본 30초
#              CAM_TOP=0 CAM_WRIST=2 python _usbbench.py 30
import os, sys, time, threading
import cv2

DUR   = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0
W, H  = int(os.environ.get("CAM_W", 640)), int(os.environ.get("CAM_H", 480))
FPS   = int(os.environ.get("CAM_FPS", 30))
CAMS  = {"top": int(os.environ.get("CAM_TOP", 0)),
         "wrist": int(os.environ.get("CAM_WRIST", 2))}

res = {}

def grab(name, idx):
    cap = cv2.VideoCapture(idx, cv2.CAP_V4L2)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, W)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, H)
    cap.set(cv2.CAP_PROP_FPS, FPS)
    if not cap.isOpened():
        res[name] = None; return
    for _ in range(10):                      # 워밍업
        cap.read()
    ts, t0 = [], time.perf_counter()
    while time.perf_counter() - t0 < DUR:
        ok, _f = cap.read()
        if ok:
            ts.append(time.perf_counter())
    cap.release()
    res[name] = ts

ths = [threading.Thread(target=grab, args=(n, i)) for n, i in CAMS.items()]
print(f"두 카메라 동시 캡처 {DUR:.0f}초 · {W}x{H}@{FPS} — 측정 중...")
for t in ths: t.start()
for t in ths: t.join()

print(f"\n{'카메라':8s} {'수신':>7s} {'실효fps':>8s} {'기대':>6s} {'p50':>7s} {'p90':>7s} {'p99':>7s} {'최대':>8s} {'>100ms':>7s} {'>500ms':>7s}")
bad = False
for name, idx in CAMS.items():
    ts = res.get(name)
    if not ts:
        print(f"{name:8s}  열기 실패 (index {idx})"); bad = True; continue
    span = ts[-1] - ts[0]
    g = sorted(ts[i] - ts[i-1] for i in range(1, len(ts)))
    q = lambda k: g[int(k * len(g))] * 1000
    n100 = sum(1 for x in g if x > 0.100)
    n500 = sum(1 for x in g if x > 0.500)      # lerobot read_latest 가 죽는 선
    fps  = len(ts) / span
    print(f"{name:8s} {len(ts):7d} {fps:8.1f} {FPS:6d} {q(.5):7.1f} {q(.9):7.1f} {q(.99):7.1f} "
          f"{g[-1]*1000:8.1f} {n100:7d} {n500:7d}")
    if fps < FPS * 0.9 or n500 > 0:
        bad = True

print()
print("판정 : " + ("❌ 사용 불가 — 실효 fps 가 기대치의 90% 미만이거나 500ms 이상 멈춤이 있습니다."
                  if bad else
                  "✅ 정상 — 두 카메라 모두 기대 fps 충족"))
print("      500ms 넘는 멈춤이 한 번이라도 있으면 녹화 중 TimeoutError 로 중단됩니다")
print("      (cameras/opencv/camera_opencv.py:582 read_latest, max_age_ms=500)")
