#!/usr/bin/env bash
# wp-release.sh
# WP Backend release assistant (with gum)
# Prereqs: 'gum' installed. If 'jq' is missing, sed/grep fallback is used.

set -o pipefail

### ---------- Helpers ----------
die() { echo -e "\n$(gum style --foreground 1 --bold "Error:") $1\n" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed. Please install it and try again."
  echo "Checked: '$1' is installed"
}

style_title() {
  gum style --bold --border normal --padding "1 2" --margin "1 0" --border-foreground 212 "$1"
}

run() {
  # Run a command with gum spinner; fail with a clear message
  local title="$1"; shift
  if ! gum spin --spinner dot --title "$title" -- "$@"; then
    die "Failed at step: '$title'."
  fi
  echo "Running: $@"
}

branch_has_upstream() {
  local br="$1"
  git rev-parse --abbrev-ref --symbolic-full-name "$br@{u}" >/dev/null 2>&1
}

branch_ahead_count() {
  local br="$1"
  # @{u}...BR: left=behind, right=ahead
  local out
  out="$(git rev-list --left-right --count "$br@{u}"..."$br" 2>/dev/null || echo "0	0")"
  echo "${out#*	}"
}

ensure_synced_or_push() {
  # Bulunduğun dal için push'lanmamış commit var mı kontrol eder.
  # Upstream yoksa kurmayı ve push’lamayı teklif eder.
  local br="$1"
  local cur
  cur="$(git rev-parse --abbrev-ref HEAD)"

  if [ "$cur" != "$br" ]; then
    die "Internal: ensure_synced_or_push must be called while on '$br' (current: '$cur')."
  fi

  if ! branch_has_upstream "$br"; then
    gum style --foreground 214 "Branch '$br' has no upstream set."
    if gum confirm "Set upstream and push '$br' to origin?"; then
      run "Push '$br' (set upstream)" git push -u origin "$br"
    else
      die "Upstream not set. Cannot continue safely."
    fi
  else
    local ahead
    ahead="$(branch_ahead_count "$br")"
    if [ "${ahead:-0}" -gt 0 ]; then
      gum style --foreground 214 --bold "Branch '$br' has $ahead unpushed commit(s)."

      git log --oneline "$br@{u}..$br" | sed 's/^/  • /'
      echo
      if gum confirm "Push '$br' to origin now?"; then
        run "Push '$br'" git push
      else
        die "Unpushed commits on '$br'. Aborting."
      fi
    fi
  fi
}

pull_or_internet_hint() {
  # Try git pull; on failure, hint about Internet/VPN
  local br="$1"
  echo "Checking Internet/VPN connectivity"
  echo "Running: git pull --ff-only"
  if ! gum spin --spinner dot --title "Pull: $br" -- git pull --ff-only; then
    echo -e "\n$(gum style --italic --foreground 1 'No internet or VPN? 🙄')\n"
    exit 1
  fi
}

ensure_clean_worktree() {
  if ! git diff-index --quiet HEAD --; then
    gum style --foreground 214 "You have uncommitted changes in the working tree."
    if gum confirm "Stash changes temporarily?"; then
      run "Stash" git stash push -u -m "auto-stash by wp-release.sh"
    else
      die "Please commit/stash your changes and retry."
    fi
  fi
  echo "Verified clean worktree"
}

branch_exists_local()  { 
  echo "check if local branch $1 exists"
  git show-ref --verify --quiet "refs/heads/$1"; 
}
branch_exists_remote() { 
  echo "check if remote branch $1 exists"
  git ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1; 
}

read_json_version() {
  local file="$1"
  local val=""
  if [ -f "$file" ]; then
    if command -v jq >/dev/null 2>&1; then
      val="$(jq -r '.Version // empty' "$file")"
    fi
    if [ -z "$val" ]; then
      # fallback via sed/grep
      val="$(grep -oE '"Version"\s*:\s*"[^"]+"' "$file" | head -1 | sed -E 's/.*"Version"\s*:\s*"([^"]+)".*/\1/')"
    fi
  fi
  echo "$val"
}

write_json_version() {
  local file="$1"
  local newv="$2"

  [ -f "$file" ] || die "File not found: $file"

  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg v "$newv" '.Version = $v' "$file" > "$tmp" || die "Failed to update $file (jq)."
    mv "$tmp" "$file"
  else
    # sed fallback (BSD/macOS compatible -i'')
    if grep -q '"Version"\s*:' "$file"; then
      sed -E -i'' 's/"Version"\s*:\s*"[^"]*"/"Version": "'"$newv"'"/' "$file" || die "Failed to update $file (sed)."
    else
      die "'Version' key not found in $file."
    fi
  fi

  echo "Wrote version $2 to $1"
}

