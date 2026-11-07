{{- /*
  Identity comes only from .Token.*, which the provisioner key signed here on
  strontium. Never read .Insecure.*: .Insecure.User is whatever the requesting
  host passes to `step ca certificate --set`, so it could pick its own role.
*/ -}}
{{- $user := .Token.user | default dict }}
{{- if not $user.role }}{{ fail "app token carries no role (mint it with --set role=<role>)" }}{{ end }}
{
  "subject": {
    "commonName": {{ toJson .Token.sub }},
    "organization": "app",
    "organizationalUnit": {{ toJson $user.role }}
  },
  "sans": [
  {{- range $i, $san := .Token.sans }}
    {{- if $i }},{{ end }}
    {{- if hasPrefix "spiffe://" $san }}
    {"type": "uri", "value": {{ toJson $san }}}
    {{- else if or (regexMatch "^[0-9.]+$" $san) (contains ":" $san) }}
    {"type": "ip", "value": {{ toJson $san }}}
    {{- else }}
    {"type": "dns", "value": {{ toJson $san }}}
    {{- end }}
  {{- end }}
  ],
  "keyUsage": ["digitalSignature"],
  "extKeyUsage": ["serverAuth", "clientAuth"],
  "crlDistributionPoints": ["http://crl.gio.ninja/"]
}
