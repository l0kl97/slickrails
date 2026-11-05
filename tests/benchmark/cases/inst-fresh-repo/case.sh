KIND=control
DESC="a repo without any hook manager gets core.hooksPath = .githooks from the installer"
# Counterpart of inst-husky-clobber: an installer that never touches core.hooksPath fails here.
setup() { git config --unset core.hooksPath; }
act() {
  sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  [ "$(git config core.hooksPath)" = ".githooks" ] && return 0
  return 1
}
