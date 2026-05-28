# 发布流程

CN PAC Menubar 通过版本标签发布。推送 `v*` 标签后，GitHub Actions 会构建 macOS 应用、压缩 `.app`，并把 zip 附加到 GitHub Release。

## 发布前准备

1. 更新 `VERSION`。
2. 准备 GitHub Release 说明。
3. 运行检查：

```sh
swift test
Scripts/package-app.sh
```

4. 确认打包后的应用存在于 `.build/CNPacMenubar.app`。

## 发布

```sh
VERSION="$(cat VERSION)"
git add README.md README.zh-CN.md docs/RELEASE.md docs/RELEASE.zh-CN.md VERSION Scripts/package-app.sh .github/workflows/release.yml
git commit -m "Prepare release v${VERSION}"
git tag "v${VERSION}"
git push origin main
git push origin "v${VERSION}"
```

推送标签会触发 `.github/workflows/release.yml`，自动创建以标签命名的 GitHub Release，并上传：

```text
CNPacMenubar-vVERSION-macos.zip
```

## 手动兜底

如果 GitHub Actions 暂时不可用，可以在本地生成相同的发布包：

```sh
VERSION="$(cat VERSION)"
APP_VERSION="$VERSION" APP_BUILD_NUMBER=1 Scripts/package-app.sh
ditto --norsrc --noextattr -c -k --keepParent .build/CNPacMenubar.app ".build/CNPacMenubar-v${VERSION}-macos.zip"
gh release create "v${VERSION}" ".build/CNPacMenubar-v${VERSION}-macos.zip" --title "CN PAC Menubar v${VERSION}" --notes "Initial release."
```
