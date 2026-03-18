#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

trap 'error "Ошибка в строке $LINENO. Смотрите вывод выше."' ERR

# ══════════════════════════════════════════
#  Установщик Simple-CI
# ══════════════════════════════════════════

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════╗"
echo "  ║         Simple-CI Install         ║"
echo "  ║   Настройка среды развёртывания   ║"
echo "  ╚═══════════════════════════════════╝"
echo -e "${NC}"

# --- Проверка существующего конфига ---
if [ -f "$ENV_FILE" ]; then
    header "Обнаружена существующая конфигурация"
    source "$ENV_FILE"
    echo -e "  TEST:  ${TEST_DOMAIN:-—}  →  ${TEST_FOLDER:-—}"
    echo -e "  BETA:  ${BETA_DOMAIN:-—}  →  ${BETA_FOLDER:-—}"
    echo -e "  PROD:  ${PROD_DOMAIN:-—}  →  ${PROD_FOLDER:-—}"
    echo ""
    if ! confirm "Перенастроить?"; then
        info "Отменено. Текущая конфигурация сохранена."
        exit 0
    fi
    echo ""
fi

# ── Окружение TEST ──
header "Окружение TEST"
ask "Домен для test" TEST_DOMAIN "test.localhost"
ask "Папка на сервере для test" TEST_FOLDER "/var/www/test"

# ── Окружение BETA ──
header "Окружение BETA"
ask "Домен для beta" BETA_DOMAIN "beta.localhost"
ask "Папка на сервере для beta" BETA_FOLDER "/var/www/beta"

# ── Окружение PROD ──
header "Окружение PROD"
ask "Домен для prod" PROD_DOMAIN "prod.localhost"
ask "Папка на сервере для prod" PROD_FOLDER "/var/www/prod"

# ── БД: beta + prod (общая) ──
header "База данных для BETA и PROD (общая)"
ask "Хост БД" SHARED_DB_HOST "localhost"
ask "Имя БД" SHARED_DB_NAME "app_production"
ask "Пользователь БД" SHARED_DB_USER "app_user"
ask_password "Пароль БД" SHARED_DB_PASS

# ── БД: test (отдельная) ──
header "База данных для TEST (отдельная)"
ask "Хост БД" TEST_DB_HOST "localhost"
ask "Имя БД" TEST_DB_NAME "app_test"
ask "Пользователь БД" TEST_DB_USER "test_user"
ask_password "Пароль БД" TEST_DB_PASS

# ── Git ──
header "Настройки Git"
ask "URL репозитория" GIT_REPO_URL ""
ask "Ветка для деплоя" GIT_BRANCH "main"

# ── Сохранение ──
separator
save_config
echo ""

# ══════════════════════════════════════════
#  Статус окружений
# ══════════════════════════════════════════

header "Статус окружений"
print_env_status "TEST" "$TEST_FOLDER" "$TEST_DOMAIN"
print_env_status "BETA" "$BETA_FOLDER" "$BETA_DOMAIN"
print_env_status "PROD" "$PROD_FOLDER" "$PROD_DOMAIN"
echo ""

# ══════════════════════════════════════════
#  Первичное развёртывание
# ══════════════════════════════════════════

header "Первичное развёртывание"

deploy_env() {
    local env_name="$1"
    local folder="$2"
    local domain="$3"
    local status

    status=$(check_folder_status "$folder")

    case "$status" in
        not_exists)
            warn "${env_name}: папка ${folder} не существует. Среда не готова."
            warn "Создайте папку и перезапустите установщик."
            ;;
        has_content)
            warn "${env_name}: папка ${folder} уже содержит файлы. Пропускаем."
            ;;
        empty)
            if confirm "Развернуть ${env_name} в ${folder}?"; then
                info "Копирование файлов проекта..."
                cp -a "$PROJECT_DIR/." "$folder/"
                success "${env_name} развёрнут в ${folder}"
            else
                info "${env_name}: пропущено по запросу."
            fi
            ;;
    esac
}

deploy_env "TEST" "$TEST_FOLDER" "$TEST_DOMAIN"
deploy_env "BETA" "$BETA_FOLDER" "$BETA_DOMAIN"
deploy_env "PROD" "$PROD_FOLDER" "$PROD_DOMAIN"

# ══════════════════════════════════════════
#  Автодеплой на тест при обновлении ветки
# ══════════════════════════════════════════

header "Автоматическое обновление TEST"
info "При обновлении ветки '${GIT_BRANCH}' можно автоматически"
info "запускать git2test.sh для обновления тестового окружения."
echo ""
echo -e "  ${BOLD}1${NC}) Настроить cron (проверка каждые 5 минут)"
echo -e "  ${BOLD}2${NC}) Сгенерировать git post-receive hook"
echo -e "  ${BOLD}3${NC}) Пропустить"
echo ""
echo -ne "${BOLD}Выберите вариант${NC} [3]: "
read -r autodeploy_choice
autodeploy_choice="${autodeploy_choice:-3}"

case "$autodeploy_choice" in
    1)
        # --- Cron ---
        CRON_CMD="*/5 * * * * cd ${ROOT_DIR} && ${SCRIPT_DIR}/git2test.sh --auto >> /var/log/simple-ci.log 2>&1"
        info "Будет добавлена cron-задача:"
        echo -e "  ${CYAN}${CRON_CMD}${NC}"
        echo ""
        if confirm "Добавить в crontab?"; then
            (crontab -l 2>/dev/null || true; echo "$CRON_CMD") | crontab -
            success "Cron-задача добавлена."
        else
            info "Пропущено. Вы можете добавить вручную:"
            echo -e "  ${CYAN}${CRON_CMD}${NC}"
        fi
        ;;
    2)
        # --- Git post-receive hook ---
        HOOK_PATH="$ROOT_DIR/.git/hooks/post-receive"
        info "Будет создан hook: ${HOOK_PATH}"
        echo ""
        if confirm "Создать post-receive hook?"; then
            cat > "$HOOK_PATH" << 'HOOKEOF'
#!/usr/bin/env bash
# Simple-CI: автоматический деплой на тест при push
while read -r oldrev newrev refname; do
    BRANCH=$(basename "$refname")
    source "$(dirname "$0")/../../.env"
    if [ "$BRANCH" = "$GIT_BRANCH" ]; then
        echo "[Simple-CI] Обновление ветки $BRANCH — запуск git2test..."
        "$(dirname "$0")/../../utils/git2test.sh" --auto
    fi
done
HOOKEOF
            chmod +x "$HOOK_PATH"
            success "Hook создан: ${HOOK_PATH}"
        else
            info "Пропущено."
        fi
        ;;
    *)
        info "Автодеплой не настроен. Используйте git2test.sh вручную."
        ;;
esac

# ══════════════════════════════════════════
#  Готово
# ══════════════════════════════════════════

echo ""
separator
echo ""
success "Установка завершена!"
echo ""
info "Доступные команды:"
echo -e "  ${CYAN}utils/status.sh${NC}     — статус окружений"
echo -e "  ${CYAN}utils/git2test.sh${NC}   — обновить тест из git"
echo -e "  ${CYAN}utils/test2beta.sh${NC}  — продвинуть тест → бета"
echo -e "  ${CYAN}utils/beta2prod.sh${NC}  — продвинуть бета → прод"
echo ""
