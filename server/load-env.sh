#!/bin/sh

# Check if the environment file exists
if [ ! -f "$ENV" ]; then
    printf "error: file not found '%s'\n" "$ENV" >&2
    return 1 2>/dev/null || exit 1
fi

# Load environment variables from the file
while IFS= read -r line || [ -n "$line" ]; do

    # Skip empty lines
    [ -z "$line" ] && continue

    # Skip comments
    case "$line" in
        \#*) continue ;;
    esac

    # Split KEY=VALUE
    key="${line%%=*}"
    value="${line#*=}"

    export "$key=$value"

done < "$ENV"

return 0 2>/dev/null || exit 0
