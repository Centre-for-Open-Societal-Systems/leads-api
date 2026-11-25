{{/* Resource name prefix: <release>-telephony (leads-api-telephony). */}}
{{- define "telephony.fullname" -}}
{{- printf "%s-telephony" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}

{{- define "telephony.labels" -}}
app.kubernetes.io/name: telephony
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
{{- end -}}

{{/* Takes dict root, component. Distinct from the Leads API pods (component api/redis). */}}
{{- define "telephony.selectorLabels" -}}
app.kubernetes.io/name: telephony
app.kubernetes.io/instance: {{ .root.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/* Takes dict registry, image. <registry>/<repository>:<tag> whenever a tag is set (the build number, e.g. 0.1.0-develop.23; the digest, if given, is only checked, the ECR tags are immutable), else @<digest>. */}}
{{- define "telephony.image" -}}
{{- $repository := required "telephony: enabled component requires image.repository" .image.repository -}}
{{- if .registry -}}
{{- $repository = printf "%s/%s" (trimSuffix "/" .registry) $repository -}}
{{- end -}}
{{- if .image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .image.digest) -}}
{{- fail "telephony: image.digest must be sha256 followed by 64 lowercase hex characters" -}}
{{- end -}}
{{- if .image.tag -}}
{{- printf "%s:%s" $repository (first (splitList "@" (toString .image.tag))) -}}
{{- else -}}
{{- printf "%s@%s" $repository .image.digest -}}
{{- end -}}
{{- else -}}
{{- printf "%s:%s" $repository (first (splitList "@" (toString (required "telephony: enabled component requires image.tag or image.digest" .image.tag)))) -}}
{{- end -}}
{{- end -}}

{{- define "telephony.secretName" -}}
{{- required "telephony.secret.name (a Secret in the release namespace) is required" .Values.secret.name -}}
{{- end -}}

{{- define "telephony.pullSecrets" -}}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end -}}
{{- end -}}

{{- define "telephony.leadServiceUrl" -}}
{{- printf "http://%s-lead-service:8080" (include "telephony.fullname" .) -}}
{{- end -}}

{{/* The parent's API Service name: leadRegistry.serviceName, else the leads-api chart's default
fullname (<release> when the release name contains "leads-api", otherwise <release>-leads-api). */}}
{{- define "telephony.leadsApiService" -}}
{{- if .Values.leadRegistry.serviceName -}}
{{- .Values.leadRegistry.serviceName -}}
{{- else if contains "leads-api" .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-leads-api" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "telephony.leadRegistryUrl" -}}
{{- .Values.leadRegistry.url | default (printf "http://%s.%s.svc.cluster.local:%v/leads/v1/initiate" (include "telephony.leadsApiService" .) .Release.Namespace .Values.leadRegistry.leadsApiPort) -}}
{{- end -}}

{{- define "telephony.dbUrl" -}}
{{- if .Values.leadService.dbUrl -}}
{{- .Values.leadService.dbUrl -}}
{{- else if .Values.postgres.enabled -}}
{{- printf "jdbc:postgresql://%s-db:5432/%s" (include "telephony.fullname" .) .Values.postgres.database -}}
{{- else -}}
{{- fail "telephony: set leadService.dbUrl when postgres.enabled is false" -}}
{{- end -}}
{{- end -}}

{{/* The telephony Secret's data (secret.create): `secret.values`, then at install time
- DB_PASSWORD, when not given, copied from secret.dbPasswordFrom (a Secret in another namespace,
  e.g. the shared PostgreSQL's), so no one keeps a copy of it;
- ESL_PASSWORD, when not given, kept from this chart's existing Secret, else generated once.
Both use Helm `lookup` (the deployer needs `get` on those Secrets); `helm template` cannot read
the cluster, so set the values directly there. Returns YAML; used by the Secret and the
pods' checksum annotations. */}}
{{- define "telephony.secretData" -}}
{{- $v := deepCopy (.Values.secret.values | default dict) -}}
{{- $from := .Values.secret.dbPasswordFrom | default dict -}}
{{- if and $from.name (not (get $v "DB_PASSWORD")) -}}
{{- $src := lookup "v1" "Secret" ($from.namespace | default .Release.Namespace) $from.name -}}
{{- $raw := dig "data" ($from.key | default "password") "" $src -}}
{{- if not $raw -}}
{{- fail (printf "telephony.secret.dbPasswordFrom: cannot read key %q of Secret %s/%s (missing, or the deployer has no get on it)" ($from.key | default "password") ($from.namespace | default .Release.Namespace) $from.name) -}}
{{- end -}}
{{- $_ := set $v "DB_PASSWORD" (b64dec $raw) -}}
{{- end -}}
{{- if and .Values.secret.generateEslPassword (not (get $v "ESL_PASSWORD")) -}}
{{- $own := lookup "v1" "Secret" .Release.Namespace .Values.secret.name -}}
{{- $kept := dig "data" "ESL_PASSWORD" "" $own -}}
{{- $_ := set $v "ESL_PASSWORD" (ternary (b64dec $kept) (randAlphaNum 32) (ne $kept "")) -}}
{{- end -}}
{{- toYaml $v -}}
{{- end -}}
