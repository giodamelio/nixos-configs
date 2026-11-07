{{- /* step-ca's default leaf template plus O=nfs, naming the provisioner. */ -}}
{
  "subject": {
    "commonName": {{ toJson .Subject.CommonName }},
    "organization": "nfs"
  },
  "sans": {{ toJson .SANs }},
{{- if typeIs "*rsa.PublicKey" .Insecure.CR.PublicKey }}
  "keyUsage": ["keyEncipherment", "digitalSignature"],
{{- else }}
  "keyUsage": ["digitalSignature"],
{{- end }}
  "extKeyUsage": ["serverAuth", "clientAuth"]
}
