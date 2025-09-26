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

### ---------- UI / Theme ----------
# Renk paleti (Gum 256-color)
CLR_PRIMARY=212      # Pembe-lila (başlık)
CLR_INFO=39          # Mavi (bilgi)
CLR_WARN=214         # Sarı (uyarı)
CLR_ERR=1            # Kırmızı (hata)
CLR_OK=35            # Yeşil-mor arası (başarı)
CLR_DIM=244          # Soluk gri (ikincil metin)
SPINNER="dot"

ICON_OK="✅"
ICON_INFO="ℹ️"
ICON_WARN="⚠️"
ICON_ERR="🛑"
ICON_RUN="🚀"


# # ---------- Animation (confetti/fireworks) ----------
# ANIMATE="${ANIMATE:-1}"   # ANIMATE=0 ile kapat

# # Basit ve taşınabilir zaman ölçer (ms)
# _now_ms() { echo "$(( $(date +%s) * 1000 ))"; }  # macOS uyumlu (yaklaşık ms)

# release_animation() {
#   # TTY değilse ya da ANIMATE=0 ise atla
#   if [ "$ANIMATE" != "1" ] || [ ! -t 1 ]; then return 0; fi

#   # Ekranı alternatif ekrana al (varsa), imleci gizle
#   tput smcup 2>/dev/null || true
#   tput civis 2>/dev/null || true
#   trap 'tput cnorm 2>/dev/null || true; tput rmcup 2>/dev/null || true' EXIT

#   local cols rows
#   cols=$(tput cols 2>/dev/null || echo 80)
#   rows=$(tput lines 2>/dev/null || echo 24)

#   # Renk paleti ve karakterler
#   local colors=(196 202 208 214 118 51 39 201 207 93 75 45 33 141 129)
#   local glyphs=("*" "+" "·" "•" "★" "✦" "✧" "✸" "✺" "❉" "❋")

#   # Süre ve yoğunluk
#   local duration_ms=1600
#   local step_ms=40                 # ~25 fps
#   local step_s; step_s=$(printf '0.%03d' "$step_ms")  # 40ms -> "0.040"
#   local bursts=30

#   # Hafif fade efekti için düşük yoğunluk
#   printf "\033[2m"

#   # Çizim döngüsü
#   local start_ms now_ms elapsed i x y c g
#   start_ms=$(_now_ms)
#   while :; do
#     for ((i=0; i<bursts; i++)); do
#       x=$(( RANDOM % (cols>2?cols-2:1) + 1 ))
#       y=$(( RANDOM % (rows>3?rows-3:1) + 2 ))
#       c=${colors[$RANDOM % ${#colors[@]}]}
#       g=${glyphs[$RANDOM % ${#glyphs[@]}]}
#       printf "\033[%d;%dH\033[38;5;%dm%s" "$y" "$x" "$c" "$g"
#     done

#     # Alt satırda ufak “akış” izi
#     printf "\033[%d;1H\033[0m" "$rows"
#     sleep "$step_s"

#     now_ms=$(_now_ms)
#     elapsed=$(( now_ms - start_ms ))
#     [ "$elapsed" -ge "$duration_ms" ] && break
#   done

#   # Temizle ve geri dön
#   printf "\033[0m"
#   # smcup kullandığımız için rmcup eski ekranı geri getirir
#   # Ekstra: tput rmcup EXIT trap'inde zaten çağrılıyor.
# }

# ---------- Fancy 2s Celebration Animation (v2, robust) ----------
ANIMATE="${ANIMATE:-1}"   # export ANIMATE=0 ile kapat

