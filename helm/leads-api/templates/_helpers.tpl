{{- define "leads-api.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "leads-api.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "leads-api.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "leads-api.labels" -}}
helm.sh/chart: {{ include "leads-api.chart" . }}
{{ include "leads-api.baseSelectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "leads-api.baseSelectorLabels" -}}
app.kubernetes.io/name: {{ include "leads-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Selector for API pods only - keeps redis pods out of the API Service/PDB */}}
{{- define "leads-api.selectorLabels" -}}
{{ include "leads-api.baseSelectorLabels" . }}
app.kubernetes.io/component: api
{{- end }}

{{- define "leads-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "leads-api.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "leads-api.image" -}}
{{- if .Values.image.digest -}}
{{ .Values.image.repository }}@{{ .Values.image.digest }}
{{- else -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}
{{- end }}

{{- define "leads-api.secretName" -}}
{{- default (printf "%s-secrets" (include "leads-api.fullname" .)) .Values.secrets.existingSecret }}
{{- end }}

{{- define "leads-api.redisName" -}}
{{- printf "%s-redis" (include "leads-api.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}
