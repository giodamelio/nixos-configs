import os
import asyncio
import subprocess
import platform
import json

import pwinput
from onepassword.client import Client


def write_systemd_secret(name, contents):
    try:
        proc = subprocess.Popen(
            [
                "systemd-creds",
                "encrypt",
                "--name=" + name,
                "-",
                f"/var/lib/credstore/{name}"
            ],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        stdout, stderr = proc.communicate(input=contents)

        if proc.returncode == 0:
            print("Credential Synced")
        else:
            print(f"Error encrypting credential: {stderr.strip()}")

    except Exception as e:
        print(f"An error occurred: {e}")


def is_password_field(item):
    return item.title == "password"


async def main():
    if os.geteuid() != 0:
        exit("Script must have root permissions")

    prompt = "Enter 1Password Service Account Token: "
    token = pwinput.pwinput(prompt=prompt).strip()

    client = await Client.authenticate(
      auth=token,
      integration_name="1Password systemd-creds sync",
      integration_version="v1.0.0"
    )

    # Find the correct vault
    vaults = await client.vaults.list()
    vault = next(filter(lambda v: v.title == "Homelab", vaults))

    # Get the hostname
    hostname = platform.node()
    hostname_tag = f"host-{hostname}"

    # Get all the items
    overviews = await client.items.list(vault.id)
    for overview in overviews:
        item = await client.items.get(vault.id, overview.id)
        print(f"Fetching {item.title}")

        # Only sync items that have the proper tag for this host or the all tag
        if hostname_tag not in item.tags and "host-all" not in item.tags:
            print("Syncing Skipped")
            print()
            continue

        # If it's a password just write the value out to a file
        # If it's a secure note construct a envfile from all the fields
        if item.category == "Password":
            field = next(filter(is_password_field, item.fields), None)
            write_systemd_secret(item.title, field.value)
        elif item.category == "SecureNote":
            file = ""

            if "json" in item.tags:
                # Build a json file from the fields
                fields = {}
                for field in item.fields:
                    if field.field_type == "Concealed":
                        fields[field.title] = field.value
                file = json.dumps(fields)
            else:
                # Build an envfile from the fields
                for field in item.fields:
                    if field.field_type == "Concealed":
                        file += f"{field.title}={field.value}\n"
                file += "\n"

            write_systemd_secret(item.title, file)

        print()

asyncio.run(main())
