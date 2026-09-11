# AI 监视器 / AI Monitor

## 开发运行

安装 Xcode 和 XcodeGen 后，在项目根目录执行：

```bash
./scripts/run-dev.sh
```

脚本会重新生成 Xcode 工程、增量构建 Debug 版本、退出旧进程并直接启动最新构建，
无需反复生成 DMG 或覆盖 `/Applications/AI Monitor.app`。也可以在 Xcode 中选择
`CodexLinxDisplay` Scheme 后直接按 `Command-R`。

## 版本管理

应用版本统一保存在 `Config/Version.xcconfig`，不要直接修改生成后的
`Resources/Info.plist` 或 `.xcodeproj`。常用命令：

```bash
./scripts/version.sh current       # 查看版本和构建号
./scripts/version.sh bump patch    # 0.4.1 -> 0.4.2，同时递增构建号
./scripts/version.sh bump minor    # 0.4.1 -> 0.5.0，同时递增构建号
./scripts/version.sh set 1.0.0 10  # 明确设置版本与构建号
```

推送 `v*` 标签时，发布工作流会先确认标签与应用版本一致，再生成安装包。例如：

```bash
./scripts/version.sh set 0.4.2
git add Config/Version.xcconfig
git commit -m "chore: release 0.4.2"
git tag v0.4.2
git push origin main v0.4.2
```

标签推送后，GitHub Actions 会构建 ZIP/DMG、使用 Sparkle 私钥签名 ZIP、生成
`appcast.xml` 并一起发布到 GitHub Releases。已安装带更新模块的版本可从菜单栏或
“设置 → 通用 → 版本更新”点击“检查更新”，随后在应用内完成替换；应用也会每天
自动检查一次。

当前仓库的 Sparkle 私钥保存在 GitHub Actions 的 `SPARKLE_PRIVATE_KEY` Secret，
对应公钥保存在 `Config/Version.xcconfig`。不要重新生成或替换这对密钥，否则旧版本
将无法验证新更新。配置 `ENABLE_SIGNED_RELEASES=true`，并设置工作流所需的 Developer
ID 与 Apple 公证 Secrets 后，流水线会额外执行签名与公证；未配置时仍会发布 adhoc
预览包。

> 注意：不包含更新模块的旧安装包无法自行获得该能力，需要安装一次 0.4.1 或更高
> 版本作为更新基线。此后无需再次手动下载安装包。

## 鸣谢
[CodexLinxDisplay](https://github.com/kkoscielniak/CodexLinxDisplay) — 初始代码来源
