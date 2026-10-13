{{- define "de-worker.labels" -}}
app.kubernetes.io/name: de-worker
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}

{{- define "de-worker.selector" -}}
app.kubernetes.io/name: de-worker
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
