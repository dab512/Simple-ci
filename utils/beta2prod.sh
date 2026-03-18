#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

trap 'error "Ошибка в строке $LINENO. Смотрите вывод выше."' ERR

# ══════════════════════════════════════════
#  beta2prod — продвижение BETA → PROD
# ══════════════════════════════════════════

load_config

echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════╗"
echo "  ║    beta2prod — BETA → PROD        ║"
echo "  ╚═══════════════════════════════════╝"
echo -e "${NC}"

# --- Валидация ---
beta_status=$(check_folder_status "$BETA_FOLDER")
prod_status=$(check_folder_status "$PROD_FOLDER")

if [ "$beta_status" != "has_content" ]; then
    error "BETA (${BETA_FOLDER}) пуст или не существует. Нечего продвигать."
    exit 1
fi

if [ "$prod_status" = "not_exists" ]; then
    error "PROD (${PROD_FOLDER}) не существует. Среда не готова."
    exit 1
fi

# --- Статус ---
header "Текущий статус"
print_env_status "BETA" "$BETA_FOLDER" "$BETA_DOMAIN"
print_env_status "PROD" "$PROD_FOLDER" "$PROD_DOMAIN"
echo ""

beta_ver=$(read_manifest_version "$BETA_FOLDER")
prod_ver=$(read_manifest_version "$PROD_FOLDER")

info "BETA: ${beta_ver}"
info "PROD: ${prod_ver}"
echo ""

# --- Двойное подтверждение ---
echo -e "  ${RED}${BOLD}╔══════════════════════════════════════╗${NC}"
echo -e "  ${RED}${BOLD}║  ВНИМАНИЕ: обновление PRODUCTION!    ║${NC}"
echo -e "  ${RED}${BOLD}╚══════════════════════════════════════╝${NC}"
echo ""
warn "Содержимое PROD будет заменено файлами из BETA."
warn "Конфиги, uploads и storage будут сохранены."
echo ""

if ! confirm "Вы уверены, что хотите обновить PROD?"; then
    info "Отменено."
    exit 0
fi

echo ""
echo -ne "${BOLD}Введите ${RED}DEPLOY${NC}${BOLD} для подтверждения: ${NC}"
read -r deploy_confirm

if [ "$deploy_confirm" != "DEPLOY" ]; then
    error "Неверное подтверждение. Отменено."
    exit 1
fi

# --- Бэкап ---
if [ "$prod_status" = "has_content" ]; then
    header "Создание бэкапа PROD"
    backup_path=$(make_backup "$PROD_FOLDER" "prod")
fi

# --- Синхронизация ---
header "Синхронизация BETA → PROD"
info "Копирование файлов..."
sync_files "$BETA_FOLDER" "$PROD_FOLDER"

# --- Результат ---
echo ""
separator
new_prod_ver=$(read_manifest_version "$PROD_FOLDER")
success "PROD обновлён!"
info "Версия на PROD: ${new_prod_ver}"
info "Домен: ${PROD_DOMAIN}"
if [ "${prod_status}" = "has_content" ]; then
    info "Бэкап предыдущей версии: ${backup_path}"
fi
echo ""
