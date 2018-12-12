# BAT

A tiny build utility.

## Example

You use it by creating a `bat.config` file in the project root. It can be something like this:

``` bash
#!/usr/bin/env bash

name="my_project"
postcss_opts="src/*.sss --parser sugarss -u postcss-easy-import -u precss -u postcss-nested-props -u autoprefixer -u lost --ext css --dir /static"
postcss_prod="-u cssnano"

# Runs before everything else.
before () {
  echo Starting from $bat_dir...
}

# Runs after everything else
after () {
  echo Done.
}

# Install dependencies
install () {
  npm install
}

# Clean up build artifacts
clean () {
  rm -rf dist public
}

watch_postcss () {
  yarn exec postcss -- --verbose --watch $postcss_opts
}

watch_webpack () {
  yarn exec webpack -- --watch
}

watch_hugo () {
  hugo server
}

# Start a parallel session running all the appropriate watchers
watch () {
  parallel "watch_postcss" \
           "watch_webpack" \
           "watch_hugo"
}

build () {
  yarn exec postcss -- $postcss_opts $postcss_prod
  yarn exec webpack -- -p
  hugo
}
```
