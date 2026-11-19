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

{{- define "leads-api.pullSecrets" -}}
{{- $pullSecrets := .Values.imagePullSecrets | default list -}}
{{- if .Values.ecrPullSecret.enabled -}}
{{- $pullSecrets = prepend $pullSecrets (dict "name" .Values.ecrPullSecret.name) -}}
{{- end -}}
{{- with $pullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end -}}
{{- end -}}

{{- define "leads-api.ecrRefresher" -}}
{{- printf "%s-ecr-refresh" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* ECR registry host (<account>.dkr.ecr.<region>.amazonaws.com): ecrPullSecret.registry, else the host of image.repository. */}}
{{- define "leads-api.ecrRegistry" -}}
{{- $registry := .Values.ecrPullSecret.registry | default (first (splitList "/" (toString .Values.image.repository))) -}}
{{- if not (contains ".dkr.ecr." $registry) -}}
{{- fail (printf "ecrPullSecret: %q is not an ECR registry host; set ecrPullSecret.registry or disable ecrPullSecret" $registry) -}}
{{- end -}}
{{- $registry -}}
{{- end -}}

{{/* Every ECR registry the pull secret covers, space-separated: the API registry, ecrPullSecret.extraRegistries and, with telephony enabled, telephony.registry. */}}
{{- define "leads-api.ecrRegistries" -}}
{{- $registries := list (include "leads-api.ecrRegistry" .) -}}
{{- $extra := .Values.ecrPullSecret.extraRegistries | default list -}}
{{- if and .Values.telephony.enabled .Values.telephony.registry -}}
{{- $extra = append $extra .Values.telephony.registry -}}
{{- end -}}
{{- range $extra -}}
{{- if not (contains ".dkr.ecr." .) -}}
{{- fail (printf "ecrPullSecret: %q is not an ECR registry host (<account>.dkr.ecr.<region>.amazonaws.com)" .) -}}
{{- end -}}
{{- $registries = append $registries (trimSuffix "/" .) -}}
{{- end -}}
{{- $registries | uniq | join " " -}}
{{- end -}}

{{/* Job spec that fetches an ECR token per registry and writes one pull secret covering all of them. Takes dict root, serviceAccount. */}}
{{- define "leads-api.ecrJobSpec" -}}
{{- $v := .root.Values.ecrPullSecret -}}
{{- $registries := splitList " " (include "leads-api.ecrRegistries" .root) -}}
backoffLimit: 2
activeDeadlineSeconds: 300
template:
  metadata:
    labels:
      app.kubernetes.io/name: leads-api-ecr-refresh
      app.kubernetes.io/instance: {{ .root.Release.Name }}
  spec:
    serviceAccountName: {{ .serviceAccount }}
    restartPolicy: Never
    initContainers:
      - name: get-token
        image: {{ $v.awsCliImage }}
        command:
          - /bin/sh
          - -c
          - |
            set -eu
            {{- range $registries }}
            aws ecr get-login-password --region {{ index (splitList "." .) 3 }} > /token/{{ . }}
            {{- end }}
        volumeMounts:
          - name: token
            mountPath: /token
    containers:
      - name: write-secret
        image: {{ $v.kubectlImage }}
        command:
          - /bin/sh
          - -c
          - |
            set -eu
            auths=""
            for registry in {{ join " " $registries }}; do
              token="$(cat "/token/$registry")"
              auth="$(printf 'AWS:%s' "$token" | base64 | tr -d '\n')"
              auths="${auths:+$auths,}\"$registry\":{\"username\":\"AWS\",\"password\":\"$token\",\"auth\":\"$auth\"}"
            done
            printf '{"auths":{%s}}' "$auths" > /tmp/config.json
            kubectl create secret generic {{ $v.name }} \
              --namespace {{ .root.Release.Namespace }} \
              --type=kubernetes.io/dockerconfigjson \
              --from-file=.dockerconfigjson=/tmp/config.json \
              --dry-run=client -o yaml | kubectl apply -f -
            rm -f /tmp/config.json
        volumeMounts:
          - name: token
            mountPath: /token
            readOnly: true
    volumes:
      - name: token
        emptyDir:
          medium: Memory
{{- end -}}

{{/* Service names of the externalDb bridge: serviceName, else <fullname>-postgres / -elasticsearch. */}}
{{- define "leads-api.pgServiceName" -}}
{{- .Values.externalDb.postgres.serviceName | default (printf "%s-postgres" (include "leads-api.fullname" .)) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "leads-api.esServiceName" -}}
{{- .Values.externalDb.elasticsearch.serviceName | default (printf "%s-elasticsearch" (include "leads-api.fullname" .)) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
