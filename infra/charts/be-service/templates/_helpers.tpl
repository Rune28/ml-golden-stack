{{- define "be-service.labels" -}}
app.kubernetes.io/name: be-service
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
{{- end }}

{{- define "be-service.selector" -}}
app.kubernetes.io/name: be-service
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
