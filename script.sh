#!/usr/bin/env bash
# wp-release.sh
# WP Backend için sürüm yükseltme + release akışı (gum ile görsellikli)
# Çalıştırmadan önce: 'gum' kurulu olmalı. 'jq' yoksa sed fallback kullanılır.

set -o pipefail

### ---------- Yardımcılar ----------
die() { echo -e "\n$(gum style --foreground 1 --bold "Hata:") $1\n" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' yüklü değil. Lütfen kur ve tekrar dene."
}

style_title() {
  gum style --bold --border normal --padding "1 2" --margin "1 0" --border-foreground 212 "$1"
}

run() {
  # gum spin ile komut çalıştır ve hatada net mesaj ver
  local title="$1"; shift
  if ! gum spin --spinner dot --title "$title" -- "$@"; then
    die "'$title' adımında hata oluştu."
  fi
}

pull_or_internet_hint() {
  # git pull dener; başarısızsa Internet/VPN ipucu gösterir
  local br="$1"
  if ! gum spin --spinner dot --title "Pull: $br" -- git pull --ff-only; then
    echo -e "\n$(gum style --italic --foreground 1 'Internet? VPN? 🙄')\n"
    exit 1
  fi
}

ensure_clean_worktree() {
  if ! git diff-index --quiet HEAD --; then
    gum style --foreground 214 "Çalışma dizininde commit'lenmemiş değişiklikler var."
    if gum confirm "Değişiklikleri geçici olarak stash'leyelim mi?"; then
      run "Stash" git stash push -u -m "auto-stash by wp-release.sh"
    else
      die "Lütfen değişiklikleri commit/stash edip tekrar deneyin."
    fi
  fi
}

git_branch_exists() {
  git rev-parse --verify "$1" >/dev/null 2>&1
}

read_json_version() {
  local file="$1"
  local val=""
  if [ -f "$file" ]; then
    if command -v jq >/dev/null 2>&1; then
      val="$(jq -r '.Version // empty' "$file")"
    fi
    if [ -z "$val" ]; then
      # jq yoksa veya alan boşsa sed/grep ile çıkar
      val="$(grep -oE '"Version"\s*:\s*"[^"]+"' "$file" | head -1 | sed -E 's/.*"Version"\s*:\s*"([^"]+)".*/\1/')"
    fi
  fi
  echo "$val"
}

write_json_version() {
  local file="$1"
  local newv="$2"

  [ -f "$file" ] || die "Dosya bulunamadı: $file"

  if command -v jq >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp)"
    jq --arg v "$newv" '.Version = $v' "$file" > "$tmp" || die "$file güncellenemedi (jq)."
    mv "$tmp" "$file"
  else
    # jq yoksa: sed ile "Version": "..." alanını değiştir
    if grep -q '"Version"\s*:' "$file"; then
      # macOS/BSD sed ile uyum: -i'' dilimsiz backup
      sed -E -i'' 's/"Version"\s*:\s*"[^"]*"/"Version": "'"$newv"'"/' "$file" || die "$file güncellenemedi (sed)."
    else
      die "$file içinde 'Version' anahtarı bulunamadı."
    fi
  fi
}

