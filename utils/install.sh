#!/usr/bin/env bash
set -euo pipefail

# ══════════════════════════════════════════
#  Simple-CI Install
#  Автономный установщик — можно скачать
#  отдельно и запустить без репозитория.
# ══════════════════════════════════════════

# --- Цвета (встроены для автономной работы) ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

_info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
_success() { echo -e "${GREEN}✔${NC}  $*"; }
_warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
_error()   { echo -e "${RED}✖${NC}  $*"; }

_header() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ $* ━━━${NC}"
    echo ""
}

_separator() {
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
}

_ask() {
    local prompt="$1"
    local var_name="$2"
    local default="${3:-}"
    local input

    if [ -n "$default" ]; then
        echo -ne "${BOLD}${prompt}${NC} [${default}]: "
    else
        echo -ne "${BOLD}${prompt}${NC}: "
    fi

    read -r input
    if [ -z "$input" ] && [ -n "$default" ]; then
        input="$default"
    fi

    eval "$var_name=\"\$input\""
}

_ask_password() {
    local prompt="$1"
    local var_name="$2"
    local input

    echo -ne "${BOLD}${prompt}${NC}: "
    read -rs input
    echo ""

    eval "$var_name=\"\$input\""
}

_confirm() {
    local question="$1"
    local answer

    echo -ne "${BOLD}${question}${NC} [y/N]: "
    read -r answer

    case "$answer" in
        [yYдД]*) return 0 ;;
        *) return 1 ;;
    esac
}

_check_folder_status() {
    local folder="$1"
    if [ ! -d "$folder" ]; then
        echo "not_exists"
    elif [ -z "$(ls -A "$folder" 2>/dev/null)" ]; then
        echo "empty"
    else
        echo "has_content"
    fi
}

_read_manifest_version() {
    local folder="$1"
    local manifest="$folder/manifest.json"

    if [ ! -f "$manifest" ]; then
        echo "(манифест не найден)"
        return
    fi

    local version build date
    version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")
    build=$(sed -n 's/.*"build"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")
    date=$(sed -n 's/.*"date"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest")

    echo "v${version:-?} (build ${build:-?}, ${date:-?})"
}

_print_env_status() {
    local env_name="$1"
    local folder="$2"
    local domain="$3"
    local status
    status=$(_check_folder_status "$folder")

    case "$status" in
        not_exists)
            echo -e "  ${RED}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${RED}Папка не существует${NC}"
            ;;
        empty)
            echo -e "  ${YELLOW}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${YELLOW}Пустая (готова к установке)${NC}"
            ;;
        has_content)
            local ver
            ver=$(_read_manifest_version "$folder")
            echo -e "  ${GREEN}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${GREEN}Развёрнуто${NC} ${ver}"
            ;;
    esac
}

trap '_error "Ошибка в строке $LINENO. Смотрите вывод выше."' ERR

# ══════════════════════════════════════════
#  Определение режима работы
# ══════════════════════════════════════════

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STANDALONE=false
ROOT_DIR=""
PROJECT_DIR=""

# Проверяем: запущен из репозитория или автономно?
if [ -f "$SCRIPT_DIR/common.sh" ] && [ -d "$SCRIPT_DIR/../project" ]; then
    # Запущен из клонированного репозитория
    ROOT_DIR="$(dirname "$SCRIPT_DIR")"
    PROJECT_DIR="$ROOT_DIR/project"
    _info "Репозиторий обнаружен: ${ROOT_DIR}"
else
    STANDALONE=true
fi

# ══════════════════════════════════════════
#  Баннер
# ══════════════════════════════════════════

clear
echo -e "${BOLD}${CYAN}"
echo "  ╔═══════════════════════════════════╗"
echo "  ║         Simple-CI Install         ║"
echo "  ║   Настройка среды развёртывания   ║"
echo "  ╚═══════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════
#  Автономный режим: клонирование репо
# ══════════════════════════════════════════

