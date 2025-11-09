### Component #5: "Chapter Session" Helm Chart

**Component #5: Kubernetes Session Orchestration**

#### Overview

The "Chapter Session" Helm chart deploys reproducible analysis environments in Kubernetes. It translates semantic configuration (tier names, image flavors) into actual infrastructure resources, mounts data artifacts, and configures cloud credentials.

#### Chart Structure

```
handbook-catalog/
├── chapter-session/
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values.schema.json
│   └── templates/
│       ├── serviceaccount.yaml  # ← For IRSA
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
```

#### Resource Tier Mapping

Resource tiers are defined in the Helm chart templates, not in the Quarto site or author frontmatter. This ensures infrastructure changes don't require updates to the static handbook site.

**Available Tiers** (GPU tier subject to funding; see [GPU Support Availability](#gpu-support-availability)):

- **`light`**: 2 CPU, 8GB RAM, 10GB storage - Theory chapters, small demonstrations
- **`medium`**: 6 CPU, 24GB RAM, 20GB storage - Crop type mapping, Random Forest training, most case studies
- **`heavy`**: 10 CPU, 48GB RAM, 50GB storage - Large-scale classification, SAR preprocessing
- **`gpu`**: 8 CPU, 32GB RAM, 1 GPU, 50GB storage - Deep learning (Colombia chapter), torch/luz models

**Author Experience** (chapter frontmatter):

Authors only specify semantic tier names:

```yaml
reproducible:
  enabled: true
  tier: heavy        # Just the name
  image-flavor: gpu  # Just the flavor
```

The Helm chart translates these to actual resource allocations.

#### Chart Metadata

**File**: `Chart.yaml`

```yaml
apiVersion: v2
name: chapter-session
version: 1.0.0
description: UN Handbook reproducible analysis session
type: application
keywords:
  - jupyter
  - r
  - reproducibility
  - geospatial
home: https://fao-eostat.github.io/UN-Handbook/
sources:
  - https://github.com/FAO-EOSTAT/UN-Handbook
maintainers:
  - name: UN Handbook Team
    email: un-handbook@example.org
icon: https://jupyter.org/assets/homepage/main-logo.svg
```

#### Default Values

**File**: `values.yaml`

```yaml
# Semantic tier selection (passed from Quarto button)
tier: "medium"
imageFlavor: "base"

# Chapter information (passed via Onyxia deep-link)
chapter:
  name: "ct_chile"
  version: "v1.0.0"
  storageSize: "20Gi"

# Legacy/override: Direct resource specification (optional)
# If empty, resources are derived from tier in deployment template
resources:
  requests:
    cpu: ""
    memory: ""
  limits:
    cpu: ""
    memory: ""

# ServiceAccount for IRSA (Workload Identity)
serviceAccount:
  create: true
  annotations: {}
  # Populated by Onyxia region.customValues:
  # annotations:
  #   eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/handbook-reader

# AWS configuration
aws:
  region: "us-west-2"
  # No credentials - IRSA provides them automatically

# Service configuration
service:
  type: ClusterIP
  port: 8888
  targetPort: 8888

# Ingress (Onyxia auto-configures subdomain)
ingress:
  enabled: true
  className: "{{onyxia.k8s.ingressClassName}}"
  hostname: "chapter-{{onyxia.k8s.randomSubdomain}}.{{onyxia.k8s.domain}}"
  tls: true

# Security (chart-specific implementation of region defaults)
security:
  ipProtection:
    enabled: "{{onyxia.region.defaultIpProtection}}"
    ip: "{{onyxia.user.ip}}"
  networkPolicy:
    enabled: "{{onyxia.region.defaultNetworkPolicy}}"

# Ephemeral session (no home persistence)
persistence:
  enabled: false

# Onyxia context (injected at deploy time)
onyxia:
  s3:
    AWS_BUCKET_NAME: ""
    AWS_S3_ENDPOINT: ""
    # Fallback credentials (only if IRSA not available)
    AWS_ACCESS_KEY_ID: ""
    AWS_SECRET_ACCESS_KEY: ""
    AWS_SESSION_TOKEN: ""
```

#### Template: ServiceAccount (IRSA)

**File**: `templates/serviceaccount.yaml`

```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "chapter-session.serviceAccountName" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "chapter-session.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

The `serviceAccount.annotations` field is populated by Onyxia's `region.customValues` with the IRSA role ARN (see Section 6.3.1).

#### Template: Deployment

**File**: `templates/deployment.yaml`

```yaml
{{- /* Define resource tier mappings (SSOT for infrastructure) */}}
{{- $resourceTiers := dict
      "light"  (dict "cpu" "2000m"  "memory" "8Gi"   "storage" "10Gi")
      "medium" (dict "cpu" "6000m"  "memory" "24Gi"  "storage" "20Gi")
      "heavy"  (dict "cpu" "10000m" "memory" "48Gi"  "storage" "50Gi")
      "gpu"    (dict "cpu" "8000m"  "memory" "32Gi"  "storage" "50Gi")
    -}}
{{- $tier := .Values.tier | default "medium" -}}
{{- $tierConfig := index $resourceTiers $tier -}}

{{- /* Define image flavor mappings (SSOT for images) */}}
{{- $imageFlavors := dict
      "base" (dict "repo" "ghcr.io/fao-eostat/handbook-base"     "tag" "v1.0")
      "gpu"  (dict "repo" "ghcr.io/fao-eostat/handbook-base-gpu" "tag" "v1.0")
    -}}
{{- $imageFlavor := .Values.imageFlavor | default "base" -}}
{{- $imageConfig := index $imageFlavors $imageFlavor -}}

{{- /* Allow override via explicit resources */}}
{{- $cpu := .Values.resources.limits.cpu | default $tierConfig.cpu -}}
{{- $memory := .Values.resources.limits.memory | default $tierConfig.memory -}}
{{- $storage := .Values.chapter.storageSize | default $tierConfig.storage -}}

apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "chapter-session.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "chapter-session.selectorLabels" . | nindent 8 }}
        chapter: {{ .Values.chapter.name }}
        tier: {{ $tier }}
    spec:
      serviceAccountName: {{ include "chapter-session.serviceAccountName" . }}
      securityContext:
        runAsUser: 1000
        runAsGroup: 100
        fsGroup: 100
      containers:
      - name: jupyterlab
        image: "{{ $imageConfig.repo }}:{{ $imageConfig.tag }}"
        imagePullPolicy: IfNotPresent
        command:
          - jupyter
          - lab
          - --ip=0.0.0.0
          - --port=8888
          - --no-browser
          - --NotebookApp.token=''
          - --NotebookApp.password=''
        ports:
        - name: http
          containerPort: 8888
          protocol: TCP
        env:
        - name: CHAPTER_NAME
          value: {{ .Values.chapter.name }}
        - name: CHAPTER_VERSION
          value: {{ .Values.chapter.version }}
        - name: ONYXIA_USER
          value: {{ .Values.onyxia.user.idep | quote }}
        # AWS region (always needed)
        - name: AWS_DEFAULT_REGION
          value: {{ .Values.aws.region | default "us-west-2" | quote }}
        # S3 endpoint and bucket info
        {{- if .Values.onyxia.s3 }}
        - name: AWS_S3_ENDPOINT
          value: {{ .Values.onyxia.s3.AWS_S3_ENDPOINT | default "https://s3.amazonaws.com" | quote }}
        - name: AWS_BUCKET_NAME
          value: {{ .Values.onyxia.s3.AWS_BUCKET_NAME | quote }}
        {{- end }}
        # FALLBACK: xOnyxiaContext credentials (only if IRSA not available)
        # AWS SDK automatically prefers IRSA when ServiceAccount has annotation
        {{- if and .Values.onyxia.s3 .Values.onyxia.s3.AWS_ACCESS_KEY_ID }}
        - name: AWS_ACCESS_KEY_ID
          value: {{ .Values.onyxia.s3.AWS_ACCESS_KEY_ID | quote }}
        - name: AWS_SECRET_ACCESS_KEY
          value: {{ .Values.onyxia.s3.AWS_SECRET_ACCESS_KEY | quote }}
        - name: AWS_SESSION_TOKEN
          value: {{ .Values.onyxia.s3.AWS_SESSION_TOKEN | quote }}
        {{- end }}
        resources:
          requests:
            cpu: {{ $cpu }}
            memory: {{ $memory }}
          limits:
            cpu: {{ $cpu }}
            memory: {{ $memory }}
            {{- if eq $tier "gpu" }}
            nvidia.com/gpu: 1
            {{- end }}
        volumeMounts:
        - name: chapter-data
          mountPath: /home/jovyan/handbook-chapter
          readOnly: true
        - name: dshm
          mountPath: /dev/shm
        livenessProbe:
          httpGet:
            path: /api
            port: http
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /api
            port: http
          initialDelaySeconds: 10
          periodSeconds: 5
      volumes:
      - name: chapter-data
        csi:
          driver: csi-image.k8s.io
          volumeAttributes:
            image: "ghcr.io/fao-eostat/handbook-data:{{ .Values.chapter.name }}-{{ .Values.chapter.version }}"
          readOnly: true
      - name: dshm
        emptyDir:
          medium: Memory
          sizeLimit: 2Gi
      {{- if .Values.gpu.enabled }}
      tolerations:
      - key: nvidia.com/gpu
        operator: Exists
        effect: NoSchedule
      {{- end }}
```

**Key Features**:

1. **Semantic Configuration**: Tier and image flavor dictionaries at top of template
2. **CSI Image Driver**: Data mounted via `csi-image.k8s.io` driver (Section 5.3)
3. **IRSA Support**: ServiceAccount referenced for Workload Identity (Section 6.3.1)
4. **Hybrid Credentials**: IRSA preferred, xOnyxiaContext fallback (Section 6.3.2)
5. **GPU Support**: Conditional resource limits and tolerations for GPU tier

#### Template: Service

**File**: `templates/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
spec:
  type: {{ .Values.service.type }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: http
    protocol: TCP
    name: http
  selector:
    {{- include "chapter-session.selectorLabels" . | nindent 4 }}
```

#### Template: Ingress

**File**: `templates/ingress.yaml`

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "chapter-session.fullname" . }}
  namespace: {{ .Release.Namespace }}
  annotations:
    {{- if .Values.security.ipProtection.enabled }}
    nginx.ingress.kubernetes.io/whitelist-source-range: {{ .Values.security.ipProtection.ip }}
    {{- end }}
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: {{ .Values.ingress.className }}
  tls:
  - hosts:
    - {{ .Values.ingress.hostname }}
    secretName: {{ include "chapter-session.fullname" . }}-tls
  rules:
  - host: {{ .Values.ingress.hostname }}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: {{ include "chapter-session.fullname" . }}
            port:
              number: {{ .Values.service.port }}
{{- end }}
```

**Features**:

- **IP Whitelisting**: Optional IP-based access control via Onyxia user context
- **TLS**: Automatic HTTPS via cert-manager and Let's Encrypt
- **Dynamic Hostname**: Onyxia injects random subdomain for session isolation

#### Packaging for Onyxia Catalog

```bash
# Package the chart
helm package handbook-catalog/chapter-session/

# Generate index
helm repo index handbook-catalog/ --url https://fao-eostat.github.io/handbook-catalog

# Host on GitHub Pages
git add handbook-catalog/index.yaml handbook-catalog/chapter-session-1.0.0.tgz
git commit -m "Add handbook chapter session chart"
git push
```

The packaged chart is then referenced by Onyxia's catalog configuration:

```yaml
# Onyxia platform configuration
catalogs:
  - id: handbook
    name: "UN Handbook Sessions"
    location: https://fao-eostat.github.io/UN-Handbook/handbook-catalog/
    type: helm
```

#### Design Benefits

1. **Single Source of Truth**: All infrastructure configuration (tiers, images) defined in Helm templates
2. **Decoupled Updates**: Infrastructure changes don't require re-rendering Quarto book
3. **Portable**: Standard Helm chart works on any Kubernetes cluster
4. **Onyxia-Compatible**: Uses Onyxia conventions (xOnyxiaContext, deep-links) but not dependent on them
5. **Secure**: IRSA for credentials, IP whitelisting, no hardcoded secrets
