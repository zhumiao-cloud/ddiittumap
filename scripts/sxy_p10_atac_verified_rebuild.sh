#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

MAIN_UNIT=sxy-mmul10-multiome-arc-20261010
RUNNER=/home/h3039/PROJECTS/zhumiao/.multiome_arc_runner
BUILD_RUNNER="$RUNNER/sxy_mmul10_arc_build_and_run.sh"
WORK=/home/h3039/PROJECTS/zhumiao/multiome_arc_work/P10MK1_1
ATAC="$WORK/input/ATAC"
REMOTE='danxibao3_webdav:P10MK1_1/ATAC'
MANIFEST="$ATAC/md5.md5"
PROXY='http://127.0.0.1:19324'
CHUNK=67108864
PAR=24

test "$(id -un)" = h3039
test -s "$BUILD_RUNNER"
test -s "$RUNNER/arc_multiome_three_samples.sh"
ss -ltn | grep -q '127.0.0.1:19324'
mkdir -p "$ATAC" "$WORK/.atac_rebuild"
export HTTPS_PROXY="$PROXY" https_proxy="$PROXY"
export NO_PROXY=localhost,127.0.0.1 no_proxy=localhost,127.0.0.1

timeout 60 rclone cat "$REMOTE/md5.md5" > "$MANIFEST.tmp"
grep -q 'P10-zc_S1_L004_R3_001.fastq.gz' "$MANIFEST.tmp"
mv -f "$MANIFEST.tmp" "$MANIFEST"

echo "ATAC_REBUILD_BEGIN=$(date -Is)"
systemctl --user stop "$MAIN_UNIT" 2>/dev/null || true
sleep 3
if pgrep -af 'rclone copy danxibao3_webdav:P10MK1_1/ATAC' >/dev/null 2>&1; then
  echo ERROR_OLD_ATAC_COPY_STILL_RUNNING >&2
  exit 30
fi

rebuild_one() {
  local f="$1" expected remote_size target chunkdir plan tmp actual planned got bad
  target="$ATAC/$f"
  expected="$(awk -v f="$f" '$2==f{print $1}' "$MANIFEST" | head -n1)"
  test -n "$expected"
  remote_size="$(timeout 90 rclone lsl "$REMOTE/$f" | awk 'NR==1{print $1}')"
  test "$remote_size" -gt 1000000
  echo "ATAC_FILE=$f REMOTE_SIZE=$remote_size EXPECTED_MD5=$expected"

  if [ -s "$target" ] && [ "$(stat -c %s "$target")" = "$remote_size" ]; then
    actual="$(md5sum "$target" | awk '{print $1}')"
    if [ "$actual" = "$expected" ] && gzip -t "$target"; then
      echo "ATAC_ALREADY_VERIFIED=$f"
      return
    fi
    echo "ATAC_EXISTING_REJECTED=$f actual_md5=$actual"
  fi

  chunkdir="$WORK/.atac_rebuild/$f"
  plan="$chunkdir/plan.tsv"
  mkdir -p "$chunkdir"
  python3 - "$remote_size" "$CHUNK" "$plan" <<'PY'
import sys
end,chunk=map(int,sys.argv[1:3]); out=sys.argv[3]
with open(out,"w") as h:
    for i,off in enumerate(range(0,end,chunk)):
        n=min(chunk,end-off)
        h.write(f"{i:08d}\t{off}\t{n}\n")
PY

  export REMOTE_FILE="$REMOTE/$f" CHUNKDIR="$chunkdir"
  xargs -P "$PAR" -n 3 bash -c '
    set -euo pipefail
    idx="$1"; off="$2"; cnt="$3"
    out="$CHUNKDIR/chunk.$idx"
    if [ -s "$out" ] && [ "$(stat -c %s "$out")" = "$cnt" ]; then exit 0; fi
    rm -f "$out" "$out.tmp"
    for try in 1 2 3 4 5 6 7 8; do
      if timeout 600 rclone cat "$REMOTE_FILE" --offset "$off" --count "$cnt" > "$out.tmp" &&
         [ "$(stat -c %s "$out.tmp")" = "$cnt" ]; then
        mv "$out.tmp" "$out"
        exit 0
      fi
      rm -f "$out.tmp"
      sleep $((try*3))
    done
    exit 41
  ' _ < "$plan"

  planned="$(awk '{s+=$3} END{print s+0}' "$plan")"
  got="$(find "$chunkdir" -type f -name 'chunk.*' -printf '%s\n' | awk '{s+=$1} END{print s+0}')"
  test "$planned" = "$got"

  tmp="$ATAC/$f.rebuild"
  rm -f "$tmp"
  find "$chunkdir" -type f -name 'chunk.*' -print0 | sort -z | xargs -0 cat > "$tmp"
  test "$(stat -c %s "$tmp")" = "$remote_size"
  actual="$(md5sum "$tmp" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "ERROR_ATAC_REBUILT_MD5=$f expected=$expected actual=$actual" >&2
    exit 43
  fi
  gzip -t "$tmp"

  bad="$ATAC/$f.rejected"
  rm -f "$bad"
  [ -e "$target" ] && mv -f "$target" "$bad"
  mv -f "$tmp" "$target"
  md5sum "$target" | grep -q "^$expected "
  gzip -t "$target"
  rm -f "$bad"
  rm -rf "$chunkdir"
  echo "ATAC_REBUILD_VERIFIED=$f size=$remote_size md5=$expected"
}

for L in 001 002 003 004; do
  for R in I1 R1 R2 R3; do
    rebuild_one "P10-zc_S1_L${L}_${R}_001.fastq.gz"
  done
done

echo ATAC_ALL_16_VERIFIED=PASS
systemctl --user reset-failed "$MAIN_UNIT" 2>/dev/null || true
if systemctl --user show "$MAIN_UNIT" -p LoadState --value 2>/dev/null | grep -qx loaded; then
  systemctl --user restart "$MAIN_UNIT"
else
  systemd-run --user --unit="$MAIN_UNIT" --description="Mmul10 ARC three Multiome conversions" /usr/bin/bash "$BUILD_RUNNER"
fi
sleep 8
systemctl --user show "$MAIN_UNIT" -p ActiveState -p SubState -p Result -p ExecMainStatus --no-pager
echo "ATAC_REBUILD_END=$(date -Is)"
