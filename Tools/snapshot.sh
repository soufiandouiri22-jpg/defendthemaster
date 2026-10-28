#!/bin/zsh
# Records the code as it is now (tracked and untracked files, as .gitignore allows) as a commit under refs/snapshots/,
# without touching the branch, HEAD, the index or any file, and without removing anything: every version stays
# retrievable exactly. Nothing is recorded when nothing changed since the last snapshot.
#   Tools/snapshot.sh [reason]      record a snapshot
#   Tools/snapshot.sh list [n]      the latest n snapshots (20)
#   git show <snapshot>:<path>      a file as it was in that snapshot
set -e
cd "$(dirname "$0")/.."
if [[ "$1" == list ]]; then
	git for-each-ref --sort=-refname --count=${2:-20} --format='%(refname:short)  %(subject)' refs/snapshots
	exit 0
fi
index=$(mktemp)
trap 'rm -f "$index"' EXIT
export GIT_INDEX_FILE=$index
git read-tree HEAD
git add -A -- src Tools Docs Lib AGENTS.md default.project.json rokit.toml selene.toml stylua.toml .gitignore
tree=$(git write-tree)
last=$(git for-each-ref --sort=-refname --count=1 --format='%(refname)' refs/snapshots)
if [[ -n $last && $(git rev-parse "$last^{tree}") == $tree ]]; then
	exit 0
fi
commit=$(git commit-tree $tree -p HEAD -m "snapshot ${1:-manual} $(date '+%Y-%m-%d %H:%M:%S')")
git update-ref refs/snapshots/$(date +%Y%m%d-%H%M%S) $commit
echo "snapshot $commit"
