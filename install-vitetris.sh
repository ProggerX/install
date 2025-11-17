if [ "$PACKAGE_MANAGER" == "apt" ]; then
	ncurses="libncurses-dev"
elif [ "$PACKAGE_MANAGER" == "dnf" ]; then
	ncurses="ncurses-devel"
elif [ "$PACKAGE_MANAGER" == "pacman" ]; then
	ncurses="ncurses"
fi
$INSTALL_COMMAND gcc make $ncurses git
git clone https://github.com/vicgeralds/vitetris
cd vitetris
make
make install
