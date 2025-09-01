{{/*
Expand the name of the chart.
*/}}
{{- define "shape-network-node.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "shape-network-node.fullname" -}}
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

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "shape-network-node.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "shape-network-node.labels" -}}
helm.sh/chart: {{ include "shape-network-node.chart" . }}
{{ include "shape-network-node.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "shape-network-node.selectorLabels" -}}
app.kubernetes.io/name: {{ include "shape-network-node.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "shape-network-node.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "shape-network-node.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generate JWT secret - must be 64 hex characters for op-geth
*/}}
{{- define "shape-network-node.jwtSecret" -}}
{{- if .Values.security.jwtSecret }}
{{- .Values.security.jwtSecret }}
{{- else }}
{{- printf "%032x%032x" (randInt 0 4294967295 | int64) (randInt 0 4294967295 | int64) }}
{{- end }}
{{- end }}

{{/*
Bootnodes string
*/}}
{{- define "shape-network-node.bootnodes" -}}
{{- join "," .Values.bootnodes }}
{{- end }}
