#!/usr/bin/env bash

# Get the current URL domain
DOMAIN=$(python3 -c "from urllib.parse import urlparse; print(urlparse('$QUTE_URL').netloc)")

# NOOP if we are already signed in
op signin

# Search for items matching the domain
echo "message-info 'Searching 1Password for $DOMAIN...'" >> "$QUTE_FIFO"

# Get the 1Password entries that match the URL
MATCHED_ITEMS=$(op item list --long --format=json | jq --raw-output "
  [
    .[] |
    select(.category == \"LOGIN\") |
    select(.urls != null) |
    .urls[] as \$url |
    {id: .id, title: .title, url: \$url.href} |
    select(.url | contains(\"$DOMAIN\"))
  ]
")

# Check that only one item matches
# TODO: handle multiple items being matched
MATCHED_COUNT=$(jq '. | length' <<< "$MATCHED_ITEMS")
if [ "$MATCHED_COUNT" -gt "1" ]; then
    echo "message-error '$DOMAIN matched more then one item'" >> "$QUTE_FIFO"
    echo "$MATCHED_ITEMS"
    exit 1
fi

if [ "$MATCHED_COUNT" -eq "0" ]; then
    echo "message-error '$DOMAIN matched did not match any items'" >> "$QUTE_FIFO"
    exit 1
fi

# Retrieve the item details
ITEM_ID=$(jq --raw-output 'first | .id' <<< "$MATCHED_ITEMS")
ITEM_JSON=$(op item get "$ITEM_ID" --format=json)

# Extract username and password
USERNAME=$(echo "$ITEM_JSON" | jq --raw-output '.fields[] | select(.id == "username") | .value // empty')
PASSWORD=$(echo "$ITEM_JSON" | jq --raw-output '.fields[] | select(.id == "password") | .value // empty')

if [[ -z "$PASSWORD" ]]; then
    echo "message-error 'No password found in selected item'" >> "$QUTE_FIFO"
    exit 1
fi

# Fill the credentials
if [[ -n "$USERNAME" ]]; then
    echo "fake-key $USERNAME" >> "$QUTE_FIFO"
    echo "fake-key <Tab>" >> "$QUTE_FIFO"
fi

#shellcheck disable=SC2129
echo "fake-key $PASSWORD" >> "$QUTE_FIFO"
echo "fake-key <Enter>" >> "$QUTE_FIFO"

echo "message-info 'Filled credentials from 1Password'" >> "$QUTE_FIFO"
