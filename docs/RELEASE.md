# Release Process

CN PAC Menubar releases are cut from version tags. The GitHub workflow builds the macOS app, zips it, and attaches the zip to the GitHub Release.

## Prepare

1. Update `VERSION`.
2. Update release notes in the GitHub release body, or prepare notes locally.
3. Run checks:

```sh
swift test
Scripts/package-app.sh
```

4. Confirm the packaged app exists at `.build/CNPacMenubar.app`.

## Publish

```sh
VERSION="$(cat VERSION)"
git add README.md README.zh-CN.md docs/RELEASE.md docs/RELEASE.zh-CN.md VERSION Scripts/package-app.sh .github/workflows/release.yml
git commit -m "Prepare release v${VERSION}"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"
```

Pushing the tag starts `.github/workflows/release.yml`. The workflow creates a GitHub Release named after the tag and uploads:

```text
CNPacMenubar-vVERSION-macos.zip
```

## Manual Fallback

If the workflow is unavailable, create the same package locally:

```sh
VERSION="$(cat VERSION)"
APP_VERSION="$VERSION" APP_BUILD_NUMBER=1 Scripts/package-app.sh
ditto --norsrc --noextattr -c -k --keepParent .build/CNPacMenubar.app ".build/CNPacMenubar-v${VERSION}-macos.zip"
gh release create "v${VERSION}" ".build/CNPacMenubar-v${VERSION}-macos.zip" --title "CN PAC Menubar v${VERSION}" --notes "Initial release."
```
