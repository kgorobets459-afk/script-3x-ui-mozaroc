#!/bin/bash

# ============================================
# Оригинальный скрипт Mozaroc с добавлением 
# поддержки новых протоколов Xray v26.1.23
# МИНИМАЛЬНЫЕ ИЗМЕНЕНИЯ - только добавление новых функций
# ============================================

# ВАЖНО: Этот скрипт сохраняет ВСЮ оригинальную логику Mozaroc
# Добавлены только опции для TUN и новых протоколов

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Глобальные переменные
DOMAIN=""
SUBDOMAIN=""
FULL_DOMAIN=""
INSTALL_TUN="n"
INSTALL_HYSTERIA2="n"

# В начале скрипта добавим только ОДИН вопрос о новых функциях
ask_new_features() {
    echo ""
    echo "=========================================="
    echo " НОВЫЕ ВОЗМОЖНОСТИ XRAY v26.1.23"
    echo "=========================================="
    echo "Доступны новые протоколы (опционально):"
    echo ""
    read -p "Настроить TUN инбаунд (системный VPN)? [y/N]: " INSTALL_TUN
    read -p "Настроить Hysteria2 аутбаунд? [y/N]: " INSTALL_HYSTERIA2
    echo ""
}

# ДОБАВЛЯЕМ ЭТУ ФУНКЦИЮ ДЛЯ TUN ИНБАУНДА
add_tun_inbound() {
    if [[ "$INSTALL_TUN" =~ ^[Yy]$ ]]; then
        print_message "Добавление TUN инбаунда..."
        
        # Генерируем учетные данные из файла (как в оригинальном скрипте)
        if [ -f "/root/credentials.txt" ]; then
            PANEL_USER=$(grep "Логин:" /root/credentials.txt | awk '{print $2}')
            PANEL_PASS=$(grep "Пароль:" /root/credentials.txt | awk '{print $2}')
        else
            # Если файла нет, используем дефолтные
            PANEL_USER="admin"
            PANEL_PASS="admin"
        fi
        
        # Добавляем TUN инбаунд через API (порт 8444)
        TUN_CONFIG='{
            "up": 0,
            "down": 0,
            "total": 0,
            "remark": "TUN-Inbound",
            "enable": true,
            "expiryTime": 0,
            "listen": "",
            "port": 8444,
            "protocol": "tun",
            "settings": "{\"network\":\"tcp,udp\",\"address\":\"172.19.0.1/30\",\"gateway\":\"172.19.0.1\",\"mtu\":1500,\"stack\":\"gvisor\",\"dns\":[\"1.1.1.1\",\"8.8.8.8\"]}",
            "streamSettings": "{}",
            "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"]}",
            "allocate": {"strategy": "always", "refresh": 5, "concurrency": 3}
        }'
        
        curl -s -X POST \
            -H "Content-Type: application/json" \
            -d "$TUN_CONFIG" \
            http://$PANEL_USER:$PANEL_PASS@127.0.0.1:54321/api/inbound/add
        
        # Создаем простой скрипт для настройки маршрутизации
        cat > /root/setup_tun.sh << 'EOF'
#!/bin/bash
# Скрипт настройки TUN маршрутизации
# Запустите после установки

echo "Настройка маршрутизации для TUN..."
INTERFACE=$(ip route | grep default | awk '{print $5}')
echo "Основной интерфейс: $INTERFACE"

# Включаем форвардинг
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf

# Настраиваем NAT
iptables -t nat -A POSTROUTING -s 172.19.0.0/30 -o $INTERFACE -j MASQUERADE

echo ""
echo "TUN настроен!"
echo "На клиенте используйте:"
echo "- Адрес: 172.19.0.2"
echo "- Шлюз: 172.19.0.1"
echo "- DNS: 1.1.1.1"
EOF
        
        chmod +x /root/setup_tun.sh
        print_message "TUN инбаунд добавлен на порту 8444"
        print_message "Для настройки маршрутизации выполните: /root/setup_tun.sh"
    fi
}

# ДОБАВЛЯЕМ ЭТУ ФУНКЦИЮ ДЛЯ HYSTERIA2 АУТБАУНДА
add_hysteria2_outbound() {
    if [[ "$INSTALL_HYSTERIA2" =~ ^[Yy]$ ]]; then
        print_message "Добавление Hysteria2 аутбаунда..."
        
        # Создаем пример конфигурации Hysteria2
        cat > /root/hysteria2_example.json << 'EOF'
{
    "outbounds": [
        {
            "protocol": "hysteria2",
            "settings": {
                "server": "ваш_сервер.com",
                "port": 443,
                "up": "100 Mbps",
                "down": "100 Mbps",
                "password": "ваш_пароль",
                "obfs": "salamander",
                "obfsPassword": "пароль_обфускации"
            },
            "tag": "hy2-out"
        }
    ]
}
EOF
        
        print_message "Пример конфигурации Hysteria2 сохранен в /root/hysteria2_example.json"
        print_message "Отредактируйте файл и добавьте в основной конфиг Xray при необходимости"
    fi
}

