def main [
  host: string # The host to deploy secrets to
] {
  echo $"Deploying secrets to ($host)"
  echo

  let secret_files = (ls *.age)
  for file in $secret_files {
    let parsed_file = ($file.name | path parse)

    echo $"Deploying ($file.name) to /usr/lib/credstore.encrypted/($parsed_file.stem)"
    (
      cat $file.name
      | rage --decrypt -i ./key -
      | ssh $host $"sudo systemd-creds encrypt - /usr/lib/credstore.encrypted/($parsed_file.stem)"
    )
  }
}
