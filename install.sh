#! /usr/bin/env bash

CONFIG_FILE="install-config.txt"

# Проверка на наличие одного из популярных менеджеров пакетов
detect_pm() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

# Вывод информации о способе установки пакета
show_package() {
	package=$1
	echo "Install $package using"
	if [ -f "install-$package.sh" ]; then
		echo -e "\t./install-$package.sh"
	else
		echo -e "\t$INSTALL_COMMAND $package"
	fi
}

# Проверка, установлен ли уже пакет
is_installed() {
	package=$1
	if [ -f /var/lib/installer/$package ]; then
		echo "yes"
	elif [ "$PACKAGE_MANAGER" == "apt" ]; then
		r=$(apt list $package --installed 2> /dev/zero | grep -o "$package")
		if [ "$r" == "" ]; then
			echo "no"
		else
			echo "yes"
		fi
	elif [ "$PACKAGE_MANAGER" == "dnf" ]; then
		r=$(dnf list installed $package 2> /dev/zero | grep -o "Installed")
		if [ "$r" == "" ]; then
			echo "no"
		else
			echo "yes"
		fi
	elif [ $PACKAGE_MANAGER == "pacman" ]; then
		if pacman -Q $package &> /dev/null; then
			echo "yes"
		else
			echo "no"
		fi
	else
		echo "no" # Нет поддержки для пакетного менеджера
	fi
}

# Установка пакета
install_package() {
	package=$1
	echo "Installing $package..."
	if [ -f "install-$package.sh" ]; then
		. ./install-$package.sh
	else
		$INSTALL_COMMAND $package
	fi &>> "$TEMP_DIR/install-$package.log"
	status=$?
	echo "status $status" >> "$TEMP_DIR/install-$package.log"
	if [ "$status" == "0" ]; then
		touch /var/lib/installer/$package
	fi
}

make_log() {
	echo "$(date)" >> install.log
	for file in $TEMP_DIR/*; do
		pkg=$(echo $file | sed 's/.*\/install-//' | sed 's/\.log$//')
		if [ "$(tail -n 1 $file)" == "status 0" ]; then
			echo "✅ $pkg was successfully installed" >> install.log
		else
			echo -e "❌ $pkg was not installed \n\t See $file" >> install.log
		fi
	done
}

# Провереям, запущен ли скрипт от root
if [[ $EUID > 0 ]]; then 
	echo "error: need to be run from root (use sudo)" >&2
	exit 1
fi
TEMP_DIR=$(mktemp -d)

# Смотрим на наличие файла конфигурации
if [[ -f "$CONFIG_FILE" ]]; then
    mapfile -t config_lines < "$CONFIG_FILE"
else
    echo "error: config file not found" >&2
    exit 1
fi

# Смотрим на наличие популярного пакетного менеджера
export PACKAGE_MANAGER=$(detect_pm)

if [ "$PACKAGE_MANAGER" == "unknown" ]; then
	echo "error: no apt/dnf/pacman detected" >&2
	exit 1
elif [ "$PACKAGE_MANAGER" == "apt" ]; then
	export UPDATE_COMMAND="apt-get update -y"
	export INSTALL_COMMAND="apt-get install -y"
    export DEBIAN_FRONTEND=noninteractive
elif [ "$PACKAGE_MANAGER" == "dnf" ]; then
	export UPDATE_COMMAND="true"
	export INSTALL_COMMAND="dnf install -y"
elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
	export UPDATE_COMMAND="pacman -Sy"
	export INSTALL_COMMAND="pacman -S --noconfirm"
fi

echo -e "info: detected install command '$INSTALL_COMMAND'\n" >&2

to_install=()

# Показываем пользователю план действий
echo "Hello! This script is going to install some packages (This might hang for a little): "
for line in "${config_lines[@]}"; do
	installed=$(is_installed $line)
	if [ "$installed" == "no" ]; then
		show_package $line &
		to_install+=("$line")
	else
		echo "Package $line is already installed, skipping"
	fi
done

wait

# Выходим из скрипта, если нечего устанавливать
if [ ${#to_install[@]} -eq 0 ]; then
	echo "Nothing to install, exiting"
	exit 0
fi

# Спрашиваем пользователя
echo "Are you aggree? (y/N) " 
read yn
if [ "${yn,,}" == "y" ]; then
	echo "Updating repositories..."
	$UPDATE_COMMAND
	mkdir -p /var/lib/installer
	for pkg in "${to_install[@]}"; do
		# TODO: Параллельная загрузка/установка
		install_package $pkg
	done

	wait

	make_log
	echo "Finished! Logs can be found in '$TEMP_DIR/' and final log is ./install.log:"
	cat install.log
else
	echo "error: interrupted by user" >&2
fi
