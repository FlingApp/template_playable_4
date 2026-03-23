#!/usr/bin/env bash
# Сборка playable рекламы из base.html и шаблонов (только bash, без Python).
# Использование: ./build.sh  или  bash build.sh
# Или одна сборка: ./build.sh <template_name> [output_file]
#
# Плейсхолдеры: {{BODY}}, {{LOGO_BASE64}}, {{BANNER_BASE64}}, {{BG_IMAGE_BASE64}},
#              {{GOOGLE_PLAY_URL}}, {{APPSTORE_URL}}, {{BASE_STYLES}}, {{BASE_BODY}}

# Если вызвали через sh — перезапустить через bash
if [ -z "$BASH_VERSION" ]; then
  exec bash "$0" "$@"
fi
set -e

BASE_HTML="base.html"
RESOURCES="resources"
TEMPLATE_DIR="template"
LIMIT_MB=5

# --- Вспомогательные функции ---

read_file_raw() {
  local path="$1"
  local default="${2:-}"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo -n "$default"
  fi
}

# Извлечь содержимое между тегами <style>...</style> и <body>...</body>
extract_base() {
  local base_path="$1"
  local out_styles="$2"
  local out_body="$3"
  [[ -f "$base_path" ]] || return 1

  # Стили: между <style...> и </style> (без первой и последней строки)
  sed -n '/<style[^>]*>/,/<\/[sS][tT][yY][lL][eE]>/p' "$base_path" | sed '1d;$d' > "$out_styles"
  # Тело: между <body...> и </body>
  sed -n '/<body[^>]*>/,/<\/[bB][oO][dD][yY]>/p' "$base_path" | sed '1d;$d' > "$out_body"
}

# Закодировать картинку в base64 (одна строка, без переносов)
image_to_base64() {
  local path="$1"
  if [[ -f "$path" ]]; then
    base64 < "$path" 2>/dev/null | tr -d '\n'
  else
    echo -n ''
  fi
}

