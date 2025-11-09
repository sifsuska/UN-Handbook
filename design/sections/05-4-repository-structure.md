### Repository Structure

#### Complete Repository Layout

```
UN-Handbook/
├── _extensions/
│   └── reproducible-button/       # Quarto extension
│       ├── _extension.yml
│       └── reproduce-button.lua   # Deep-link generator
│
├── handbook-catalog/               # Onyxia Helm catalog
│   ├── chapter-session/
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   ├── values.schema.json
│   │   └── templates/
│   │       ├── serviceaccount.yaml  # For IRSA
│   │       ├── deployment.yaml
│   │       ├── service.yaml
│   │       └── ingress.yaml
│   ├── index.yaml                 # Helm repo index
│   └── chapter-session-1.0.0.tgz
│
├── ci/                            # NEW: Portable Dagger pipeline logic
│   ├── __init__.py
│   └── pipeline.py                # Dagger SDK script (Components #2, #3, #5)
│
├── .docker/
│   ├── base.Dockerfile            # R + renv + GDAL
│   ├── gpu.Dockerfile             # CUDA + torch
│   └── .dockerignore
│
├── .github/
│   └── workflows/
│       ├── build-images.yml       # SIMPLIFIED: One-line 'dagger run' wrapper
│       ├── package-data.yml       # SIMPLIFIED: One-line 'dagger run' wrapper
│       └── generate-metadata.yml  # SIMPLIFIED: One-line 'dagger run' wrapper
│
├── scripts/
│   └── scan-all-chapters.R        # Metadata extraction (executed by Dagger)
│
├── requirements.txt               # Python deps (Indonesia chapter)
│
├── renv.lock                      # R package lockfile
├── .Rprofile                      # renv configuration
├── renv/
│   ├── activate.R
│   └── settings.json
│
├── data/
│   ├── ct_chile/                  # Chapter-specific data
│   │   ├── sentinel_time_series.tif
│   │   └── training_samples.gpkg
│   ├── cy_colombia/
│   └── ...
│
└── chapters/
    ├── ct_chile.qmd               # With reproducible: { data-snapshot: sha256-... }
    ├── cy_colombia.qmd
    └── ...
```

#### Key Directory Purposes

**Build-Time Components**:

- `ci/pipeline.py` - Portable Dagger pipeline (Section 5.1)
- `.docker/` - Compute image Dockerfiles (Section 5.2)
- `.github/workflows/` - Platform-specific CI wrappers
- `scripts/` - Metadata generation scripts

**Run-Time Components**:

- `_extensions/reproducible-button/` - Quarto extension for "Reproduce" buttons (Section 6.1)
- `handbook-catalog/` - Onyxia Helm chart (Section 6.4)

**Content**:

- `chapters/*.qmd` - Chapter source files with reproducible metadata
- `data/*/` - Chapter-specific datasets (packaged as OCI artifacts)

**Dependency Management**:

- `renv.lock` - Shared R package lockfile
- `requirements.txt` - Python dependencies for specific chapters
- `.Rprofile` + `renv/` - renv infrastructure

#### CI Workflow Examples

**Build Images** (`.github/workflows/build-images.yml`):

```yaml
name: Build Compute Images
on:
  push:
    paths:
      - '.docker/**'
      - 'renv.lock'
      - 'requirements.txt'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dagger/setup-dagger@v1
      - name: Build Base Image
        run: |
          dagger run python ./ci/pipeline.py build-image \
            --dockerfile .docker/base.Dockerfile \
            --tag ghcr.io/fao-eostat/handbook-base:v1.0
        env:
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Package Data** (`.github/workflows/package-data.yml`):

```yaml
name: Package Data Artifacts
on:
  push:
    paths:
      - 'data/**'

jobs:
  package:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 2  # Need previous commit for diff
      - uses: dagger/setup-dagger@v1
      - name: Build and Push Data
        run: |
          dagger run python ./ci/pipeline.py package-data \
            --registry-prefix ghcr.io/fao-eostat/handbook-data
        env:
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_COMMIT_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_REPO_URL: github.com/fao-eostat/un-handbook
```

**Generate Metadata** (`.github/workflows/generate-metadata.yml`):

```yaml
name: Generate Chapter Metadata
on:
  push:
    paths:
      - 'chapters/*.qmd'

jobs:
  metadata:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dagger/setup-dagger@v1
      - name: Scan Chapters
        run: dagger run python ./ci/pipeline.py generate-metadata
        env:
          GIT_COMMIT_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_REPO_URL: github.com/fao-eostat/un-handbook
```

#### Portability Note

All CI workflows are simple wrappers around the Dagger pipeline. The same `ci/pipeline.py` script runs identically on:

- Local developer machine: `dagger run python ./ci/pipeline.py package-data ...`
- GitHub Actions: (see above)
- GitLab CI: Similar YAML with GitLab-specific env vars
- Any platform with Docker and the Dagger CLI
