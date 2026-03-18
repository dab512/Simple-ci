#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

# ══════════════════════════════════════════
#  status — статус версий всех окружений
# ══════════════════════════════════════════

load_config

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════╗"
echo "  ║       Simple-CI — Статус          ║"
echo "  ╚═══════════════════════════════════╝"
echo -e "${NC}"

# --- Сбор данных ---
get_env_data() {
    local folder="$1"
    local status
    status=$(check_folder_status "$folder")

    if [ "$status" != "has_content" ]; then
        echo "— — — $status"
        return
    fi

    local manifest="$folder/manifest.json"
    if [ ! -f "$manifest" ]; then
        echo "— — — no_manifest"
        return
    fi

    local version build date
    version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")
    build=$(sed -n 's/.*"build"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")
    date=$(sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")

    echo "${version:-—} ${build:-—} ${date:-—} has_content"
}

# Данные источника (project/)
src_data=$(get_env_data "$PROJECT_DIR")
read -r SRC_VER SRC_BUILD SRC_DATE SRC_STATUS <<< "$src_data"

# Данные окружений
test_data=$(get_env_data "$TEST_FOLDER")
read -r TEST_VER TEST_BUILD TEST_DATE TEST_STATUS <<< "$test_data"

beta_data=$(get_env_data "$BETA_FOLDER")
read -r BETA_VER BETA_BUILD BETA_DATE BETA_STATUS <<< "$beta_data"

prod_data=$(get_env_data "$PROD_FOLDER")
read -r PROD_VER PROD_BUILD PROD_DATE PROD_STATUS <<< "$prod_data"

# --- Таблица ---
header "Версии окружений"

# Ширина колонок
printf "${BOLD}  %-10s  %-10s  %-8s  %-12s  %-15s${NC}\n" \
    "Среда" "Версия" "Билд" "Дата" "Статус"
separator

# Функция вывода строки
print_row() {
    local env_name="$1"
    local version="$2"
    local build="$3"
    local date="$4"
    local status="$5"
    local color

    case "$status" in
        has_content)  color="$GREEN"; status_text="Развёрнуто" ;;
        empty)        color="$YELLOW"; status_text="Пустая" ;;
        not_exists)   color="$RED"; status_text="Нет папки" ;;
        no_manifest)  color="$YELLOW"; status_text="Нет манифеста" ;;
        *)            color="$RED"; status_text="Неизвестно" ;;
    esac

    printf "  %-10s  %-10s  %-8s  %-12s  ${color}%-15s${NC}\n" \
        "$env_name" "$version" "$build" "$date" "$status_text"
}

print_row "SOURCE" "$SRC_VER" "$SRC_BUILD" "$SRC_DATE" "$SRC_STATUS"
print_row "TEST"   "$TEST_VER" "$TEST_BUILD" "$TEST_DATE" "$TEST_STATUS"
print_row "BETA"   "$BETA_VER" "$BETA_BUILD" "$BETA_DATE" "$BETA_STATUS"
print_row "PROD"   "$PROD_VER" "$PROD_BUILD" "$PROD_DATE" "$PROD_STATUS"

echo ""

# --- Сравнение версий ---
header "Анализ"

compare_versions() {
    local name1="$1" ver1="$2" name2="$3" ver2="$4"
    if [ "$ver1" = "—" ] || [ "$ver2" = "—" ]; then
        return
    fi
    if [ "$ver1" = "$ver2" ]; then
        success "${name1} и ${name2}: одинаковая версия (${ver1})"
    else
        warn "${name1} (${ver1}) ≠ ${name2} (${ver2})"
    fi
}

compare_versions "SOURCE" "$SRC_VER"  "TEST" "$TEST_VER"
compare_versions "TEST"   "$TEST_VER" "BETA" "$BETA_VER"
compare_versions "BETA"   "$BETA_VER" "PROD" "$PROD_VER"

echo ""

# --- Домены ---
header "Домены"
echo -e "  TEST:  ${CYAN}${TEST_DOMAIN}${NC}  →  ${TEST_FOLDER}"
echo -e "  BETA:  ${CYAN}${BETA_DOMAIN}${NC}  →  ${BETA_FOLDER}"
echo -e "  PROD:  ${CYAN}${PROD_DOMAIN}${NC}  →  ${PROD_FOLDER}"
echo ""

# --- Подсказки ---
if [ "$SRC_VER" != "$TEST_VER" ] && [ "$SRC_VER" != "—" ] && [ "$TEST_VER" != "—" ]; then
    info "Подсказка: SOURCE отличается от TEST → запустите ${CYAN}utils/git2test.sh${NC}"
fi
if [ "$TEST_VER" != "$BETA_VER" ] && [ "$TEST_VER" != "—" ] && [ "$BETA_VER" != "—" ]; then
    info "Подсказка: TEST отличается от BETA → запустите ${CYAN}utils/test2beta.sh${NC}"
fi
if [ "$BETA_VER" != "$PROD_VER" ] && [ "$BETA_VER" != "—" ] && [ "$PROD_VER" != "—" ]; then
    info "Подсказка: BETA отличается от PROD → запустите ${CYAN}utils/beta2prod.sh${NC}"
fi
echo ""
