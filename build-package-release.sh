#!/bin/bash
set -e

echo "Building release binary for target: $RUSTTARGET"
rustup target add "$RUSTTARGET"
cargo build --release --target "$RUSTTARGET"


: "${BINARY_NAMES:?Environment variable BINARY_NAMES must be set}"
BINARY_PATHS=()
for BINARY_NAME in $BINARY_NAMES; do
  BINARY_PATH="target/$RUSTTARGET/release/$BINARY_NAME"
  if [ ! -x "$BINARY_PATH" ]; then
    echo "Error: Binary not found at $BINARY_PATH"
    exit 1
  fi
  BINARY_PATHS+=("$BINARY_PATH")
done

PACKAGE_DIR=package
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR"

for BINARY_PATH in "${BINARY_PATHS[@]}"; do
  echo "Copying binary ($BINARY_PATH) into package directory..."
  cp "$BINARY_PATH" "$PACKAGE_DIR/"
done

# Include any extra files, if specified
if [ -n "$EXTRA_FILES" ]; then
  echo "Adding extra files: $EXTRA_FILES"
  for file in $EXTRA_FILES; do
    if [ -f "$file" ]; then
      cp "$file" "$PACKAGE_DIR/"
    else
      echo "Warning: Extra file '$file' not found."
    fi
  done
fi

: "${ARTIFACT_PREFIX}?Environment variable ARTIFACT_PREFIX must be set}"
RELEASE_TAG="${GITHUB_REF#refs/tags/}"


ARTIFACTS=()
# Create archives based on ARCHIVE_TYPES
for archive_type in $ARCHIVE_TYPES; do
  PREFIX="$ARTIFACT_PREFIX"_"$RELEASE_TAG"_"$RUSTTARGET"
  case "$archive_type" in
    zip)
      ARCHIVE_FILE="$PREFIX".zip
      echo "Creating ZIP archive: $ARCHIVE_FILE"
      zip -j "$ARCHIVE_FILE" "$PACKAGE_DIR"/*
      ;;
    tar.gz)
      ARCHIVE_FILE="$PREFIX.tar.gz"
      echo "Creating tar.gz archive: $ARCHIVE_FILE"
      tar -czf "$ARCHIVE_FILE" -C "$PACKAGE_DIR" .
      ;;
    tar.xz)
      ARCHIVE_FILE="$PREFIX.tar.xz"
      echo "Creating tar.xz archive: $ARCHIVE_FILE"
      tar -cJf "$ARCHIVE_FILE" -C "$PACKAGE_DIR" .
      ;;
    *)
      echo "Error: Unknown archive type '$archive_type'"
      exit 1
      ;;
  esac
  shasum -a 256 "$ARCHIVE_FILE" > "$ARCHIVE_FILE".sha256
  ARTIFACTS+=("$ARCHIVE_FILE")
  ARTIFACTS+=("$ARCHIVE_FILE".sha256)
done

# Upload the archives as assets to the GitHub release.
# Assumes that this workflow was triggered by a release event, so GITHUB_REF is set to the tag name.
echo "Uploading artifacts to release: $RELEASE_TAG"

# Iterate over all archives created (assuming their names start with the binary name)
for artifact in "${ARTIFACTS[@]}"; do
  if [ -f "$artifact" ]; then
    echo "Uploading $artifact..."
    gh release upload "$RELEASE_TAG" "$artifact" --repo "$GITHUB_REPOSITORY" --clobber
  fi
done

echo "Release process complete."
