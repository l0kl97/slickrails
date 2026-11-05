KIND=fault
DESC="the installer must not silently switch core.hooksPath away from an existing hook manager (Husky)"
# Caught = after the install the repo still points at the user's own hook directory. The install also has
# to keep going (placing the files); only the silent switch is the fault.
setup() {
  mkdir -p .husky
  printf '#!/bin/sh\necho husky pre-commit\n' > .husky/pre-commit; chmod +x .husky/pre-commit
  git config core.hooksPath .husky
}
act() {
  sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  [ "$(git config core.hooksPath)" = ".husky" ] && return 1
  return 0
}
