# {{package_name}}

{{description}}

Owner: {{owner}}

## Develop

```bash
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
ruff check . && ruff format --check .
mypy src
pytest --cov
```

## Release

CI runs on every pull request and push to `main`. To publish a version:

1. Bump `version` in `pyproject.toml` and merge to `main`.
2. Tag the merge commit with the same version: `git tag v0.2.0 && git push origin v0.2.0`.

The tag triggers a publish to AWS CodeArtifact (if publishing is enabled for this
package). The pipeline logic lives in `oteemoPrudhvi/golden-path-workflows-dev`; this repo only
holds the short caller in `.github/workflows/ci.yml`.

## Install from CodeArtifact

```bash
aws codeartifact login --tool pip --domain <domain> --repository <repository>
pip install {{package_name}}
```
