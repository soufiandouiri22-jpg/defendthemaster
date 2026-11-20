#!/bin/zsh
# Records the Roblox window (Studio or the player) with Roblox's own sound into .local/recordings/.
# Usage: Tools/Record/record.sh start [name] | stop | status | list
set -e
here=${0:A:h}
root=${here:h:h}
bin=/tmp/dtm/record
pidfile=/tmp/dtm/record.pid
outfile=/tmp/dtm/record.out
log=/tmp/dtm/record.log
if [[ ! -x $bin || $here/record.swift -nt $bin ]]; then
	mkdir -p /tmp/dtm
	swiftc -O -swift-version 5 $here/record.swift -o $bin
fi
running() { [[ -f $pidfile ]] && kill -0 $(<$pidfile) 2>/dev/null }

case $1 in
start)
	running && { echo "already recording: $(<$outfile)" >&2; exit 1 }
	# A minute of Retina footage takes about 100 MB.
	free=$(df -m $root | awk 'NR == 2 { print $4 }')
	(( free > 2048 )) || { echo "only ${free} MB free on the disk, need at least 2 GB" >&2; exit 1 }
	mkdir -p $root/.local/recordings
	out=$root/.local/recordings/${2:-$(date +%Y-%m-%d_%H-%M-%S)}.mp4
	[[ -e $out ]] && { echo "$out already exists" >&2; exit 1 }
	nohup $bin $out >$log 2>&1 &
	echo $! >$pidfile
	echo $out >$outfile
	for _ in {1..50}; do
		grep -q '^window:' $log && break
		running || break
		sleep 0.1
	done
	running || { cat $log >&2; exit 1 }
	grep '^window:' $log
	echo "recording to $out"
	;;
stop)
	running || { echo "not recording" >&2; exit 1 }
	kill -INT $(<$pidfile)
	for _ in {1..150}; do
		running || break
		sleep 0.1
	done
	rm -f $pidfile
	grep -q '^saved' $log || { cat $log >&2; exit 1 }
	out=$(<$outfile)
	length=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 $out)
	echo "saved $out ($(printf %.0f $length) s, $(du -h $out | cut -f1))"
	;;
status)
	if running; then echo "recording to $(<$outfile)"; else echo "not recording"; fi
	;;
list)
	$bin --list
	;;
*)
	echo "usage: $0 start [name] | stop | status | list" >&2
	exit 2
	;;
esac
