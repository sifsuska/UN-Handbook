### Component #1: Portable CI/CD Pipeline (Dagger SDK)

**Build-Time Automation for Compute Images, Data Artifacts, and Metadata Generation**

#### The Portability Challenge

**Problem**: The CI/CD logic for building compute images, hashing data, and auto-committing hashes is complex. While it could be implemented using GitHub Actions YAML, that approach is platform-specific and tightly coupled to a single CI system. This creates a significant barrier to adoption for organizations using GitLab, Bitbucket, or other platforms.

**Solution**: Abstract the entire build-time logic (Components #2, #3, and #5) into a portable "Pipeline-as-Code" SDK using the Dagger framework.

This SDK (implemented in `ci/pipeline.py`) uses the Dagger Python SDK to define pipeline functions. The CI platform's YAML file becomes a simple, one-line wrapper that just executes the Dagger pipeline.

#### How It Works: The Transformation

This design turns complex, platform-specific CI configurations into simple, portable declarations.

**After: GitHub Actions (Simple & Portable)**

```yaml
# .github/workflows/package-data.yml
jobs:
  build-data:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dagger/setup-dagger@v1
      - name: Build, Push, and Commit Data
        run: dagger run python ./ci/pipeline.py package-data --registry-prefix "ghcr.io/fao-eostat/handbook-data"
        env:
          REGISTRY_USER: ${{ github.actor }}
          REGISTRY_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_COMMIT_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          GIT_REPO_URL: "github.com/fao-eostat/un-handbook"
```

**After: GitLab CI (Nearly Identical)**

```yaml
# .gitlab-ci.yml
build_data_artifacts:
  image: registry.gitlab.com/dagger-io/dagger/dagger:latest
  script:
    - dagger run python ./ci/pipeline.py package-data --registry-prefix "registry.gitlab.com/my-org/handbook-data"
  variables:
    REGISTRY_USER: $CI_REGISTRY_USER
    REGISTRY_TOKEN: $CI_REGISTRY_PASSWORD
    GIT_COMMIT_TOKEN: $GITLAB_PUSH_TOKEN
    GIT_REPO_URL: "gitlab.com/my-org/un-handbook"
```

#### Dagger SDK Implementation

The core logic moves into a Python script using the Dagger SDK. Dagger runs pipeline steps in isolated containers, providing automatic caching, parallelization, and portability.

**File**: `ci/pipeline.py`

```python
import dagger
import anyio
import sys
import os
import re

# --- CLI Argument Parsing ---
if len(sys.argv) < 2:
    print("Usage: python pipeline.py <command>")
    sys.exit(1)

COMMAND = sys.argv[1]

# --- Helper Functions ---

def get_registry_auth(client: dagger.Client):
    """Configures registry authentication from environment variables."""
    user = os.environ.get("REGISTRY_USER")
    token_secret = client.set_secret(
        "REGISTRY_TOKEN",
        os.environ.get("REGISTRY_TOKEN")
    )
    if not user or not token_secret:
        raise ValueError("REGISTRY_USER and REGISTRY_TOKEN must be set")
    return user, token_secret

def get_git_commit_token(client: dagger.Client):
    """Gets the Git token for committing back to the repo."""
    token = os.environ.get("GIT_COMMIT_TOKEN")
    if not token:
        raise ValueError("GIT_COMMIT_TOKEN must be set for auto-commit")
    return client.set_secret("GIT_COMMIT_TOKEN", token)

def get_git_repo_url():
    """Gets the Git repo URL from an env var."""
    url = os.environ.get("GIT_REPO_URL")
    if not url:
        raise ValueError("GIT_REPO_URL env var must be set (e.g., github.com/fao-eostat/un-handbook)")
    return url

def get_git_commit_base(client: dagger.Client, base_image: str = "alpine/git:latest"):
    """
    Creates a base container pre-configured with Git
    and credentials, ready to clone and commit.
    """
    git_token = get_git_commit_token(client)
    git_repo_url = get_git_repo_url()

    auth_url = f"https://oauth2:{git_token}@{git_repo_url}"

    container = (
        client.container()
        .from_(base_image)
        .with_secret_variable("GIT_TOKEN", git_token)
        # Configure Git
        .with_exec(["git", "config", "--global", "user.name", "github-actions[bot]"])
        .with_exec(["git", "config", "--global", "user.email", "github-actions[bot]@users.noreply.github.com"])
        # Clone repo using token
        .with_exec(["git", "clone", auth_url, "/repo"])
        .with_workdir("/repo")
    )
    return container

# --- Dagger Pipeline Functions ---

async def build_compute_image(client: dagger.Client, dockerfile: str, tag: str):
    """
    (Component #2) Builds and publishes a curated compute image.
    e.g., python pipeline.py build-image --dockerfile .docker/base.Dockerfile --tag ghcr.io/fao-eostat/handbook-base:v1.0
    """
    print(f"Building compute image for {dockerfile}...")
    user, token = get_registry_auth(client)

    # Get source context
    src = client.host().directory(".")

    # Build and publish
    image_ref = await (
        client.container()
        .build(context=src, dockerfile=dockerfile)
        .with_registry_auth(
            address=tag.split("/")[0],
            username=user,
            secret=token
        )
        .publish(address=tag)
    )
    print(f"Published compute image to: {image_ref}")

async def package_data_artifacts(client: dagger.Client, registry_prefix: str):
    """
    (Component #3) Builds, content-hashes, publishes, and auto-commits
    all changed chapter data artifacts.
    """
    print("Starting data packaging pipeline...")
    user, token = get_registry_auth(client)
    git_token = get_git_commit_token(client)

    # 1. Get repository source and find changed chapters
    src = client.host().directory(".")

    # Use a container with git to find changed data dirs
    # Note: Using HEAD~1 HEAD works for single commits.
    # For multi-commit pushes, consider: git diff --name-only origin/main...HEAD
    changed_chapters = await (
        client.container()
        .from_("alpine/git:latest")
        .with_mounted_directory("/src", src)
        .with_workdir("/src")
        .with_exec(["sh", "-c", "git diff --name-only HEAD~1 HEAD | grep '^data/' | cut -d/ -f2 | sort -u"])
        .stdout()
    )

    changed_chapters = changed_chapters.strip().split("\n")
    if not changed_chapters or (len(changed_chapters) == 1 and changed_chapters[0] == ''):
        print("No chapter data changes detected. Exiting.")
        return

    print(f"Detected changes in: {', '.join(changed_chapters)}")

    # 2. Build, Hash, and Push artifacts
    updated_files = {} # dict to store { "ct_chile.qmd": "sha256-abcdef..." }

    for chapter in changed_chapters:
        chapter_data_dir = f"data/{chapter}"
        print(f"Processing data for: {chapter}")

        # Build 'scratch' artifact
        artifact = (
            client.container()
            .from_("scratch")
            .with_directory(f"/data/{chapter}", src.directory(chapter_data_dir))
        )

        # Get Dagger's automatic content-based digest (the hash)
        digest = await artifact.digest() # e.g., "sha256:abc..."
        hash_suffix = f"sha256-{digest.split(':')[-1][:12]}" # "sha256-abcdef123"

        # Push the artifact
        image_tag = f"{registry_prefix}:{chapter}-{hash_suffix}"
        image_ref = await (
            artifact
            .with_registry_auth(
                address=registry_prefix,
                username=user,
                secret=token
            )
            .publish(address=image_tag)
        )
        print(f"Pushed data artifact: {image_ref}")

        # Store for commit
        updated_files[f"{chapter}.qmd"] = hash_suffix

    # 3. Auto-commit hashes back to repo
    # Get the base git container
    commit_container = get_git_commit_base(client)

    # Add python dependencies
    commit_container = (
        commit_container
        .with_exec(["apk", "add", "py3-pip", "python3"])
        .with_exec(["pip", "install", "pyyaml"])
    )

    # Python script to update YAML (more robust than 'yq' or 'sed')
    py_script = """
import yaml, sys, os
file_path = sys.argv[1]
new_hash = sys.argv[2]
if not os.path.exists(file_path):
    print(f"Warning: {file_path} not found, skipping.")
    sys.exit(0)
with open(file_path, 'r') as f:
    content = f.read()
parts = content.split('---')
if len(parts) < 3:
    print(f"No YAML frontmatter in {file_path}")
    sys.exit(1)
data = yaml.safe_load(parts[1])
if 'reproducible' not in data:
    data['reproducible'] = {}
data['reproducible']['data-snapshot'] = new_hash
parts[1] = yaml.dump(data)
with open(file_path, 'w') as f:
    f.write('---'.join(parts))
"""

    commit_container = commit_container.with_new_file("/src/update_yaml.py", py_script)

    # Run update for each changed file
    commit_message = "chore: update data snapshots [skip ci]\\n\\n"
    for file_name, hash_value in updated_files.items():
        commit_container = commit_container.with_exec([
            "python", "/src/update_yaml.py", file_name, hash_value
        ])
        commit_container = commit_container.with_exec(["git", "add", file_name])
        commit_message += f"- Updates {file_name} to {hash_value}\\n"

    # Commit and Push
    commit_container = commit_container.with_exec(["git", "commit", "-m", commit_message])
    commit_container = commit_container.with_exec(["git", "push"])

    # Run the final container
    await commit_container.sync()
    print("Successfully committed updated data snapshot hashes.")

async def generate_metadata(client: dagger.Client):
    """
    (Component #5) Scans all .qmd files and commits an updated chapters.json.
    """
    print("Starting metadata generation pipeline...")

    # 1. Get the base git container, using an R-based image
    commit_container = get_git_commit_base(client, base_image="r-base:4.5.1")

    # 2. Add R dependencies
    commit_container = (
        commit_container
        .with_exec(["apt-get", "update"])
        .with_exec(["apt-get", "install", "-y", "libgit2-dev"]) # for R 'git2r' if needed
        # Install R packages
        .with_exec(["Rscript", "-e", "install.packages(c('yaml', 'jsonlite', 'purrr'), repos='https://cloud.r-project.org')"])
    )

    # 3. Run the R script, commit, and push
    final_container = (
        commit_container
        # Run the R script from the repo and redirect output
        # Assumes scan-all-chapters.R is in a 'scripts' dir
        .with_exec(["Rscript", "scripts/scan-all-chapters.R"], redirect_stdout="chapters.json")
        # Commit the result
        .with_exec(["git", "add", "chapters.json"])
        .with_exec(["git", "commit", "-m", "chore: update chapter metadata [skip ci]"])
        .with_exec(["git", "push"])
    )

    # Run the final container
    await final_container.sync()
    print("Successfully generated and committed chapters.json.")

# --- Main Execution ---

async def run_pipeline():
    async with dagger.Connection() as client:
        if COMMAND == "build-image":
            dockerfile = sys.argv[2].split("=")[1]
            tag = sys.argv[3].split("=")[1]
            await build_compute_image(client, dockerfile, tag)

        elif COMMAND == "package-data":
            registry_prefix = sys.argv[2].split("=")[1]
            await package_data_artifacts(client, registry_prefix)

        elif COMMAND == "generate-metadata":
            await generate_metadata(client)

        else:
            print(f"Unknown command: {COMMAND}")
            sys.exit(1)

if __name__ == "__main__":
    anyio.run(run_pipeline)
```

#### R Script for Metadata Scanning

This script is executed by the Dagger `generate_metadata()` pipeline function (Component #5) to scan all chapter `.qmd` files and extract reproducible metadata.

**File**: `scripts/scan-all-chapters.R`

```r
#!/usr/bin/env Rscript
library(yaml)
library(jsonlite)
library(purrr)

# Find all .qmd files
qmd_files <- list.files(
  path = ".",
  pattern = "\\.qmd$",
  recursive = TRUE,
  full.names = TRUE
)

# Function to extract reproducible metadata
extract_metadata <- function(file) {
  tryCatch({
    lines <- readLines(file, warn = FALSE)

    # Find YAML frontmatter
    yaml_start <- which(lines == "---")[1]
    yaml_end <- which(lines == "---")[2]

    if (is.na(yaml_start) || is.na(yaml_end)) {
      return(NULL)
    }

    yaml_text <- paste(lines[(yaml_start+1):(yaml_end-1)], collapse = "\n")
    metadata <- yaml.load(yaml_text)

    # Check if reproducible metadata exists
    if (is.null(metadata$reproducible) || !isTRUE(metadata$reproducible$enabled)) {
      return(NULL)
    }

    # Extract chapter name
    chapter_name <- tools::file_path_sans_ext(basename(file))

    # Build metadata object
    list(
      tier = metadata$reproducible$tier %||% "medium",
      image_flavor = metadata$reproducible$`image-flavor` %||% "base",
      version = metadata$reproducible$`data-snapshot` %||% "v1.0.0",
      oci_image = sprintf(
        "ghcr.io/fao-eostat/handbook-data:%s-%s",
        chapter_name,
        metadata$reproducible$`data-snapshot` %||% "v1.0.0"
      ),
      estimated_runtime = metadata$reproducible$`estimated-runtime` %||% "Unknown",
      storage_size = metadata$reproducible$`storage-size` %||% "20Gi"
    )
  }, error = function(e) {
    warning(sprintf("Error parsing %s: %s", file, e$message))
    return(NULL)
  })
}

# Scan all chapters
chapters <- qmd_files %>%
  set_names(tools::file_path_sans_ext(basename(.))) %>%
  map(extract_metadata) %>%
  compact()  # Remove NULLs

# Output as JSON
cat(toJSON(chapters, pretty = TRUE, auto_unbox = TRUE))
```

#### Key Benefits

1. **Extreme Portability**: The logic runs identically on GitHub-hosted runners, GitLab instances, or a developer's laptop. The only requirement is the Dagger engine.

2. **Local Testing**: Developers can run the exact production CI pipeline on their local machine by executing `dagger run python ./ci/pipeline.py package-data ...`. This is impossible with traditional CI.

3. **Automatic Caching**: Dagger automatically caches every step of the pipeline. If the `data/ct_chile` directory hasn't changed, `artifact.digest()` will be instant, and the build will be skipped.

4. **Simplified CI**: The CI YAML files are reduced to simple, declarative "runners," making them easy to read and manage. All complex logic is in a single, version-controlled, and testable Python script.

5. **Robust Hashing**: We no longer rely on `find | sha256sum` shell scripting. Dagger's `artifact.digest()` calculates a reproducible, content-addressed digest of the OCI artifact layer, which is a more robust and correct form of content-hashing.

6. **Zero-Friction Author Workflow**: Authors simply commit data files to the repository. The Dagger pipeline automatically handles all five steps: detecting changes, calculating content hash, building OCI artifacts, pushing to registry, and auto-committing hashes back to chapter frontmatter.

**Result**: True immutability. The chapter always references an exact, content-addressed data snapshot, and the entire build pipeline is portable across any CI platform.