if [ "$STANDALONE" = true ]; then
    _header "Автономный режим"
    _info "Репозиторий не обнаружен рядом со скриптом."
    _info "Нужно указать URL репозитория для клонирования."
    echo ""

    # Проверяем наличие git
    if ! command -v git &>/dev/null; then
        _error "git не установлен. Установите git и повторите."
        exit 1
    fi

    _ask "URL git-репозитория" GIT_REPO_URL ""

    if [ -z "$GIT_REPO_URL" ]; then
        _error "URL репозитория не может быть пустым."
        exit 1
    fi

    _ask "Ветка" GIT_BRANCH "main"
    _ask "Куда клонировать репозиторий?" CLONE_DIR "./simple-ci"

    echo ""
    _info "Клонирование ${GIT_REPO_URL} (ветка: ${GIT_BRANCH})..."

    if git clone --branch "$GIT_BRANCH" "$GIT_REPO_URL" "$CLONE_DIR" 2>&1; then
        _success "Репозиторий клонирован в ${CLONE_DIR}"
    else
        _error "Не удалось клонировать репозиторий."
        _warn "Проверьте URL и доступ, затем повторите."
        exit 1
    fi

    ROOT_DIR="$(cd "$CLONE_DIR" && pwd)"
    PROJECT_DIR="$ROOT_DIR/project"

    if [ ! -d "$PROJECT_DIR" ]; then
        _error "В репозитории нет папки project/. Проверьте структуру."
        exit 1
    fi

    _success "Проект найден: ${PROJECT_DIR}"
    echo ""

    # Переключаемся на работу из клонированного репо
    ENV_FILE="$ROOT_DIR/.env"
else
    ENV_FILE="$ROOT_DIR/.env"
fi

# ══════════════════════════════════════════
#  Проверка существующего конфига
# ══════════════════════════════════════════

if [ -f "$ENV_FILE" ]; then
    _header "Обнаружена существующая конфигурация"
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo -e "  TEST:  ${TEST_DOMAIN:-—}  →  ${TEST_FOLDER:-—}"
    echo -e "  BETA:  ${BETA_DOMAIN:-—}  →  ${BETA_FOLDER:-—}"
    echo -e "  PROD:  ${PROD_DOMAIN:-—}  →  ${PROD_FOLDER:-—}"
    echo ""
    if ! _confirm "Перенастроить?"; then
        _info "Отменено. Текущая конфигурация сохранена."
        exit 0
    fi
    echo ""
fi

# ══════════════════════════════════════════
#  Ввод параметров окружений
# ══════════════════════════════════════════

# ── Окружение TEST ──
_header "Окружение TEST"
_ask "Домен для test" TEST_DOMAIN "test.localhost"
_ask "Папка на сервере для test" TEST_FOLDER "/var/www/test"

# ── Окружение BETA ──
_header "Окружение BETA"
_ask "Домен для beta" BETA_DOMAIN "beta.localhost"
_ask "Папка на сервере для beta" BETA_FOLDER "/var/www/beta"

# ── Окружение PROD ──
_header "Окружение PROD"
_ask "Домен для prod" PROD_DOMAIN "prod.localhost"
_ask "Папка на сервере для prod" PROD_FOLDER "/var/www/prod"

# ── БД: beta + prod (общая) ──
_header "База данных для BETA и PROD (общая)"
_ask "Хост БД" SHARED_DB_HOST "localhost"
_ask "Имя БД" SHARED_DB_NAME "app_production"
_ask "Пользователь БД" SHARED_DB_USER "app_user"
_ask_password "Пароль БД" SHARED_DB_PASS

# ── БД: test (отдельная) ──
_header "База данных для TEST (отдельная)"
_ask "Хост БД" TEST_DB_HOST "localhost"
_ask "Имя БД" TEST_DB_NAME "app_test"
_ask "Пользователь БД" TEST_DB_USER "test_user"
_ask_password "Пароль БД" TEST_DB_PASS

