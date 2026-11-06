def fail [msg: string] {
    error make --unspanned {msg: $"agent-dms: ($msg)"}
}

def check-name [kind: string, value: string] {
    if ($value | find --regex '^[a-z0-9-]+$' | is-empty) {
        fail $"($kind) `($value)` must match [a-z0-9-]+"
    }
}

def --wrapped must [...args: string] {
    let r = (^$args.0 ...($args | skip 1) | complete)
    if $r.exit_code != 0 {
        fail $"`($args | str join ' ')` failed: ($r.stderr | str trim)"
    }
    $r.stdout | str trim
}

def --wrapped try-run [...args: string] {
    let r = (^$args.0 ...($args | skip 1) | complete)
    if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

def repo-root [] {
    try-run jj workspace root --ignore-working-copy
    | default (try-run git rev-parse --show-toplevel)
    | default $env.PWD
}

# The main checkout has no tag. jj: a secondary workspace's .jj/repo is a file
# pointing at the main one. git: a linked worktree's git dir differs from the
# common dir.
def workspace-tag [root: string] {
    let jj_repo = ($root | path join .jj repo)
    let tag = if ($jj_repo | path exists) {
        if ($jj_repo | path type) == dir {
            ""
        } else {
            let names = (must jj log -r @ --no-graph --ignore-working-copy -T 'working_copies.map(|w| w.name()).join("\n")' | lines)
            if ($names | length) != 1 {
                fail $"can't tell which jj workspace this is: @ is the working copy of ($names | str join ', ')"
            }
            $names | first
        }
    } else if (try-run git -C $root rev-parse --git-dir) != null {
        let dirs = (must git -C $root rev-parse --path-format=absolute --git-dir --git-common-dir | lines)
        if ($dirs.0 == $dirs.1) { "" } else { $root | path basename }
    } else {
        ""
    }
    if $tag != "" { check-name "workspace name" $tag }
    $tag
}

def main-repo-name [root: string] {
    let jj_repo = ($root | path join .jj repo)
    if ($jj_repo | path type) == file {
        open --raw $jj_repo | str trim | path expand | path dirname | path dirname | path basename
    } else if ($jj_repo | path exists) {
        $root | path basename
    } else if (try-run git -C $root rev-parse --git-dir) != null {
        must git -C $root rev-parse --path-format=absolute --git-common-dir | path dirname | path basename
    } else {
        $root | path basename
    }
}

def project [] {
    let root = (repo-root)
    let file = ($root | path join .agent-dms.yml)
    if not ($file | path exists) {
        fail $"no .agent-dms.yml in ($root). Ask the user to run `agent-dms init` there, outside the jail."
    }
    let name = (open $file | get name)
    check-name "project name" $name
    let tag = (workspace-tag $root)
    let local = if $tag == "" { $name } else { $"($name)+($tag)" }
    {
        root: $root
        name: $name
        tag: $tag
        login: $"($name)@($domain)"
        address: $"($local)@($domain)"
    }
}

def password-env [] {
    if ($env.AGENT_DMS_PASSWORD? | is-empty) {
        fail "AGENT_DMS_PASSWORD is not set. Outside the jail, run `agent-dms init` in this repo; inside, restart the jail after init."
    }
}

def himalaya-config [login: string, password_command: string] {
    let path = (mktemp -t agent-dms.XXXXXX.toml)
    {
        accounts: {
            agent-dms: {
                default: true
                email: $login
                jmap: {
                    # himalaya refuses the redirect /.well-known/jmap answers with.
                    server: $"($server)/jmap/session"
                    auth: {basic: {username: $login, password: {command: $password_command}}}
                }
            }
        }
    } | to toml | save --force $path
    $path
}

def with-himalaya [login: string, password_command: string, body: closure] {
    let config = (himalaya-config $login $password_command)
    let result = (try { do $body $config } catch {|e| rm -f $config; error make $e.raw })
    rm -f $config
    $result
}

# Sends raw JMAP method calls through himalaya, which owns auth and session
# discovery, and returns the responses keyed by call id. A method-level error
# fails the whole command.
def jmap-as [login: string, password_command: string, calls: list, --using: list<string> = []] {
    let using_args = ($using | each {|u| ["--using" $u] } | flatten)
    let out = (with-himalaya $login $password_command {|config|
        $calls | to json --raw | ^himalaya -c $config --json jmap query ...$using_args - | complete
    })
    if $out.exit_code != 0 {
        # With --json, himalaya reports errors on stdout as {error, sources}.
        let reason = (try {
            let e = ($out.stdout | from json)
            [$e.error ...($e.sources? | default [])] | str join ": "
        } catch {
            [$out.stdout $out.stderr] | str join " " | str trim
        })
        fail $"JMAP request failed: ($reason)"
    }
    let responses = ($out.stdout | from json | get method_responses)
    let errors = ($responses | where {|r| $r.0 == "error" })
    if not ($errors | is-empty) {
        let e = ($errors | first)
        fail $"JMAP call ($e.2) failed: ($e.1.type)(if ($e.1.description? | is-empty) { '' } else { $': ($e.1.description)' })"
    }
    $responses | reduce --fold {} {|r, acc| $acc | insert $r.2 $r.1 }
}

def jmap [p: record, calls: list] {
    password-env
    jmap-as $p.login "printenv AGENT_DMS_PASSWORD" $calls
}

def set-errors [response: record, what: string] {
    for field in [notCreated notUpdated notDestroyed] {
        let failed = ($response | get -o $field | default {})
        if not ($failed | is-empty) {
            let first = ($failed | transpose id err | first)
            fail $"($what): ($first.err.type)(if ($first.err.description? | is-empty) { '' } else { $': ($first.err.description)' })"
        }
    }
}

def mailboxes [p: record] {
    let r = (jmap $p [["Mailbox/get", {properties: [id role name]}, "m"]])
    let list = $r.m.list
    let by_role = {|role|
        let found = ($list | where role == $role)
        if ($found | is-empty) { fail $"no mailbox with role ($role) on ($p.login)" }
        $found | first | get id
    }
    {
        inbox: (do $by_role inbox)
        archive: (do $by_role archive)
        drafts: (do $by_role drafts)
        sent: (do $by_role sent)
    }
}

# The tag a message was sent to: the +tag on whichever recipient is this project.
def tag-of [p: record, email: record] {
    let mine = ($email.to? | default [] | append ($email.cc? | default []) | get email | each {|a|
        let parsed = ($a | parse --regex '^(?P<name>[a-z0-9-]+)(\+(?P<tag>[a-z0-9-]+))?@(?P<domain>.+)$')
        if ($parsed | is-empty) { null } else { $parsed | first }
    } | compact | where {|a| $a.name == $p.name and $a.domain == $domain })
    if ($mine | is-empty) { "" } else { $mine | first | get tag | default "" }
}

def format-addresses [addrs] {
    $addrs | default [] | each {|a| if ($a.name? | is-empty) { $a.email } else { $"($a.name) <($a.email)>" } } | str join ", "
}

def thread-emails [p: record, id: string] {
    let r = (jmap $p [
        ["Email/get", {ids: [$id], properties: [threadId]}, "e"]
        ["Thread/get", {"#ids": {resultOf: "e", name: "Email/get", path: "/list/*/threadId"}}, "t"]
        ["Email/get", {
            "#ids": {resultOf: "t", name: "Thread/get", path: "/list/*/emailIds"}
            properties: [id threadId mailboxIds keywords messageId from to cc subject sentAt receivedAt textBody bodyValues]
            fetchTextBodyValues: true
        }, "m"]
    ])
    if not ($r.e.notFound | is-empty) { fail $"no message with id ($id)" }
    $r.m.list | sort-by receivedAt
}

def print-thread [emails: list] {
    $emails | each {|e|
        let body = ($e.textBody | default [] | each {|part| $e.bodyValues | get -o $part.partId | get -o value | default "" } | str join "\n")
        [
            $"=== ($e.id)(if ($e.keywords | get -o '$seen' | default false) { '' } else { '  [unread]' })"
            $"From: (format-addresses $e.from)"
            $"To: (format-addresses $e.to)"
            $"Subject: ($e.subject? | default '')"
            $"Date: ($e.sentAt? | default $e.receivedAt)"
            ""
            $body
        ] | str join "\n"
    } | str join "\n\n" | print
}

def recipient [to: string] {
    let parsed = ($to | parse --regex '^(?P<name>[a-z0-9-]+)(\+(?P<tag>[a-z0-9-]+))?(@(?P<domain>.+))?$')
    if ($parsed | is-empty) {
        fail $"recipient `($to)` must be <project> or <project>+<workspace>"
    }
    let r = ($parsed | first)
    if ($r.domain | is-not-empty) and $r.domain != $domain {
        fail $"recipient `($to)` is outside ($domain)"
    }
    if ($r.tag | is-empty) { $"($r.name)@($domain)" } else { $"($r.name)+($r.tag)@($domain)" }
}

def read-body [body_file?: path] {
    let body = if $body_file != null { open --raw $body_file } else { $in }
    if ($body | is-empty) { fail "empty body: pipe it on stdin or pass --body-file" }
    $body
}

def submit [p: record, to: string, subject: string, body: string, reply_to?: record] {
    let boxes = (mailboxes $p)
    let identities = (jmap $p [["Identity/get", {}, "i"]]).i.list
    let identity = ($identities | where email == $p.login)
    if ($identity | is-empty) { fail $"no JMAP identity for ($p.login)" }
    let threading = if $reply_to == null { {} } else {
        {
            inReplyTo: $reply_to.messageId
            references: ($reply_to.references? | default [] | append $reply_to.messageId)
        }
    }
    # Stalwart only lets an account send as its exact address, so a workspace
    # sends as the project and takes replies through Reply-To.
    let workspace = if $p.tag == "" { {} } else { {replyTo: [{email: $p.address}]} }
    let email = ({
        mailboxIds: {($boxes.drafts): true}
        keywords: {"$draft": true, "$seen": true}
        from: [{name: ($p.address | split row "@" | first), email: $p.login}]
        to: [{email: $to}]
        subject: $subject
        textBody: [{partId: "body", type: "text/plain"}]
        bodyValues: {body: {value: $body}}
    } | merge $threading | merge $workspace)
    let r = (jmap $p [
        ["Email/set", {create: {draft: $email}}, "c"]
        ["EmailSubmission/set", {
            create: {send: {emailId: "#draft", identityId: ($identity | first | get id)}}
            onSuccessUpdateEmail: {"#send": {
                $"mailboxIds/($boxes.drafts)": null
                $"mailboxIds/($boxes.sent)": true
                "keywords/$draft": null
            }}
        }, "s"]
        ["EmailSubmission/get", {
            "#ids": {resultOf: "s", name: "EmailSubmission/set", path: "/created/send/id"}
            properties: [deliveryStatus]
        }, "d"]
    ])
    set-errors $r.c "creating the message failed"
    set-errors $r.s "sending failed"
    # Stalwart checks local recipients during submission and records a refusal
    # here instead of failing the call or sending a bounce.
    let refused = ($r.d.list | first | get -o deliveryStatus | default {} | transpose rcpt status | where {|s| $s.status.delivered == "no" })
    if not ($refused | is-empty) {
        fail $"($refused | first | get rcpt) refused: ($refused | first | get status.smtpReply). Check the project name."
    }
    $r.c.created.draft.id
}

def keyword-patch [ids: list, keyword: string, value] {
    $ids | reduce --fold {} {|id, acc| $acc | insert $id {$"keywords/($keyword)": $value} }
}

# Show this checkout's address and workspace tag.
def "main whoami" [] {
    let p = (project)
    {address: $p.address, project: $p.name, workspace: $p.tag, login: $p.login} | print
}

# List the inbox, oldest first. A workspace sees only mail sent to its +tag.
def "main list" [
    --unread    # only unread messages
    --untagged  # main checkout: only mail with no +tag
    --all       # workspace: mail for every tag
    --json      # print JSON
] {
    let p = (project)
    let boxes = (mailboxes $p)
    let filter = if $unread { {inMailbox: $boxes.inbox, notKeyword: "$seen"} } else { {inMailbox: $boxes.inbox} }
    let r = (jmap $p [
        ["Email/query", {filter: $filter, sort: [{property: receivedAt, isAscending: true}]}, "q"]
        ["Email/get", {
            "#ids": {resultOf: "q", name: "Email/query", path: "/ids"}
            properties: [id threadId from to cc subject receivedAt keywords]
        }, "g"]
    ])
    let rows = ($r.g.list | each {|e|
        {
            id: $e.id
            unread: (not ($e.keywords | get -o '$seen' | default false))
            date: $e.receivedAt
            from: (format-addresses $e.from)
            subject: ($e.subject? | default "")
            tag: (tag-of $p $e)
        }
    })
    let shown = if $p.tag != "" {
        if $all { $rows } else { $rows | where tag == $p.tag }
    } else if $untagged {
        $rows | where tag == ""
    } else {
        $rows
    }
    if $json { $shown | to json | print } else if ($shown | is-empty) { print "No messages." } else { $shown | print }
}

# Show the whole thread a message belongs to, oldest first, without marking it read.
def "main peek" [id: string, --json] {
    let p = (project)
    let emails = (thread-emails $p $id)
    if $json { $emails | to json | print } else { print-thread $emails }
}

# Show the thread, then mark every message in it read.
def "main read" [id: string, --json] {
    let p = (project)
    let emails = (thread-emails $p $id)
    if $json { $emails | to json | print } else { print-thread $emails }
    let r = (jmap $p [["Email/set", {update: (keyword-patch ($emails | get id) '$seen' true)}, "u"]])
    set-errors $r.u "marking the thread read failed"
}

# Mark every message in the thread unread again.
def "main unread" [id: string] {
    let p = (project)
    let emails = (thread-emails $p $id)
    let r = (jmap $p [["Email/set", {update: (keyword-patch ($emails | get id) '$seen' null)}, "u"]])
    set-errors $r.u "marking the thread unread failed"
}

# Move the thread out of the inbox into Archive.
def "main archive" [id: string] {
    let p = (project)
    let boxes = (mailboxes $p)
    let emails = (thread-emails $p $id | where {|e| $e.mailboxIds | get -o $boxes.inbox | default false })
    if ($emails | is-empty) { fail $"nothing in the thread of ($id) is in the inbox" }
    let patch = ($emails | get id | reduce --fold {} {|id, acc|
        $acc | insert $id {$"mailboxIds/($boxes.inbox)": null, $"mailboxIds/($boxes.archive)": true}
    })
    let r = (jmap $p [["Email/set", {update: $patch}, "u"]])
    set-errors $r.u "archiving failed"
}

# Send a message to another project, or one of its workspaces as <project>+<workspace>. The body is read from stdin.
def "main send" [
    to: string             # <project> or <project>+<workspace>
    --subject (-s): string # a short, imperative subject line
    --body-file: path      # read the body from a file instead of stdin
] {
    let body = (read-body $body_file)
    if ($subject | is-empty) { fail "--subject is required" }
    let p = (project)
    let id = (submit $p (recipient $to) $subject $body)
    print $"Sent ($id) to (recipient $to)."
}

# Reply to a message, staying in its thread. The body is read from stdin.
def "main reply" [
    id: string
    --body-file: path
] {
    let body = (read-body $body_file)
    let p = (project)
    let r = (jmap $p [["Email/get", {ids: [$id], properties: [id messageId references from replyTo subject]}, "g"]])
    if ($r.g.list | is-empty) { fail $"no message with id ($id)" }
    let original = ($r.g.list | first)
    let to = ($original.replyTo? | default $original.from | first | get email)
    let subject = ($original.subject? | default "")
    let subject = if ($subject | str lowercase | str starts-with "re:") { $subject } else { $"Re: ($subject)" }
    let sent = (submit $p $to $subject $body $original)
    let a = (jmap $p [["Email/set", {update: (keyword-patch [$id] '$answered' true)}, "a"]])
    set-errors $a.a "marking the original answered failed"
    print $"Sent ($sent) to ($to)."
}

def --wrapped stalwart-cli-as-admin [password: string, ...args: string] {
    with-env {STALWART_URL: $server, STALWART_USER: "admin", STALWART_PASSWORD: $password} {
        must stalwart-cli ...$args
    }
}

def query-id [password: string, object: string, where: string] {
    let rows = (stalwart-cli-as-admin $password query $object --where $where --json --fields id | lines | where {|l| $l != "" } | each { from json })
    if ($rows | length) > 1 { fail $"more than one ($object) matches ($where)" }
    if ($rows | is-empty) { null } else { $rows | first | get id }
}

def created-id [output: string, object: string] {
    let m = ($output | parse --regex ($"Created ($object) " + '(?P<id>\S+)'))
    if ($m | is-empty) { fail $"couldn't find the new ($object) id in stalwart-cli's output: ($output)" }
    $m | first | get id
}

# Mailbox sharing and app passwords are per-account JMAP calls, so they run as
# the project through a master-user login: <project>@domain%admin.
def jmap-as-project [admin_password: string, login: string, calls: list, --using: list<string> = []] {
    with-env {AGENT_DMS_ADMIN_PASSWORD: $admin_password} {
        jmap-as $"($login)%admin" "printenv AGENT_DMS_ADMIN_PASSWORD" $calls --using $using
    }
}

# Everything here is idempotent, so a re-run repairs a half-finished init.
def ensure-account [admin_password: string, name: string, login: string] {
    let gio_id = (query-id $admin_password Account $"name=($owner)")
    if $gio_id == null { fail $"no ($owner) account on the server; has stalwart-apply run?" }
    if (query-id $admin_password Account $"name=($name)") == null {
        let domain_id = (query-id $admin_password Domain $"name=($domain)")
        if $domain_id == null { fail $"no ($domain) domain on the server; has stalwart-apply run?" }
        let out = (stalwart-cli-as-admin $admin_password create Account --json ({"@type": "User", name: $name, domainId: $domain_id} | to json --raw))
        created-id $out Account
        print $"Created ($login)."
    }

    let boxes = (jmap-as-project $admin_password $login [["Mailbox/get", {properties: [id role]}, "m"]]).m.list
    if ($boxes | where role == archive | is-empty) {
        let r = (jmap-as-project $admin_password $login [["Mailbox/set", {create: {a: {name: "Archive", role: "archive"}}}, "c"]])
        set-errors $r.c "creating Archive failed"
    }
    let boxes = (jmap-as-project $admin_password $login [["Mailbox/get", {properties: [id role]}, "m"]]).m.list
    let rights = {mayReadItems: true, mayAddItems: true, mayRemoveItems: true, maySetSeen: true, maySetKeywords: true}
    let patch = ($boxes | where role in [inbox archive] | reduce --fold {} {|b, acc|
        $acc | insert $b.id {$"shareWith/($gio_id)": $rights}
    })
    let r = (jmap-as-project $admin_password $login [["Mailbox/set", {update: $patch}, "s"]])
    set-errors $r.s $"sharing the inbox with ($owner) failed"
}

def keyring-password [name: string] {
    try-run secret-tool lookup service agent-dms project $name
}

def password-works [login: string, name: string] {
    try {
        jmap-as $login $"secret-tool lookup service agent-dms project ($name)" [["Mailbox/get", {ids: []}, "m"]]
        true
    } catch {
        false
    }
}

# One app password per host, so init on another machine adds one instead of
# copying a secret around.
def replace-app-password [admin_password: string, login: string, name: string] {
    let description = $"host:(sys host | get hostname)"
    let using = ["urn:stalwart:jmap"]
    # Stalwart only filters app passwords on expiresAt.
    let existing = (jmap-as-project $admin_password $login [
        ["x:AppPassword/query", {}, "q"]
        ["x:AppPassword/get", {
            "#ids": {resultOf: "q", name: "x:AppPassword/query", path: "/ids"}
            properties: [id description]
        }, "g"]
    ] --using $using).g.list | where description == $description | get id
    if not ($existing | is-empty) {
        let r = (jmap-as-project $admin_password $login [["x:AppPassword/set", {destroy: $existing}, "d"]] --using $using)
        set-errors $r.d "removing the old app password failed"
    }
    let permissions = ([
        authenticate emailSend
        jmapEmailGet jmapEmailQuery jmapEmailCreate jmapEmailUpdate
        jmapMailboxGet jmapThreadGet jmapIdentityGet
        jmapEmailSubmissionCreate jmapEmailSubmissionGet
    ] | reduce --fold {} {|p, acc| $acc | insert $p true })
    let r = (jmap-as-project $admin_password $login [["x:AppPassword/set", {create: {n: {
        description: $description
        permissions: {"@type": "Replace", permissions: $permissions}
    }}}, "c"]] --using $using)
    set-errors $r.c "creating the app password failed"
    let secret = ($r.c.created.n.secret)
    $secret | ^secret-tool store --label $"agent-dms ($login)" service agent-dms project $name
    print $"Stored a new app password for ($login) as ($description)."
}

# Set up this repo's inbox and this host's access to it. Run on the host, not in the jail.
def "main init" [] {
    if ($env.AGENT_DMS_PASSWORD? | is-not-empty) {
        fail "init runs on the host, outside the jail"
    }
    let root = (repo-root)
    let file = ($root | path join .agent-dms.yml)
    let name = if ($file | path exists) {
        open $file | get name
    } else {
        let default = (main-repo-name $root)
        let answer = (input $"Project name [($default)]: " | str trim)
        if $answer == "" { $default } else { $answer }
    }
    check-name "project name" $name
    if not ($file | path exists) {
        {name: $name} | to yaml | save $file
        print $"Wrote ($file); commit it."
    }
    let login = $"($name)@($domain)"

    if (keyring-password $name) != null and (password-works $login $name) {
        print $"($login) is already set up on this host."
        return
    }

    let admin_password = (must op item get $admin_item --reveal --fields=password)
    ensure-account $admin_password $name $login
    replace-app-password $admin_password $login $name
    if not (password-works $login $name) {
        fail $"the new app password for ($login) doesn't log in"
    }
    print "Done. Restart the jail in this repo to pick it up."
}

# Run himalaya against this project's account, for anything the verbs don't cover.
def --wrapped "main himalaya" [...args] {
    let p = (project)
    password-env
    with-himalaya $p.login "printenv AGENT_DMS_PASSWORD" {|config| ^himalaya -c $config ...$args }
}

def main [] {
    print "agent-dms - an inbox per project for coding agents"
    print ""
    print "  agent-dms whoami"
    print "  agent-dms list [--unread] [--untagged | --all] [--json]"
    print "  agent-dms peek <id>       show the thread, leave it unread"
    print "  agent-dms read <id>       show the thread, mark it read"
    print "  agent-dms unread <id>"
    print "  agent-dms archive <id>"
    print "  agent-dms send <project>[+<workspace>] -s <subject>   body on stdin"
    print "  agent-dms reply <id>                                 body on stdin"
    print "  agent-dms himalaya ..."
    print "  agent-dms init            on the host, outside the jail"
}
