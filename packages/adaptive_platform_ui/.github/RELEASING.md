# Release Process

This document describes how to create a new release of Adaptive Platform UI.

## Prerequisites

- Write access to the repository
- All changes merged to `main` branch
- All tests passing on CI
- CHANGELOG.md updated with release notes

## Release Steps

### 1. Update Version Numbers

Update the version in `pubspec.yaml`:

```yaml
version: 0.1.95  # Increment according to semver
```

### 2. Update CHANGELOG.md

Add a new section at the top of CHANGELOG.md:

```markdown
## [0.1.95]
* **NEW**: Description of new features
* **FIX**: Description of bug fixes
* **IMPROVEMENT**: Description of improvements
```

**Important**: The version number in brackets `[0.1.95]` must match the tag you'll create.

### 3. Commit Changes

```bash
git add pubspec.yaml CHANGELOG.md
git commit -m "chore: Release v0.1.95"
git push origin main
```

### 4. Create and Push Tag

```bash
# Create annotated tag
git tag -a v0.1.95 -m "Release v0.1.95"

# Push tag to GitHub
git push origin v0.1.95
```

### 5. Automated Release

Once the tag is pushed, GitHub Actions will automatically:

1. ✅ Build the example app APK
2. ✅ Extract release notes from CHANGELOG.md
3. ✅ Create a GitHub Release
4. ✅ Upload the APK to the release

You can monitor the progress in the **Actions** tab on GitHub.

### 6. Verify Release

After the workflow completes (usually 5-10 minutes):

1. Go to the [Releases page](https://github.com/berkaycatak/adaptive_platform_ui/releases)
2. Verify the new release is published
3. Download and test the APK
4. Check that release notes are correct

## Release Naming Convention

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR** version (1.0.0): Breaking changes
- **MINOR** version (0.2.0): New features, backward compatible
- **PATCH** version (0.1.1): Bug fixes, backward compatible

Examples:
- `0.1.95` → `0.1.96` (bug fix)
- `0.1.95` → `0.2.0` (new features)
- `0.1.95` → `1.0.0` (breaking changes)

## Tag Naming Convention

Always prefix with `v`:
- ✅ `v0.1.95`
- ✅ `v1.0.0`
- ❌ `0.1.95`
- ❌ `1.0.0`

## Hotfix Releases

For urgent bug fixes:

```bash
# Create hotfix branch from main
git checkout -b hotfix/0.1.96 main

# Make fixes and commit
git add .
git commit -m "fix: Critical bug fix"

# Merge back to main
git checkout main
git merge hotfix/0.1.96

# Update version and changelog
# ... (follow steps 1-4)

# Delete hotfix branch
git branch -d hotfix/0.1.96
```

## Pre-release / Beta Releases

For testing releases before stable:

```bash
# Use pre-release suffix
git tag -a v0.2.0-beta.1 -m "Beta release v0.2.0-beta.1"
git push origin v0.2.0-beta.1
```

The release will be marked as "Pre-release" on GitHub.

## Rollback a Release

If a release has critical issues:

### Option 1: Delete Release and Tag

```bash
# Delete the tag locally
git tag -d v0.1.95

# Delete the tag on GitHub
git push origin :refs/tags/v0.1.95
```

Then manually delete the Release on GitHub.

### Option 2: Create Hotfix Release

Create a new patch version with the fix:

```bash
# Fix the issue
git commit -m "fix: Critical issue from v0.1.95"

# Create new patch release
git tag -a v0.1.96 -m "Hotfix release v0.1.96"
git push origin v0.1.96
```

## Troubleshooting

### Release workflow failed

1. Check the Actions tab for error logs
2. Common issues:
   - CHANGELOG.md format incorrect
   - Build errors in example app
   - GitHub token permissions

### Release created but APK missing

1. Check workflow logs for build failures
2. Verify example app builds locally:
   ```bash
   cd example
   flutter build apk --release
   ```

### Release notes not showing correctly

1. Verify CHANGELOG.md format:
   ```markdown
   ## [0.1.95]
   * Changes here

   ## [0.1.94]
   * Previous changes
   ```
2. Ensure version in brackets matches tag

### Cannot push tag

```bash
# Fetch latest tags
git fetch --tags

# Check if tag already exists
git tag -l | grep v0.1.95

# If exists, delete and recreate
git tag -d v0.1.95
git tag -a v0.1.95 -m "Release v0.1.95"
git push origin v0.1.95 --force
```

## Publishing to pub.dev

After verifying the release on GitHub:

```bash
# Dry run first
flutter pub publish --dry-run

# Publish to pub.dev
flutter pub publish
```

Follow the prompts to complete the publishing process.

## Checklist

Before creating a release:

- [ ] All PRs merged to main
- [ ] CI passing on main branch
- [ ] Version updated in pubspec.yaml
- [ ] CHANGELOG.md updated with release notes
- [ ] Commits pushed to main
- [ ] Tag created and pushed
- [ ] Release verified on GitHub
- [ ] APK tested
- [ ] Package published to pub.dev (if applicable)

## Questions?

If you have questions about the release process, please:
- Open a [Discussion](https://github.com/berkaycatak/adaptive_platform_ui/discussions)
- Contact the maintainers
