#!/bin/bash
cd "$(dirname "$0")" || exit 1
REPO_URL="https://github.com/gh0st-8221/ghostosinstall.git"
printf 'out/\n' > .gitignore
if [[ ! -d ".git" ]]; then
    git init -b main
    git remote add origin "$REPO_URL"
elif ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "$REPO_URL"
fi
git add .
git commit -m "update backup from $(date '+%Y-%m-%d %H:%M:%S')" || echo "No changes to commit."
git push -u origin main --force
