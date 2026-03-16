#!/bin/bash
#===============================================================================
# Базовый скрипт настройки Ubuntu-сервера
# Запуск: sh -c "$(curl -fsSL https://raw.githubusercontent.com/SomniSom/setup/main/setup.sh)"
# Требования: запуск от root, Ubuntu 20.04/22.04/24.04
#===============================================================================

set -e  # Выход при ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

#-------------------------------------------------------------------------------
# 1. Обновление системы
#-------------------------------------------------------------------------------
log_info "Обновление пакетов..."
apt update -qq
apt upgrade -y -qq
apt autoremove -y -qq

#-------------------------------------------------------------------------------
# 2. Установка базовых пакетов
#-------------------------------------------------------------------------------
log_info "Установка базовых пакетов..."
apt install -y -qq wget zsh git nano mc nginx docker.io

# Установка docker-compose-v2 (плагин для docker)
log_info "Установка docker-compose-v2..."
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

#-------------------------------------------------------------------------------
# 3. Настройка ZSH и Oh-My-Zsh
#-------------------------------------------------------------------------------
log_info "Настройка ZSH..."

# Установка Oh-My-Zsh в неинтерактивном режиме
RUNZSH=no CHSH=no sh -c "$(wget -O- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Копирование шаблона zshrc для root (если не создан)
if [ ! -f /root/.zshrc ]; then
    cp /root/.oh-my-zsh/templates/zshrc.zsh-template /root/.zshrc
fi

# Добавление алиаса dc="docker compose" для root
if ! grep -q 'alias dc="docker compose"' /root/.zshrc; then
    echo '' >> /root/.zshrc
    echo '# Custom aliases' >> /root/.zshrc
    echo 'alias dc="docker compose"' >> /root/.zshrc
fi

# Смена shell для root на zsh (если ещё не установлен)
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s $(which zsh) root
fi

#-------------------------------------------------------------------------------
# 4. Создание пользователя som
#-------------------------------------------------------------------------------
USERNAME="som"
log_info "Создание пользователя $USERNAME..."

# Генерация случайного пароля (16 символов)
PASSWORD=$(openssl rand -base64 16 | tr -d '=+/' | cut -c1-16)

# Создание пользователя (если не существует)
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/zsh "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    log_info "Пользователь $USERNAME создан."
else
    log_warn "Пользователь $USERNAME уже существует, пароль не изменён."
fi

# Настройка ZSH для нового пользователя
log_info "Настройка окружения для $USERNAME..."

# Копирование .zshrc из шаблона, если нет
if [ ! -f "/home/$USERNAME/.zshrc" ]; then
    cp /root/.oh-my-zsh/templates/zshrc.zsh-template "/home/$USERNAME/.zshrc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.zshrc"
fi

# Добавление алиаса dc для пользователя
if ! grep -q 'alias dc="docker compose"' "/home/$USERNAME/.zshrc"; then
    echo '' >> "/home/$USERNAME/.zshrc"
    echo '# Custom aliases' >> "/home/$USERNAME/.zshrc"
    echo 'alias dc="docker compose"' >> "/home/$USERNAME/.zshrc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.zshrc"
fi

# Смена shell на zsh для пользователя
chsh -s $(which zsh) "$USERNAME"

# Права на домашнюю директорию
chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

#-------------------------------------------------------------------------------
# 5. Настройка SSH
#-------------------------------------------------------------------------------
SSH_PORT=2222
log_info "Настройка SSH (порт $SSH_PORT)..."

# Резервная копия конфигурации
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d%H%M)

# Обновление конфигурации SSH
sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^#*PermitRootLogin .*/PermitRootLogin prohibit-password/" /etc/ssh/sshd_config
sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config

# Проверка синтаксиса конфигурации
if sshd -t; then
    log_info "Конфигурация SSH валидна, перезапуск службы..."
    systemctl restart ssh
else
    log_error "Ошибка в конфигурации SSH! Восстановление из бэкапа..."
    cp /etc/ssh/sshd_config.backup.* /etc/ssh/sshd_config
    systemctl restart ssh
    exit 1
fi

#-------------------------------------------------------------------------------
# 6. Настройка фаервола (UFW)
#-------------------------------------------------------------------------------
log_info "Настройка UFW..."

ufw --force enable
ufw allow "$SSH_PORT"/tcp comment 'SSH custom port'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw --force reload

#-------------------------------------------------------------------------------
# 7. Запуск и автозагрузка сервисов
#-------------------------------------------------------------------------------
log_info "Запуск сервисов..."
systemctl enable --now docker
systemctl enable --now nginx

#-------------------------------------------------------------------------------
# 8. Финальный вывод
#-------------------------------------------------------------------------------
echo ""
echo "============================================================"
echo -e "${GREEN}✅ Настройка сервера завершена!${NC}"
echo "============================================================"
echo ""
echo -e "${YELLOW}🔐 Данные для входа:${NC}"
echo "   Пользователь: $USERNAME"
echo "   Пароль:       $PASSWORD"
echo "   SSH порт:     $SSH_PORT"
echo ""
echo -e "${YELLOW}📋 Команда для подключения:${NC}"
echo "   ssh -p $SSH_PORT $USERNAME@<IP_АДРЕС_СЕРВЕРА>"
echo ""
echo -e "${RED}⚠️  ВАЖНО:${NC}"
echo "   1. НЕ ЗАКРЫВАЙТЕ текущую сессию root!"
echo "   2. Откройте НОВОЕ окно терминала и проверьте вход под $USERNAME"
echo "   3. Только после успешного входа можно закрывать root-сессию"
echo "   4. Рекомендуется сразу настроить SSH-ключи и отключить PasswordAuthentication"
echo ""
echo "============================================================"