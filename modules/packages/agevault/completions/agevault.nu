# nushell completions for agevault. Autoloaded from
# share/nushell/vendor/autoload; typed `extern` signatures with dynamic
# host/secret completers that read the vault on disk ($AGEVAULT_ROOT or $PWD).

def agevault-root [] {
  $env.AGEVAULT_ROOT? | default $env.PWD
}

def "nu-complete agevault hosts" [] {
  let d = (agevault-root | path join "hosts")
  if ($d | path exists) {
    ls $d | where type == dir | get name | each {|p| $p | path basename }
  } else { [] }
}

# `context` is the command line typed so far; the host is the 3rd token
# (`agevault <sub> <host>`). Split on whitespace only (preserve hyphenated host
# names) and drop empties so trailing spaces don't shift the index.
def "nu-complete agevault names" [context: string] {
  let host = (
    $context
    | split row --regex '\s+'
    | where ($it | is-not-empty)
    | get 2?
    | default ""
  )
  let d = (agevault-root | path join "hosts" $host)
  if ($host | is-not-empty) and ($d | path exists) {
    ls $d
    | get name
    | each {|p| $p | path basename }
    | where ($it | str ends-with ".age")
    | each {|f| $f | str replace --regex '\.age$' '' }
  } else { [] }
}

export extern "agevault cat" [
  host: string@"nu-complete agevault hosts"
  name: string@"nu-complete agevault names"
]

export extern "agevault write" [
  host: string@"nu-complete agevault hosts"
  name: string@"nu-complete agevault names"
  source?: string # `-` for stdin (default) or a path to a plaintext file
]

export extern "agevault edit" [
  host: string@"nu-complete agevault hosts"
  name: string@"nu-complete agevault names"
]

export extern "agevault rm" [
  host: string@"nu-complete agevault hosts"
  name: string@"nu-complete agevault names"
]

export extern "agevault push" [
  host?: string@"nu-complete agevault hosts"
  name?: string@"nu-complete agevault names"
]

export extern "agevault rekey" []

export extern "agevault generate-toml" []
