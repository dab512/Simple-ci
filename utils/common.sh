#!/usr/bin/env bash
# common.sh — общая библиотека для скриптов развёртывания
# Подключается через: source "$(dirname "$0")/common.sh"

# --- Цвета ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Пути ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$ROOT_DIR/.env"
PROJECT_DIR="$ROOT_DIR/project"

# --- Вывод ---
info()    { echo -e "${BLUE}ℹ${NC}  $*"; }
success() { echo -e "${GREEN}✔${NC}  $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
error()   { echo -e "${RED}✖${NC}  $*"; }

header() {
    echo ""
    echo -e "${BOLD}${CYAN}━━━ $* ━━━${NC}"
    echo ""
}

separator() {
    echo -e "${CYAN}───────────────────────────────────────────${NC}"
}

# --- Промпты ---

# ask PROMPT VAR_NAME [DEFAULT]
# Запрашивает ввод, сохраняет в переменную. Если пусто — использует дефолт.
ask() {
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

# ask_password PROMPT VAR_NAME
# Скрытый ввод пароля
ask_password() {
    local prompt="$1"
    local var_name="$2"
    local input

    echo -ne "${BOLD}${prompt}${NC}: "
    read -rs input
    echo ""

    eval "$var_name=\"\$input\""
}

# confirm QUESTION
# Возвращает 0 (да) или 1 (нет)
confirm() {
    local question="$1"
    local answer

    echo -ne "${BOLD}${question}${NC} [y/N]: "
    read -r answer

    case "$answer" in
        [yYдД]*) return 0 ;;
        *) return 1 ;;
    esac
}

# --- Конфигурация ---

load_config() {
    if [ ! -f "$ENV_FILE" ]; then
        error "Файл .env не найден. Сначала запустите install.sh"
        exit 1
    fi
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
}

save_config() {
    cat > "$ENV_FILE" << ENVEOF
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
    success "Конфигурация сохранена в .env"
}

# --- Проверка папок ---

# check_folder_status PATH
# Выводит: not_exists / empty / has_content
check_folder_status() {
    local folder="$1"
    if [ ! -d "$folder" ]; then
        echo "not_exists"
    elif [ -z "$(ls -A "$folder" 2>/dev/null)" ]; then
        echo "empty"
    else
        echo "has_content"
    fi
}

# print_env_status ENV_NAME FOLDER DOMAIN
# Цветной вывод статуса окружения
print_env_status() {
    local env_name="$1"
    local folder="$2"
    local domain="$3"
    local status
    status=$(check_folder_status "$folder")

    case "$status" in
        not_exists)
            echo -e "  ${RED}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${RED}Папка не существует${NC}"
            ;;
        empty)
            echo -e "  ${YELLOW}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${YELLOW}Пустая (готова к установке)${NC}"
            ;;
        has_content)
            local ver
            ver=$(read_manifest_version "$folder")
            echo -e "  ${GREEN}●${NC} ${BOLD}${env_name}${NC}  ${domain}  ${folder}  → ${GREEN}Развёрнуто${NC} ${ver}"
            ;;
    esac
}

# --- Манифест ---

# read_manifest_version FOLDER
# Читает версию из manifest.json в указанной папке
read_manifest_version() {
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

# --- Бэкапы ---

# make_backup FOLDER ENV_NAME
# Создаёт timestamped бэкап, возвращает путь
make_backup() {
    local folder="$1"
    local env_name="$2"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="${folder}/../backups/${env_name}_${timestamp}"

    mkdir -p "$backup_dir"
    cp -a "$folder/." "$backup_dir/"
    success "Бэкап создан: $backup_dir"
    echo "$backup_dir"
}

# --- Синхронизация ---

# sync_files SOURCE DEST
# rsync с исключениями конфигов и пользовательских данных
sync_files() {
    local source="$1"
    local dest="$2"

    rsync -a --delete \
        --exclude='config.*' \
        --exclude='.env' \
        --exclude='uploads/' \
        --exclude='storage/' \
        "$source/" "$dest/"
}
