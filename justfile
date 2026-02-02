release bump="patch":
    npm version {{bump}}
    git push && git push --tags

test-install:
    node bin/install.mjs

test-uninstall:
    node bin/install.mjs uninstall