celebrate_fancy_2s() {
  # TTY değilse ya da ANIMATE=0 ise atla
  if [ "$ANIMATE" != "1" ] || [ ! -t 1 ]; then return 0; fi

  # İmleci gizle; çıkışta geri getir
  tput civis 2>/dev/null || true
  trap 'tput cnorm 2>/dev/null || true' EXIT

  local cols rows cx cy
  cols=$(tput cols 2>/dev/null || echo 80)
  rows=$(tput lines 2>/dev/null || echo 24)
  cx=$(( cols / 2 ))
  cy=$(( rows / 2 ))

  # Renk ve karakter setleri
  local RESET="\033[0m"
  local PAL=(196 202 208 214 220 118 51 39 201 207 93 75 45 33 141 129)
  local GOLD=220 WHITE=231 OK=35
  local SPARKS=("·" "•" "*" "✦" "✶" "✷" "✸" "✺")
  local CONFETTI=("◆" "●" "■" "▲" "★" "✶" "✹" "+")

  local fps=25 total_ms=2000 total_frames=$(( total_ms * fps / 1000 ))
  local phase1=$(( total_frames * 30 / 100 ))   # ~0.6s: burst
  local phase2=$(( total_frames * 40 / 100 ))   # ~0.8s: confetti
  local phase3=$(( total_frames - phase1 - phase2 )) # ~0.6s: banner

  color() { printf "\033[38;5;%sm%s\033[0m" "$1" "$2"; }
  draw()  { # y x text
    printf "\033[%d;%dH%s" "$1" "$2" "$3"
  }

  burst_frame() { # frame_index
    local k="$1" r steps=16 i x y ch col
    r=$(( 1 + (k * 6 / (phase1>0?phase1:1)) ))   # yarıçap 1..6
    for ((i=0;i<steps;i++)); do
      case "$i" in
        0)  x=$r; y=0 ;;
        1)  x=$(( r-1 )); y=-1 ;;
        2)  x=$(( r-1 )); y=-2 ;;
        3)  x=$(( r-2 )); y=-3 ;;
        4)  x=0; y=-$r ;;
        5)  x=-2; y=-3 ;;
        6)  x=-1; y=-2 ;;
        7)  x=-1; y=-1 ;;
        8)  x=-$r; y=0 ;;
        9)  x=-1; y=1 ;;
        10) x=-1; y=2 ;;
        11) x=-2; y=3 ;;
        12) x=0; y=$r ;;
        13) x=2; y=3 ;;
        14) x=1; y=2 ;;
        15) x=1; y=1 ;;
      esac
      ch="${SPARKS[$(( (k+i) % ${#SPARKS[@]} ))]}"
      col="${PAL[$(( (k+i) % ${#PAL[@]} ))]}"
      draw $(( cy + y )) $(( cx + x )) "$(color "$col" "$ch")"
    done
    draw "$cy" "$cx" "$(color $GOLD '✹')"
  }

  confetti_frame() { # frame_index
    local k="$1" n=120 i x y ch col
    for ((i=0;i<n;i++)); do
      x=$(( (RANDOM % (cols-4)) + 2 ))
      y=$(( (RANDOM % (rows-4)) + 2 ))
      ch="${CONFETTI[$(( RANDOM % ${#CONFETTI[@]} ))]}"
      col="${PAL[$(( (k+i*3) % ${#PAL[@]} ))]}"
      draw "$y" "$x" "$(color "$col" "$ch")"
    done
  }

  banner_frame() { # frame_index
    local k="$1" msg="RELEASE  COMPLETE" col bcol width left top
    case $(( k % 4 )) in
      0|2) col=$OK;   bcol=$GOLD ;;
      1|3) col=$GOLD; bcol=$WHITE ;;
    esac
    width=$(( ${#msg} + 4 ))
    left=$(( (cols - width - 2) / 2 ))
    [ $left -lt 1 ] && left=1
    top=$(( cy - 1 ))

    local border_top border_mid border_bot
    border_top="$(printf "\033[38;5;%sm┏%s┓\033[0m" "$bcol" "$(printf '━%.0s' $(seq 1 $width))")"
    border_mid="$(printf "\033[38;5;%sm┃  \033[1m\033[38;5;%sm%s\033[0m\033[38;5;%sm  ┃\033[0m" "$bcol" "$col" "$msg" "$bcol")"
    border_bot="$(printf "\033[38;5;%sm┗%s┛\033[0m" "$bcol" "$(printf '━%.0s' $(seq 1 $width))")"

    draw "$top"       "$left" "$border_top"
    draw $((top + 1)) "$left" "$border_mid"
    draw $((top + 2)) "$left" "$border_bot"
  }

  local f
  for ((f=0; f<total_frames; f++)); do
    # tam ekran temizle + home
    printf "\033[2J\033[H"

    if [ $f -lt $phase1 ]; then
      burst_frame "$f"
    elif [ $f -lt $(( phase1 + phase2 )) ]; then
      burst_frame "$phase1"
      confetti_frame "$f"
    else
      confetti_frame "$f"
      banner_frame $(( f - phase1 - phase2 ))
    fi

    # 25 FPS
    sleep 0.040
  done

  # Finali kısa süre gösterip temizle
  sleep 0.15
  printf "$RESET\033[2J\033[H"
}


ui_hr() {
  gum style --foreground "$CLR_DIM" "$(printf '—%.0s' {1..60})"
}

ui_banner() {
  local title="$1"
  gum style \
    --border double --margin "1 0" --padding "1 3" \
    --border-foreground "$CLR_PRIMARY" --bold "$title"
}

ui_section() {
  local title="$1"
  gum style \
    --border normal --margin "1 0" --padding "0 2" \
    --border-foreground "$CLR_PRIMARY" --bold "$title"
}

ui_note()   { gum style --foreground "$CLR_INFO"  "$ICON_INFO  $*"; }
ui_warn()   { gum style --foreground "$CLR_WARN"  "$ICON_WARN  $*"; }
ui_error()  { gum style --foreground "$CLR_ERR"   "$ICON_ERR  $*"; }
ui_success(){ gum style --foreground "$CLR_OK" --bold "$ICON_OK  $*"; }

# Eski style_title yerine daha “fancy” bir bölüm başlığı
style_title() { ui_section "$1"; }

# Komut çalıştıran helper: spinner + outcome rozeti
run() {
  local title="$1"; shift
  if gum spin --spinner "$SPINNER" --title "$title" -- "$@"; then
    gum style --foreground "$CLR_OK"  "$ICON_OK  $title"
    gum style --foreground "$CLR_DIM" "     ↳ $*"
  else
    ui_error "Failed at step: '$title'"
    gum style --foreground "$CLR_DIM" "     ↳ $*"
    exit 1
  fi
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
    ui_warn "Branch '$br' has no upstream set."
    if gum confirm "Set upstream and push '$br' to origin?"; then
      run "Push '$br' (set upstream)" git push -u origin "$br"
    else
      ui_error "Upstream not set. Cannot continue safely."
      exit 1
    fi
  else
    local ahead
    ahead="$(branch_ahead_count "$br")"
    if [ "${ahead:-0}" -gt 0 ]; then
      gum style --foreground "$CLR_WARN" --bold "$ICON_WARN  Branch '$br' has $ahead unpushed commit(s)."
      git log --oneline "$br@{u}..$br" | sed 's/^/  • /'
      echo
      if gum confirm "Push '$br' to origin now?"; then
        run "Push '$br'" git push
      else
        ui_error "Unpushed commits on '$br'. Aborting."
        exit 1
      fi
    else
      ui_success "Branch '$br' is up-to-date with upstream"
    fi
  fi
}

pull_or_internet_hint() {
  local br="$1"
  ui_note "Checking Internet/VPN connectivity for '$br'…"
  if ! gum spin --spinner "$SPINNER" --title "Pull: $br" -- git pull --ff-only; then
    echo
    ui_error "Pull failed. Possible Internet/VPN issue."
    gum style --italic --foreground "$CLR_WARN" "Hint: Is your VPN connected?"
    echo
    exit 1
  fi
  ui_success "Pulled '$br' successfully"
}

ensure_clean_worktree() {
  if ! git diff-index --quiet HEAD --; then
    ui_warn "You have uncommitted changes in the working tree."
    if gum confirm "Stash changes temporarily?"; then
      run "Stash" git stash push -u -m "auto-stash by wp-release.sh"
    else
      ui_error "Please commit/stash your changes and retry."
      exit 1
    fi
  fi
  ui_success "Verified clean worktree"
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

  echo "Set version $2 to $1"
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

# style_title "WP Release Assistant"
ui_banner "WP Release Assistant"
ui_note   "Prereqs: gum, jq (optional). $(gum style --foreground $CLR_DIM 'Sed/grep fallback active if jq is missing.')"
ui_hr

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

gum style --foreground "$CLR_OK" "New version: $(gum style --bold $NEW_V)"
ui_hr


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

celebrate_fancy_2s

ui_banner "✅  Release Complete"
gum join \
  --horizontal \
  "$(gum style --border normal --padding '0 2' --border-foreground $CLR_OK "Release branch: $(gum style --bold $REL_BRANCH)")" \
  "$(gum style --border normal --padding '0 2' --border-foreground $CLR_PRIMARY "New version: $(gum style --bold $NEW_V)")"

ui_note "Tip: Check Jenkins: https://jenkins.afiniti.com/job/Engr_Portal_Backend_Service"
ui_hr