# Собрать один шаблон: build_one <template_name> [output_file]
# template_name может быть "unity", "applovin", "google/portrait" и т.д.
build_one() {
  local template_name="$1"
  local output_file="${2:-${template_name//\//_}_output.html}"
  local template_path="${TEMPLATE_DIR}/${template_name}.html"
  local tmpdir
  tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t build)
  trap "rm -rf '$tmpdir'" EXIT

  if [[ ! -f "$BASE_HTML" ]]; then
    echo "Ошибка: файл $BASE_HTML не найден"
    return 1
  fi
  if [[ ! -f "$template_path" ]]; then
    echo "Ошибка: шаблон $template_path не найден"
    return 1
  fi

  echo "Сборка: $template_name -> $output_file"

  extract_base "$BASE_HTML" "$tmpdir/base_styles.txt" "$tmpdir/base_body.txt"

  local body google_play_url appstore_url
  body=$(read_file_raw "$RESOURCES/body.txt" "{{BODY}}")
  google_play_url=$(read_file_raw "$RESOURCES/playstore_url.txt" "{{GOOGLE_PLAY_URL}}")
  appstore_url=$(read_file_raw "$RESOURCES/appstore_url.txt" "{{APPSTORE_URL}}")

  local logo_b64 banner_b64 bg_b64
  logo_b64=$(image_to_base64 "$RESOURCES/logo.png")
  banner_b64=$(image_to_base64 "$RESOURCES/banner.png")
  bg_b64=$(image_to_base64 "$RESOURCES/bg_image.png")

  local logo_data banner_data bg_data
  if [[ -n "$logo_b64" ]]; then
    logo_data="data:image/png;base64,${logo_b64}"
  else
    logo_data="{{LOGO_BASE64}}"
  fi
  if [[ -n "$banner_b64" ]]; then
    banner_data="data:image/png;base64,${banner_b64}"
  else
    banner_data="{{BANNER_BASE64}}"
  fi
  if [[ -n "$bg_b64" ]]; then
    bg_data="data:image/png;base64,${bg_b64}"
  else
    bg_data="{{BG_IMAGE_BASE64}}"
  fi

  # Все подставляемые данные пишем в файлы (многострочные/большие ломают -v)
  printf '%s' "$logo_data" > "$tmpdir/logo_data.txt"
  printf '%s' "$banner_data" > "$tmpdir/banner_data.txt"
  printf '%s' "$bg_data" > "$tmpdir/bg_data.txt"
  printf '%s' "$body" > "$tmpdir/body.txt"
  printf '%s' "$google_play_url" > "$tmpdir/google_play_url.txt"
  printf '%s' "$appstore_url" > "$tmpdir/appstore_url.txt"

  # Обернуть стили в <style></style>
  printf '<style>%s</style>' "$(cat "$tmpdir/base_styles.txt")" > "$tmpdir/base_styles_wrapped.txt"

  # Замена плейсхолдеров через awk (все данные читаем из файлов)
  awk -v tmpdir="$tmpdir" '
  BEGIN {
    base_styles = ""; base_body = ""; body = ""
    logo_data = ""; banner_data = ""; bg_data = ""
    google_play_url = ""; appstore_url = ""
    f = tmpdir "/base_styles_wrapped.txt"
    while ((getline < f) > 0) base_styles = base_styles $0 "\n"
    close(f)
    f = tmpdir "/base_body.txt"
    while ((getline < f) > 0) base_body = base_body $0 "\n"
    close(f)
    f = tmpdir "/body.txt"
    while ((getline < f) > 0) body = body (body ? "\n" : "") $0
    close(f)
    f = tmpdir "/google_play_url.txt"
    while ((getline < f) > 0) google_play_url = google_play_url $0
    close(f)
    f = tmpdir "/appstore_url.txt"
    while ((getline < f) > 0) appstore_url = appstore_url $0
    close(f)
    f = tmpdir "/logo_data.txt"
    while ((getline < f) > 0) logo_data = logo_data $0
    close(f)
    f = tmpdir "/banner_data.txt"
    while ((getline < f) > 0) banner_data = banner_data $0
    close(f)
    f = tmpdir "/bg_data.txt"
    while ((getline < f) > 0) bg_data = bg_data $0
    close(f)
  }
  {
    gsub(/\{\{BASE_STYLES\}\}/, base_styles)
    gsub(/\{\{BASE_BODY\}\}/, base_body)
    gsub(/\{\{TITLE\}\}/, "Playable")
    gsub(/\{\{BODY\}\}/, body)
    gsub(/\{\{GOOGLE_PLAY_URL\}\}/, google_play_url)
    gsub(/\{\{APPSTORE_URL\}\}/, appstore_url)
    gsub(/\{\{LOGO_BASE64\}\}/, logo_data)
    gsub(/\{\{BANNER_BASE64\}\}/, banner_data)
    gsub(/\{\{BG_IMAGE_BASE64\}\}/, bg_data)
    print
  }' "$template_path" > "$output_file"

  rm -rf "$tmpdir"

  # ZIP рядом с HTML (имя внутри архива = basename output_file)
  local zip_name="${output_file%.html}.zip"
  if command -v zip >/dev/null 2>&1; then
    (cd "$(dirname "$output_file")" && zip -j -q "$(basename "$zip_name")" "$(basename "$output_file")")
  else
    powershell.exe -NoProfile -Command \
      "Compress-Archive -Force '$output_file' '$zip_name'"
  fi


  echo "  -> $output_file, $zip_name"
}

# --- Размеры HTML в export/ ---
report_export_sizes() {
  local export_dir="${1:-export}"
  [[ ! -d "$export_dir" ]] && return 0
  local limit_bytes=$((LIMIT_MB * 1024 * 1024))
  echo ""
  echo "Размеры HTML в $export_dir/ (лимит ${LIMIT_MB} MB):"
  find "$export_dir" -type f -name "*.html" 2>/dev/null | sort | while IFS= read -r f; do
    [ -n "$f" ] || continue
    local size
    size=$(wc -c < "$f" 2>/dev/null || echo 0)
    local size_mb
    size_mb=$(awk "BEGIN { printf \"%.2f\", $size/1024/1024 }")
    local rel="${f#$export_dir/}"
    rel="${rel#/}"
    if [[ $size -lt $limit_bytes ]]; then
      echo " ✅ $rel: ${size_mb} MB"
    else
      echo " 🛑 $rel: ${size_mb} MB (перевес)"
    fi
  done
}

# --- Main ---
main() {
  if [[ $# -ge 1 ]]; then
    build_one "$1" "$2"
    report_export_sizes
    exit 0
  fi

  # Папка экспорта: export/ с подпапками по дате и времени (включая секунды)
  local export_dir="export/$(date +%Y-%m-%d_%H-%M-%S)"
  mkdir -p "$export_dir/unity" "$export_dir/applovin" "$export_dir/mintegral" "$export_dir/google"

  build_one "unity"       "$export_dir/unity/unity.html"
  build_one "applovin"    "$export_dir/applovin/applovin.html"
  build_one "mintegral"   "$export_dir/mintegral/mintegral.html"
  build_one "google/portrait"  "$export_dir/google/portrait.html"
  build_one "google/landscape" "$export_dir/google/landscape.html"

  report_export_sizes "$export_dir"
  echo ""
  echo "Готово."
}

main "$@"