# ── Git (если не был указан в автономном режиме) ──
if [ "$STANDALONE" = false ]; then
    _header "Настройки Git"
    _ask "URL репозитория" GIT_REPO_URL ""
    _ask "Ветка для деплоя" GIT_BRANCH "main"
fi

# ══════════════════════════════════════════
#  Сохранение конфигурации
# ══════════════════════════════════════════

_separator
cat > "$ENV_FILE" << ENVEOF
# Simple-CI Configuration
# Создан: $(date '+%Y-%m-%d %H:%M:%S')

# === Окружения ===
TEST_DOMAIN="${TEST_DOMAIN}"
TEST_FOLDER="${TEST_FOLDER}"

BETA_DOMAIN="${BETA_DOMAIN}"
BETA_FOLDER="${BETA_FOLDER}"

PROD_DOMAIN="${PROD_DOMAIN}"
PROD_FOLDER="${PROD_FOLDER}"

# === БД: общая для beta + prod ===
SHARED_DB_HOST="${SHARED_DB_HOST}"
SHARED_DB_NAME="${SHARED_DB_NAME}"
SHARED_DB_USER="${SHARED_DB_USER}"
SHARED_DB_PASS="${SHARED_DB_PASS}"

# === БД: отдельная для test ===
TEST_DB_HOST="${TEST_DB_HOST}"
TEST_DB_NAME="${TEST_DB_NAME}"
TEST_DB_USER="${TEST_DB_USER}"
TEST_DB_PASS="${TEST_DB_PASS}"

# === Git ===
GIT_REPO_URL="${GIT_REPO_URL}"
GIT_BRANCH="${GIT_BRANCH}"
ENVEOF

_success "Конфигурация сохранена в ${ENV_FILE}"
echo ""

# ══════════════════════════════════════════
#  Статус окружений
# ══════════════════════════════════════════

_header "Статус окружений"
_print_env_status "TEST" "$TEST_FOLDER" "$TEST_DOMAIN"
_print_env_status "BETA" "$BETA_FOLDER" "$BETA_DOMAIN"
_print_env_status "PROD" "$PROD_FOLDER" "$PROD_DOMAIN"
echo ""

# ══════════════════════════════════════════
#  Первичное развёртывание
# ══════════════════════════════════════════

_header "Первичное развёртывание"

deploy_env() {
    local env_name="$1"
    local folder="$2"
    local status

    status=$(_check_folder_status "$folder")

    case "$status" in
        not_exists)
            _warn "${env_name}: папка ${folder} не существует. Среда не готова."
            _warn "Создайте папку и перезапустите установщик."
            ;;
        has_content)
            _warn "${env_name}: папка ${folder} уже содержит файлы. Пропускаем."
            ;;
        empty)
            if _confirm "Развернуть ${env_name} в ${folder}?"; then
                _info "Копирование файлов проекта..."
                cp -a "$PROJECT_DIR/." "$folder/"
                _success "${env_name} развёрнут в ${folder}"
            else
                _info "${env_name}: пропущено по запросу."
            fi
            ;;
    esac
}

deploy_env "TEST" "$TEST_FOLDER"
deploy_env "BETA" "$BETA_FOLDER"
deploy_env "PROD" "$PROD_FOLDER"

# ══════════════════════════════════════════
#  Готово
# ══════════════════════════════════════════

echo ""
_separator
echo ""
_success "Установка завершена!"
echo ""

if [ "$STANDALONE" = true ]; then
    _info "Репозиторий клонирован в: ${ROOT_DIR}"
    _info "Для дальнейшей работы используйте скрипты из ${ROOT_DIR}/utils/"
    echo ""
fi

_info "Доступные команды:"
echo -e "  ${CYAN}utils/status.sh${NC}     — статус окружений"
echo -e "  ${CYAN}utils/git2test.sh${NC}   — обновить тест из git"
echo -e "  ${CYAN}utils/test2beta.sh${NC}  — продвинуть тест → бета"
echo -e "  ${CYAN}utils/beta2prod.sh${NC}  — продвинуть бета → прод"
echo ""
