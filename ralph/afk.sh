#!/bin/bash
set -eo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations>"
  exit 1
fi

# jq filter to extract streaming text from assistant messages
stream_text='select(.type == "assistant").message.content[]? | select(.type == "text").text // empty | gsub("\n"; "\r\n") | . + "\r\n\n"'

# jq filter to extract final result
final_result='select(.type == "result").result // empty'

for ((i=1; i<=$1; i++)); do
  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
  repo=$(git remote get-url origin | sed 's|.*github\.com[/:]||;s|\.git$||')
  issues=$(gh issue list --repo "$repo" --state open --json number,title --jq '.[] | "#\(.number): \(.title)"')
  prompt=$(cat ralph/prompt.md)

  docker sandbox run claude . -- \
    --verbose \
    --print \
    --permission-mode bypassPermissions \
    --output-format stream-json \
    "GitHub repo: $repo

Previous commits: $commits

Open issues:
$issues

$prompt" \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_text"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
    echo "Ralph complete after $i iterations."
    exit 0
  fi
done