#!/usr/bin/env nix-shell
#! nix-shell -i nu -p nushell

def main [
  host: string # The host to deploy secrets to
] {
  print $"Deploying secrets to ($host)"
  print

  ssh $host "sudo mkdir -p /usr/lib/credstore.encrypted"

  let secret_files = (glob $"($host)/*.age") 
  for file in $secret_files {
    let parsed_file = ($file | path parse)

    print $"Deploying ($parsed_file.stem) to /usr/lib/credstore.encrypted/($parsed_file.stem)"
    (
      cat $file
      | rage --decrypt -i ./key -
      | ssh $host $"sudo systemd-creds encrypt - /usr/lib/credstore.encrypted/($parsed_file.stem)"
    )
  }
}

# Edit an encrypted file
def "main edit" [
  file: string # A file to edit
] {
  if not ($file | path exists) {
    print $"Creating new file: ($file)"

    let recipient = (rage-keygen -y ./key)
    echo "" | rage -r $recipient | save $file
  }

  agedit --identity-file ./key $file
}

# Print an encrypted file
def "main cat" [
  file: string # A file to print
] {
  cat $file | rage --decrypt --identity ./key
}