release_branch_exists() {
  # Check if release/<version> exists locally OR on origin (remote)
  local v="$1"
  local r="release/$v"

  echo "Checking if release branch already exists: $r"
  # local branch
  if git show-ref --verify --quiet "refs/heads/$r"; then
    return 0
  fi
  # remote-tracking branch
  if git show-ref --verify --quiet "refs/remotes/origin/$r"; then
    return 0
  fi
  # ensure remote check even if fetch is stale
  if git ls-remote --exit-code --heads origin "$r" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

### ---------- Pre-flight ----------
need_cmd git
need_cmd gum

[ -d .git ] || die "You must run this script at the repo root ('.git' not found)."

style_title "WP Release Assistant"

### ---------- Repo choice ----------
CHOICE=$(gum choose --header "Which repo?" "WP Backend" "WP Frontend")
[ -z "$CHOICE" ] && die "You must make a selection."

if [ "$CHOICE" = "WP Frontend" ]; then
  gum style --foreground 212 "Frontend flow will be added later. Exiting for now. 👋"
  exit 0
fi

### ---------- Backend flow ----------
style_title "Backend: preparation"

# Auto-stash if needed
ensure_clean_worktree

# Fetch remotes
run "Git fetch" git fetch --all

# master pull
if branch_exists_local master; then
  run "Checkout master" git checkout master
  ensure_synced_or_push "master" 
  pull_or_internet_hint "master"
else
  die "Branch not found: master"
fi

# develop pull
if branch_exists_local develop; then
  run "Checkout develop" git checkout develop
  ensure_synced_or_push "develop"
  pull_or_internet_hint "develop"
else
  die "Branch not found: develop"
fi

### ---------- Read current version ----------
API_FILE="./MyFolder1/appsettings.json"
AUTH_FILE="./MyFolder2/appsettings.json"

[ -f "$API_FILE" ] || die "Missing file: $API_FILE"
[ -f "$AUTH_FILE" ] || die "Missing file: $AUTH_FILE"

CUR_V_API=$(read_json_version "$API_FILE")
CUR_V_AUTH=$(read_json_version "$AUTH_FILE")

CUR_V="$CUR_V_API"
[ -z "$CUR_V" ] && CUR_V="$CUR_V_AUTH"
[ -z "$CUR_V" ] && CUR_V="0.0.0"

gum style "Current version (API): $(gum style --bold $CUR_V_API)"
gum style "Current version (Auth): $(gum style --bold $CUR_V_AUTH)"

### ---------- Ask for new version ----------
style_title "Choose new version"

while true; do
  NEW_V=$(gum input --placeholder "e.g. $CUR_V" --value "$CUR_V" --prompt "Enter new version: ")
  [ -z "$NEW_V" ] && die "Version cannot be empty."

  if ! [[ "$NEW_V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    gum style --foreground 214 "Invalid semver format. Expected: X.Y.Z (e.g., 19.8.5)"
    continue
  fi

  # Block using an existing release branch (local or origin)
  if release_branch_exists "$NEW_V"; then
    gum style --foreground 214 --bold "release/$NEW_V already exists (local or origin). Please choose a DIFFERENT version. ⚠️"
    CUR_V="$NEW_V"   # use the last input as placeholder for convenience
    continue
  fi

  break
done

gum style --foreground 36 "New version: $(gum style --bold $NEW_V)"

### ---------- Update version on develop ----------
style_title "Update version (develop)"

run "Checkout develop" git checkout develop

write_json_version "$API_FILE" "$NEW_V"
write_json_version "$AUTH_FILE" "$NEW_V"

# Stage/commit/push changes
run "Stage changes" git add .

if git diff --cached --quiet; then
  gum style --foreground 244 "No changes detected, skipping commit."
else
  run "Commit" git commit -m "update version to $NEW_V"
  run "Push develop" git push
fi

### ---------- Create release/<version> ----------
style_title "Create and merge release"

run "Checkout master" git checkout master
pull_or_internet_hint "master"

REL_BRANCH="release/$NEW_V"

if branch_exists_local "$REL_BRANCH"; then
  gum style --foreground 214 "Branch already exists: $REL_BRANCH — switching to it."
  run "Checkout $REL_BRANCH" git checkout "$REL_BRANCH"
else
  run "Create $REL_BRANCH" git checkout -b "$REL_BRANCH" master
fi

# Merge develop into release
if ! gum spin --spinner dot --title "Merge develop → $REL_BRANCH" -- git merge --no-ff develop -m "Merge develop into $REL_BRANCH"; then
  echo
  gum style --foreground 1 --bold "⚠️  CONFLICT (develop → $REL_BRANCH)."
  gum style "Please resolve conflicts, commit, and continue manually."
  exit 1
fi

# Push release branch
run "Push $REL_BRANCH" git push --set-upstream origin "$REL_BRANCH"

# Merge release into master
run "Checkout master" git checkout master

if ! gum spin --spinner dot --title "Merge $REL_BRANCH → master" -- git merge --no-ff "$REL_BRANCH" -m "Merge $REL_BRANCH into master"; then
  echo
  gum style --foreground 1 --bold "⚠️  CONFLICT/ERROR ( $REL_BRANCH → master )."
  gum style "Please fix the issue and finish manually."
  exit 1
fi

# Push master
run "Push master" git push

style_title "✅ Done"
gum style --foreground 35 --bold "Release branch: $REL_BRANCH"
gum style --foreground 35 --bold "New version: $NEW_V"
