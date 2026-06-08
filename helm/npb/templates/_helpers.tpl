{{/*
_helpers.tpl — reusable template snippets
Think of these as utility functions. Templates call them with {{ include "npb.xxx" . }}
*/}}

{{/*
Chart name — used as a base for resource names
*/}}
{{- define "npb.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full name — combines release name and chart name
Helm supports installing the same chart multiple times with different release names.
This ensures resource names don't collide.
*/}}
{{- define "npb.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to every resource for consistent identification
These labels let you query all resources from this chart with:
  kubectl get all -l app.kubernetes.io/name=npb
*/}}
{{- define "npb.labels" -}}
app.kubernetes.io/name: {{ include "npb.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end }}

{{/*
Selector labels — used in spec.selector.matchLabels
Must be a SUBSET of the full labels and must never change after creation
*/}}
{{- define "npb.selectorLabels.app" -}}
app.kubernetes.io/name: {{ include "npb.name" . }}
app.kubernetes.io/component: app
{{- end }}

{{- define "npb.selectorLabels.database" -}}
app.kubernetes.io/name: {{ include "npb.name" . }}
app.kubernetes.io/component: database
{{- end }}
