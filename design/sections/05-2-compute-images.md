##### Component #2: Curated Compute Images

**Pre-built System Dependency Images**

###### The System Dependency Challenge

**Problem**: System libraries (GDAL, PROJ, GEOS) cannot be managed by `renv`. Allowing runtime `apt-get install`:

- Requires `root` access (security vulnerability)
- Adds 2-5 minutes to startup time
- Not reproducible (package versions can change)

**Solution**: Pre-built, immutable Docker images maintained by infrastructure team.

###### Image Catalog

| Image Flavor | Repository | Parent Base | System Packages | Use Case |
|--------------|------------|-------------|-----------------|----------|
| `base` | `ghcr.io/fao-eostat/handbook-base:v1.0` | jupyter/r-notebook:r-4.5.1 | GDAL 3.6.2, PROJ 9.1.1, GEOS 3.11.1 | 95% of chapters |
| `gpu` | `ghcr.io/fao-eostat/handbook-base-gpu:v1.0` | nvidia/cuda:12.1-cudnn8 | Same as base + CUDA, cuDNN | Deep learning (Colombia) |

###### Helm Chart Implementation

The Helm chart uses a server-side dictionary to map semantic flavor names to actual image repositories:

**File**: `handbook-catalog/chapter-session/templates/deployment.yaml`

```yaml
{{- $imageFlavors := dict
      "base" (dict "repo" "ghcr.io/fao-eostat/handbook-base"     "tag" "v1.0")
      "gpu"  (dict "repo" "ghcr.io/fao-eostat/handbook-base-gpu" "tag" "v1.0")
    -}}
{{- $imageFlavor := .Values.imageFlavor | default "base" -}}
{{- $imageConfig := index $imageFlavors $imageFlavor -}}
```

###### Author Experience

Authors specify the semantic flavor name in chapter frontmatter - no need to know registry paths or image tags:

```yaml
reproducible:
  enabled: true
  image-flavor: base  # or "gpu"
```

###### Image Implementations

###### Base Image

**Dockerfile** (`.docker/base.Dockerfile`):

```dockerfile
FROM jupyter/r-notebook:r-4.5.1

USER root

# Install system dependencies (fixed versions for reproducibility)
RUN apt-get update && apt-get install -y \
    libgdal-dev=3.6.2+dfsg-1~jammy \
    libproj-dev=9.1.1-1~jammy \
    libgeos-dev=3.11.1-1~jammy \
    libudunits2-dev \
    libnode-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

USER ${NB_UID}

# Copy renv files
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Install R packages from renv.lock
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"
RUN R -e "renv::restore()"

# Install Python dependencies (for Indonesia chapter)
COPY requirements.txt requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Pre-warm key packages (reduce first-run latency)
RUN R -e "library(sits); library(terra); library(sf)"

# Set working directory
WORKDIR /home/jovyan

# Labels
LABEL org.opencontainers.image.version="v1.0" \
      org.opencontainers.image.title="UN Handbook Base Image" \
      org.opencontainers.image.description="R 4.5.1 + geospatial stack"
```

**Python Requirements** (`requirements.txt`):

```
# For Indonesia chapter (reticulate integration)
numpy>=1.24.0
pandas>=2.0.0
geopandas>=0.13.0
rasterio>=1.3.0
```

###### GPU Image

**Dockerfile** (`.docker/gpu.Dockerfile`):

```dockerfile
FROM nvidia/cuda:12.1.0-cudnn8-runtime-ubuntu22.04

USER root

# Install R 4.5.1
RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:c2d4u.team/c2d4u4.0+ \
    && apt-get update && apt-get install -y \
    r-base=4.5.1* \
    r-base-dev=4.5.1* \
    python3 python3-pip \
    libgdal-dev libproj-dev libgeos-dev \
    # ... (same system deps as base)

# Create jovyan user
RUN useradd -m -s /bin/bash -N -u 1000 jovyan
USER jovyan

# Install R packages (same as base)
# ... (copy renv restore steps)

# Install torch with CUDA support
RUN R -e "install.packages('torch', repos='https://cloud.r-project.org')"
RUN R -e "torch::install_torch(type='cuda', version='2.1.0')"

# Verify GPU access
RUN R -e "stopifnot(torch::cuda_is_available())"

WORKDIR /home/jovyan

LABEL org.opencontainers.image.version="v1.0-gpu" \
      handbook.requires-gpu="true"
```

###### Build Process

Images are built by the Dagger pipeline (Component #2):

```bash
# Via Dagger pipeline
dagger run python ./ci/pipeline.py build-image \
  --dockerfile .docker/base.Dockerfile \
  --tag ghcr.io/fao-eostat/handbook-base:v1.0

dagger run python ./ci/pipeline.py build-image \
  --dockerfile .docker/gpu.Dockerfile \
  --tag ghcr.io/fao-eostat/handbook-base-gpu:v1.0
```

See [Portable CI/CD Pipeline](#component-1-portable-cicd-pipeline-dagger-sdk) for complete Dagger implementation details.

###### Version Management

**Updating Image Versions**:

Infrastructure team updates the Helm chart template's `$imageFlavors` dictionary and deploys new chart version. No changes needed to Quarto site or chapter files.

**Adding New System Dependency** (governed process):

1. Author opens GitHub issue requesting new package
2. Infrastructure team reviews and approves
3. PR updates Dockerfile: `apt-get install libmagick++-dev`
4. CI builds new image: `handbook-base:v1.1`
5. Update Helm chart values or Quarto extension
6. Deploy via new handbook render

###### Security Benefits

- All system packages installed at build time in trusted CI
- No `root` access in user containers
- Immutable, auditable images
- Versioned (can roll back if needed)
