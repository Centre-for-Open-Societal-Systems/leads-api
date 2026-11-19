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

{{/* Takes dict registry, image. <registry>/<repository>@<digest>, or :<tag> without a digest. */}}
{{- define "telephony.image" -}}
{{- $repository := required "telephony: enabled component requires image.repository" .image.repository -}}
{{- if .registry -}}
{{- $repository = printf "%s/%s" (trimSuffix "/" .registry) $repository -}}
{{- end -}}
{{- if .image.digest -}}
{{- if not (regexMatch "^sha256:[a-f0-9]{64}$" .image.digest) -}}
{{- fail "telephony: image.digest must be sha256 followed by 64 lowercase hex characters" -}}
{{- end -}}
{{- printf "%s@%s" $repository .image.digest -}}
{{- else -}}
{{- printf "%s:%s" $repository (required "telephony: enabled component requires image.tag or image.digest" .image.tag) -}}
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
