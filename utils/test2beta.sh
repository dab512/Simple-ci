#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

trap 'error "Ошибка в строке $LINENO. Смотрите вывод выше."' ERR

# ══════════════════════════════════════════
#  test2beta — продвижение TEST → BETA
# ══════════════════════════════════════════

load_config

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════╗"
echo "  ║     test2beta — TEST → BETA       ║"
echo "  ╚═══════════════════════════════════╝"
echo -e "${NC}"

# --- Валидация ---
test_status=$(check_folder_status "$TEST_FOLDER")
beta_status=$(check_folder_status "$BETA_FOLDER")

if [ "$test_status" != "has_content" ]; then
    error "TEST (${TEST_FOLDER}) пуст или не существует. Нечего продвигать."
    exit 1
fi

if [ "$beta_status" = "not_exists" ]; then
    error "BETA (${BETA_FOLDER}) не существует. Среда не готова."
    exit 1
fi

# --- Статус ---
header "Текущий статус"
print_env_status "TEST" "$TEST_FOLDER" "$TEST_DOMAIN"
print_env_status "BETA" "$BETA_FOLDER" "$BETA_DOMAIN"
echo ""

test_ver=$(read_manifest_version "$TEST_FOLDER")
beta_ver=$(read_manifest_version "$BETA_FOLDER")

info "TEST: ${test_ver}"
info "BETA: ${beta_ver}"
echo ""

# --- Подтверждение ---
warn "Содержимое BETA будет заменено файлами из TEST."
warn "Конфиги, uploads и storage будут сохранены."
echo ""

if ! confirm "Продолжить обновление BETA?"; then
    info "Отменено."
    exit 0
fi

# --- Бэкап ---
if [ "$beta_status" = "has_content" ]; then
    header "Создание бэкапа BETA"
    backup_path=$(make_backup "$BETA_FOLDER" "beta")
fi

# --- Синхронизация ---
header "Синхронизация TEST → BETA"
info "Копирование файлов..."
sync_files "$TEST_FOLDER" "$BETA_FOLDER"

# --- Результат ---
echo ""
separator
new_beta_ver=$(read_manifest_version "$BETA_FOLDER")
success "BETA обновлена!"
info "Версия на BETA: ${new_beta_ver}"
info "Домен: ${BETA_DOMAIN}"
if [ "${beta_status}" = "has_content" ]; then
    info "Бэкап предыдущей версии: ${backup_path}"
fi
echo ""
