#!/usr/bin/env bash
# Instala Node (via nvm), clona el repositorio y deja FibonacciApp corriendo con forever.
# Uso (dentro de la VM):
#   curl -fsSL https://raw.githubusercontent.com/juanesgl/ARSW_LOAD-BALANCING_AZURE/main/scripts/setup-vm.sh | bash
#   o bien:  bash setup-vm.sh [url_del_repo]
set -eo pipefail  # sin -u: nvm.sh usa variables no definidas

REPO_URL="${1:-https://github.com/juanesgl/ARSW_LOAD-BALANCING_AZURE.git}"
REPO_DIR="$HOME/$(basename "$REPO_URL" .git)"
NVM_VERSION="v0.40.1"

# El timeout evita fallar si unattended-upgrades tiene apt bloqueado en el primer arranque
sudo apt-get -o DPkg::Lock::Timeout=600 update -y
sudo apt-get -o DPkg::Lock::Timeout=600 install -y git curl

# Node.js con nvm (seccion "Installing Node.js and npm using NVM" del laboratorio)
if [ ! -d "$HOME/.nvm" ]; then
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'

# Codigo de la aplicacion
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull
else
  git clone "$REPO_URL" "$REPO_DIR"
fi
cd "$REPO_DIR/FibonacciApp"
npm install --omit=dev

# forever mantiene la app viva al cerrar la sesion ssh
npm install -g forever
forever stopall || true
forever start FibonacciApp.js

# Al cambiar el tamano de la VM (escalamiento vertical) Azure la reinicia y forever no
# sobrevive al reinicio; esta entrada de cron vuelve a levantar la app al arrancar.
NODE_BIN="$(dirname "$(nvm which default)")"
CRON_LINE="@reboot PATH=$NODE_BIN:\$PATH forever start $REPO_DIR/FibonacciApp/FibonacciApp.js"
( crontab -l 2>/dev/null | grep -v 'forever start' || true; echo "$CRON_LINE" ) | crontab -

forever list
echo "Listo. Pruebe con: curl http://localhost:3000/fibonacci/6   (debe responder 'The answer is 8')"
