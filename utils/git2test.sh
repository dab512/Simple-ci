#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

trap 'error "Ошибка в строке $LINENO. Смотрите вывод выше."' ERR

# ══════════════════════════════════════════
#  git2test — обновление TEST из Git
#  Фаза 1: скачивание из ветки
#  Фаза 2: обновление тестового окружения
# ══════════════════════════════════════════

AUTO_MODE=false
PHASE2=false

for arg in "$@"; do
    case "$arg" in
        --phase2) PHASE2=true ;;
        --auto)   AUTO_MODE=true ;;
    esac
done

# ── ФАЗА 2: обновление тестового окружения ──
if [ "$PHASE2" = true ]; then
    load_config

    if [ "$AUTO_MODE" = false ]; then
        header "Фаза 2: Обновление TEST"
    fi

    # Проверка
    status=$(check_folder_status "$TEST_FOLDER")
    if [ "$status" != "has_content" ]; then
        error "TEST (${TEST_FOLDER}) не развёрнут. Сначала запустите install.sh"
        exit 1
    fi

    # Бэкап
    if [ "$AUTO_MODE" = false ]; then
        info "Создание бэкапа..."
    fi
    backup_path=$(make_backup "$TEST_FOLDER" "test" 2>/dev/null)
    if [ "$AUTO_MODE" = false ]; then
        success "Бэкап: $backup_path"
    fi

    # Синхронизация
    if [ "$AUTO_MODE" = false ]; then
        info "Синхронизация файлов проекта..."
    fi
    sync_files "$PROJECT_DIR" "$TEST_FOLDER"

    # Устанавливаем окружение в манифесте
    set_manifest_env "$TEST_FOLDER" "test"

    # Результат
    local_ver=$(read_manifest_version "$PROJECT_DIR")
    deployed_ver=$(read_manifest_version "$TEST_FOLDER")

    if [ "$AUTO_MODE" = true ]; then
        echo "[Simple-CI] TEST обновлён: ${deployed_ver}"
    else
        echo ""
        success "TEST обновлён!"
        info "Версия в репозитории: ${local_ver}"
        info "Версия на TEST:      ${deployed_ver}"
    fi

    exit 0
fi

# ── ФАЗА 1: скачивание из Git ──
load_config

if [ "$AUTO_MODE" = false ]; then
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════╗"
    echo "  ║       git2test — Обновление       ║"
    echo "  ╚═══════════════════════════════════╝"
    echo -e "${NC}"

    header "Фаза 1: Загрузка из Git"
    info "Ветка: ${GIT_BRANCH}"
fi

# Проверка что TEST развёрнут
status=$(check_folder_status "$TEST_FOLDER")
if [ "$status" != "has_content" ]; then
    error "TEST (${TEST_FOLDER}) не развёрнут. Сначала запустите install.sh"
    exit 1
fi

# Переход в корень репозитория и pull
cd "$ROOT_DIR"

if [ "$AUTO_MODE" = false ]; then
    info "Получение обновлений..."
fi

# Проверяем есть ли изменения в удалённой ветке
git fetch origin "$GIT_BRANCH" 2>/dev/null || {
    error "Не удалось получить обновления из репозитория."
    exit 1
}

LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "none")
REMOTE_HASH=$(git rev-parse "origin/${GIT_BRANCH}" 2>/dev/null || echo "none")

if [ "$LOCAL_HASH" = "$REMOTE_HASH" ] && [ "$AUTO_MODE" = true ]; then
    # В автоматическом режиме — если нет изменений, выходим тихо
    exit 0
fi

git merge "origin/${GIT_BRANCH}" --ff-only 2>/dev/null || {
    warn "Не удалось выполнить fast-forward merge."
    warn "Попытка reset к удалённой ветке..."
    if ! confirm "Сбросить локальные изменения?"; then
        error "Отменено."
        exit 1
    fi
    git reset --hard "origin/${GIT_BRANCH}"
}

if [ "$AUTO_MODE" = false ]; then
    success "Код загружен из ветки ${GIT_BRANCH}"
    info "Передача управления обновлённому скрипту..."
    echo ""
fi

# Передаём управление обновлённой версии скрипта (Фаза 2)
ARGS="--phase2"
if [ "$AUTO_MODE" = true ]; then
    ARGS="--phase2 --auto"
fi

exec "$SCRIPT_DIR/git2test.sh" $ARGS