release_branch_exists() {
  local v="$1"
  local r="release/$v"

  # Lokal branch
  if git show-ref --verify --quiet "refs/heads/$r"; then
    return 0
  fi
  # Remote-tracking branch
  if git show-ref --verify --quiet "refs/remotes/origin/$r"; then
    return 0
  fi
  # Ek güvence: fetch güncel değilse doğrudan remote'a bak
  if git ls-remote --exit-code --heads origin "$r" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

### ---------- Ön kontroller ----------
need_cmd git
need_cmd gum

[ -d .git ] || die "Bu script'i repo kökünde çalıştırmalısın ('.git' bulunamadı)."

style_title "WP Release Asistanı"

### ---------- Repo seçimi ----------
CHOICE=$(gum choose --header "Hangi repo?" "WP Backend" "WP Frontend")
[ -z "$CHOICE" ] && die "Bir seçim yapmalısın."

if [ "$CHOICE" = "WP Frontend" ]; then
  gum style --foreground 212 "Frontend akışını sonra ekleyeceğiz. Şimdilik çıkıyorum. 👋"
  exit 0
fi

### ---------- Backend akışı ----------
style_title "Backend: ön hazırlık"

# Varsa otomatik stash
ensure_clean_worktree

# Remote'ları al
run "Git fetch" git fetch --all --prune

# master pull
if git_branch_exists master; then
  run "Checkout master" git checkout master
  pull_or_internet_hint "master"
else
  die "Branch bulunamadı: master"
fi

# develop pull
if git_branch_exists develop; then
  run "Checkout develop" git checkout develop
  pull_or_internet_hint "develop"
else
  die "Branch bulunamadı: develop"
fi

### ---------- Mevcut versiyonu oku ----------
API_FILE="./MyFolder1/appsettings.json"
AUTH_FILE="./MyFolder2/appsettings.json"

# Kullanıcının yazdığı path'teki olası yazım hatalarını tolere etmeye çalış:
if [ ! -f "$AUTH_FILE" ]; then
  # bazen yanlışlıkla başında nokta yazılıyor ya da 'jon' yazılıyor olabilir
  [ -f ".MyFolder1/appsettings.json" ] && AUTH_FILE=".MyFolder2/appsettings.json"
  [ -f "./MyFolder1/appsettings.jon" ] && AUTH_FILE="./MyFolder2/appsettings.jon"
fi

[ -f "$API_FILE" ] || die "Dosya yok: $API_FILE"
[ -f "$AUTH_FILE" ] || die "Dosya yok: $AUTH_FILE"

CUR_V_API=$(read_json_version "$API_FILE")
CUR_V_AUTH=$(read_json_version "$AUTH_FILE")

CUR_V="$CUR_V_API"
[ -z "$CUR_V" ] && CUR_V="$CUR_V_AUTH"

[ -z "$CUR_V" ] && CUR_V="0.0.0"

gum style "Mevcut versiyon (API): $(gum style --bold $CUR_V_API)"
gum style "Mevcut versiyon (Auth): $(gum style --bold $CUR_V_AUTH)"

### ---------- Yeni versiyonu sor ----------
style_title "Versiyon seç"

while true; do
  NEW_V=$(gum input --placeholder "örn: 19.8.5" --value "$CUR_V" --prompt "Yeni versiyonu yaz: ")
  [ -z "$NEW_V" ] && die "Versiyon boş olamaz."

  if ! [[ "$NEW_V" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    gum style --foreground 214 "Geçersiz sürüm formatı. Beklenen: X.Y.Z (örn: 19.8.5)"
    continue
  fi

  if release_branch_exists "$NEW_V"; then
    gum style --foreground 214 --bold "Hâlihazırda release/$NEW_V var. Yeni numara seç ⚠️"
    # Son girileni placeholder yaparak tekrar sor
    CUR_V="$NEW_V"
    continue
  fi

  break
done

gum style --foreground 36 "Yeni versiyon: $(gum style --bold $NEW_V)"

### ---------- Versiyonu develop'ta güncelle ----------
style_title "Versiyon güncelle (develop)"

run "Checkout develop" git checkout develop

write_json_version "$API_FILE"  "$NEW_V"
write_json_version "$AUTH_FILE" "$NEW_V"

# Değişiklikleri ekle/commit/push
run "Stage changes" git add "$API_FILE" "$AUTH_FILE"

if git diff --cached --quiet; then
  gum style --foreground 244 "Değişiklik yok, commit atlanıyor."
else
  run "Commit" git commit -m "update version to $NEW_V"
  run "Push develop" git push
fi

### ---------- release/<versiyon> oluştur ----------
style_title "Release oluştur ve birleştir"

run "Checkout master" git checkout master
pull_or_internet_hint "master"

REL_BRANCH="release/$NEW_V"

if git_branch_exists "$REL_BRANCH"; then
  gum style --foreground 214 "Branch zaten var: $REL_BRANCH — ona geçiyorum."
  run "Checkout $REL_BRANCH" git checkout "$REL_BRANCH"
else
  run "Create $REL_BRANCH" git checkout -b "$REL_BRANCH" master
fi

# develop'ı release'e merge et
if ! gum spin --spinner dot --title "Merge develop → $REL_BRANCH" -- git merge --no-ff develop -m "Merge develop into $REL_BRANCH"; then
  echo
  gum style --foreground 1 --bold "⚠️  ÇAKIŞMA OLUŞTU (develop → $REL_BRANCH)."
  gum style "Lütfen çatışmaları çöz, commit et ve işlemi manuel sürdür."
  exit 1
fi

# release branch push
run "Push $REL_BRANCH" git push -u origin "$REL_BRANCH"

# release'i master'a merge et
run "Checkout master" git checkout master

if ! gum spin --spinner dot --title "Merge $REL_BRANCH → master" -- git merge --no-ff "$REL_BRANCH" -m "Merge $REL_BRANCH into master"; then
  echo
  gum style --foreground 1 --bold "⚠️  ÇAKIŞMA/HATA ( $REL_BRANCH → master )."
  gum style "Hata çıktı. Lütfen problemi çöz ve işlemi manuel tamamla."
  exit 1
fi

# master push
pull_or_internet_hint "master (son push)"
run "Push master" git push

# --- develop'u master/release ile senkronla ---
style_title "Develop'i senkronla"

run "Checkout develop" git checkout develop
pull_or_internet_hint "develop"

# release'i develop'a geri merge et
if ! gum spin --spinner dot --title "Merge $REL_BRANCH → develop" -- \
  git merge --no-ff "$REL_BRANCH" -m "Merge $REL_BRANCH back into develop"; then
  echo
  gum style --foreground 1 --bold "⚠️  ÇAKIŞMA/HATA ($REL_BRANCH → develop)."
  gum style "Lütfen çatışmaları çöz (develop'ta), commit et ve işlemi manuel tamamla."
  exit 1
fi

run "Push develop" git push

style_title "✅ İşlem tamam"
gum style --foreground 35 --bold "Release branch: $REL_BRANCH"
gum style --foreground 35 --bold "Yeni sürüm: $NEW_V"

