#!/bin/sh
set -eu
# Xcode injects this absolute SwiftPM rpath ahead of embedded frameworks.
# In a simulator, opening a build tree under ~/Documents can block before main.
# All runtime frameworks are embedded; installed apps must not load build files.
# https://github.com/skiptools/skip/issues/728
package_rpath="${BUILT_PRODUCTS_DIR}/PackageFrameworks"
for binary in "${TARGET_BUILD_DIR}/${EXECUTABLE_PATH}" "${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/${PRODUCT_NAME}.debug.dylib"; do
  [ -f "$binary" ] || continue
  if /usr/bin/otool -l "$binary" | /usr/bin/grep -Fq "path ${package_rpath} (offset"; then
    /usr/bin/install_name_tool -delete_rpath "$package_rpath" "$binary"
    # The debug dylib may already have been signed; keep its signature valid.
    if [ "${CODE_SIGNING_ALLOWED:-NO}" = YES ]; then
      /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" "$binary"
    fi
  fi
done