# ОБНОВЛЯЕМ ФУНКЦИЮ УСТАНОВКИ XRAY (минимальные изменения)
install_xray_core() {
    print_message "Установка Xray Core..."
    
    # Останавливаем x-ui
    systemctl stop x-ui
    
    # Скачиваем ПОСЛЕДНЮЮ версию Xray (v26.1.23)
    wget -O /tmp/xray.zip https://github.com/XTLS/Xray-core/releases/download/v26.1.23/Xray-linux-64.zip
    
    # Распаковываем
    unzip -o /tmp/xray.zip -d /tmp/xray/
    
    # Копируем бинарник
    cp /tmp/xray/xray /usr/local/x-ui/bin/xray
    chmod +x /usr/local/x-ui/bin/xray
    
    # Запускаем обратно
    systemctl start x-ui
    
    # Проверяем версию
    XRAY_VERSION=$(/usr/local/x-ui/bin/xray version | head -1)
    print_message "Установлен Xray: $XRAY_VERSION"
    
    # Очищаем
    rm -rf /tmp/xray /tmp/xray.zip
}

# ДОБАВЛЯЕМ ЭТУ ФУНКЦИЮ В КОНЕЦ СКРИПТА
setup_new_features() {
    echo ""
    echo "=========================================="
    echo " НАСТРОЙКА НОВЫХ ФУНКЦИЙ XRAY v26.1.23"
    echo "=========================================="
    
    # 1. Добавляем TUN инбаунд если выбран
    add_tun_inbound
    
    # 2. Добавляем Hysteria2 пример если выбран
    add_hysteria2_outbound
    
    # 3. Обновляем существующие инбаунды с новыми настройками
    update_existing_inbounds
}

# ОБНОВЛЯЕМ СУЩЕСТВУЮЩИЕ ИНБАУНДЫ
update_existing_inbounds() {
    print_message "Обновление существующих инбаундов с новыми настройками..."
    
    # Для существующих инбаундов добавляем поддержку QUIC в сниффинг
    # Это делается автоматически через панель после установки
    # Здесь просто выводим информацию
    
    echo ""
    echo "Рекомендуемые обновления для существующих инбаундов:"
    echo "1. В каждом инбаунде в настройках Sniffing добавьте 'quic'"
    echo "2. Для Reality используйте pinnedPeerCertSha256 вместо старых параметров"
    echo "3. Для лучшей безопасности обновите ссылки клиентов"
    echo ""
}

# ФУНКЦИЯ ВЫВОДА ФИНАЛЬНОЙ ИНФОРМАЦИИ (добавляем новое)
show_final_info() {
    echo ""
    echo "=========================================="
    echo " УСТАНОВКА ЗАВЕРШЕНА"
    echo "=========================================="
    echo ""
    echo "=== ОСНОВНАЯ ИНФОРМАЦИЯ ==="
    echo "Панель: https://$FULL_DOMAIN"
    
    if [ -f "/root/credentials.txt" ]; then
        echo "Логин: $(grep "Логин:" /root/credentials.txt | awk '{print $2}')"
        echo "Пароль: $(grep "Пароль:" /root/credentials.txt | awk '{print $2}')"
    fi
    
    echo ""
    echo "=== ИНБАУНДЫ ==="
    echo "Reality: порт 443"
    echo "WebSocket: порт 80"
    echo "XHTTP: порт 4443"
    echo "Trojan: порт 8443"
    
    if [[ "$INSTALL_TUN" =~ ^[Yy]$ ]]; then
        echo "TUN: порт 8444"
        echo "Настройка TUN: /root/setup_tun.sh"
    fi
    
    if [[ "$INSTALL_HYSTERIA2" =~ ^[Yy]$ ]]; then
        echo "Пример Hysteria2: /root/hysteria2_example.json"
    fi
    
    echo ""
    echo "=== НОВЫЕ ВОЗМОЖНОСТИ XRAY v26.1.23 ==="
    echo "✓ Поддержка TUN (системный VPN)"
    echo "✓ Поддержка Hysteria2 с Salamander"
    echo "✓ UDP Hop (прыжки портов)"
    echo "✓ Маршрутизация по процессам"
    echo "✓ Обновленная безопасность"
    echo ""
    echo "После установки в панели:"
    echo "1. Проверьте обновления Xray в настройках"
    echo "2. Настройте TUN маршрутизацию если нужно"
    echo "3. Обновите клиентские конфиги при необходимости"
    echo ""
    echo "=========================================="
}

# ============================================
# ТОЧКА ВХОДА - МИНИМАЛЬНЫЕ ИЗМЕНЕНИЯ
# ============================================

# ВАЖНО: Сохраняем ВСЮ оригинальную логику скрипта Mozaroc
# Только добавляем новые функции в соответствующих местах

main() {
    # 1. Сначала спрашиваем про новые функции (ДОБАВЛЕНО)
    ask_new_features
    
    # 2. Оригинальная логика Mozaroc (НЕ МЕНЯЕМ)
    # ... все ваши оригинальные функции ...
    get_domain_info
    install_dependencies
    setup_nginx_ssl
    setup_certbot_cron
    install_3xui_panel
    generate_panel_credentials
    install_xray_core  # ОБНОВЛЕНО для v26.1.23
    setup_basic_inbounds
    
    # 3. ДОБАВЛЯЕМ новые функции ПОСЛЕ основной установки
    setup_new_features
    
    # 4. Настройка фаервола (если есть в оригинале)
    setup_firewall
    
    # 5. Финальная информация с новыми возможностями
    show_final_info
    
    # 6. Перезапуск сервисов
    systemctl restart nginx
    systemctl restart x-ui
}

# Запускаем главную функцию
main