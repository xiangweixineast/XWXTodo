# XWXTodo 手动验收

## 覆盖层

- [x] 桌面可见
- [x] 普通 App 上方可见
- [x] 全屏 App 上方可见
- [x] 切换 Space 后仍在主屏顶部
- [x] 展开弹窗不显示独立刘海屏
- [x] 弹窗可以输入文本
- [x] 不交互时不抢当前 App 焦点

## 结果记录

- macOS 版本：15.2 (24C101)
- 基础覆盖层测试日期：2026-05-07
- 最新 Release 验收日期：2026-05-09
- `panel.level`：`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))`，实测窗口层级 `1000`
- 全屏 App 测试结果：通过。Finder 全屏 Space 中覆盖层仍 `onscreen=1`，收起态位于 `X=820, Y=0, Width=280, Height=34`，展开态位于 `X=730, Y=0, Width=460, Height=360`。
- 层级选择说明：当前选择 `screenSaverWindow`，因为覆盖层需要贴物理屏幕顶边并覆盖全屏 Space。该层级偏强，风险是覆盖系统或 App 顶部内容；当前通过小尺寸收起态、固定宽高展开态和鼠标离开自动收起来控制遮挡范围。暂不降级到 `.statusBar`、`.popUpMenu` 或 `.modalPanel`。

## 最终验收记录

| 项目 | 结果 | 记录 |
| --- | --- | --- |
| 完整测试 | 通过 | `xcodebuild test -project XWXTodo/XWXTodo.xcodeproj -scheme XWXTodo -destination 'platform=macOS'` 返回 `** TEST SUCCEEDED **`，共 23 个测试、0 个失败。 |
| Debug 构建 | 通过 | `xcodebuild build -project XWXTodo/XWXTodo.xcodeproj -scheme XWXTodo -configuration Debug` 返回 `** BUILD SUCCEEDED **`。 |
| Release 打包 | 通过 | `./scripts/package.sh` 返回 `** BUILD SUCCEEDED **` 并生成 `dist/XWXTodo.zip`；生成时间 `2026-05-09 01:28:13 +0800`，SHA256 `0ad12d38e852bbfa2bf4fc825b8f67883f416715037387a90841912960c72137`；包内包含 `_CodeSignature/CodeResources`，未发现 `._` AppleDouble 条目。 |
| Release 插桩检查 | 通过 | 使用 `strings` 检查 `build/DerivedData/Build/Products/Release/XWXTodo.app/Contents/MacOS/XWXTodo`，未发现 `LLVM_PROFILE_FILE`、`default.profraw`、`__llvm_prf` 或 `__LLVM_COV`。 |
| Zip 内容校验 | 通过 | `unzip -t dist/XWXTodo.zip` 无错误；`codesign --verify --deep --strict build/DerivedData/Build/Products/Release/XWXTodo.app` 通过。 |
| 通用架构 | 通过 | Release 可执行文件为 `x86_64` 和 `arm64` 双架构 Mach-O。 |
| 顶部覆盖层 | 通过 | Release app 启动后，系统窗口列表显示 XWXTodo 覆盖层 `layer=1000`、收起态位于 `X=820, Y=0, Width=280, Height=34`。 |
| Release 覆盖层动画 | 通过 | Release app 采样显示：悬停后从 `280x34` 平滑展开到 `460x360`，展开采样到 18 个不同尺寸；鼠标离开后平滑收回到 `280x34`，收回采样到 19 个不同尺寸。 |
| 首次启动创建数据库 | 通过 | 退出 App 并完整备份现有 `/Users/xwx/Library/Application Support/XWXTodo` 后，临时移走该目录并启动 `/tmp/XWXTodo-qa/XWXTodo.app`；执行 `test -f "$HOME/Library/Application Support/XWXTodo/xwxtodo.sqlite"` 后输出 `first_launch_db_exit=0`。验收后已退出 App 并恢复原目录。 |
| 数据库位置 | 通过 | 恢复原目录后，`test -f "$HOME/Library/Application Support/XWXTodo/xwxtodo.sqlite"` 返回 `0`，数据库位于 `/Users/xwx/Library/Application Support/XWXTodo/xwxtodo.sqlite`。 |
| 数据库失败 fallback 刘海屏 | 通过 | 退出 App 并完整备份现有 `/Users/xwx/Library/Application Support/XWXTodo` 后，用同名文件阻塞数据库目录创建并启动 `/tmp/XWXTodo-release-check/XWXTodo.app`；App 仍启动，系统窗口列表显示 fallback 刘海屏覆盖层 `layer=1000`、`onscreen=1`、`X=820, Y=0, Width=280, Height=34`。验收后已退出 App 并恢复原目录。 |
| 无业务联网代码 | 通过 | `rg -n "URLSession|NWConnection|Network|http://|https://" XWXTodo/XWXTodo || true` 仅匹配 `XWXTodo.entitlements` 的 Apple plist DTD `http://www.apple.com/DTDs/PropertyList-1.0.dtd`，未发现业务联网 API 或网络 URL。 |
| 分发限制 | 已记录 | `XWXTodo.zip` 使用 ad-hoc 签名且未 notarize；发给其他 Mac 时可能被 Gatekeeper 阻止，需要用户手动允许或后续补 notarization 流程。 |

## 记录明细

| 项目 | 结果 | 记录 |
| --- | --- | --- |
| 桌面可见 | 通过 | Debug app 启动后，系统窗口列表显示 XWXTodo 覆盖层 `layer=1000`、`onscreen=1`、`X=820, Y=0, Width=280, Height=34`。 |
| 普通 App 上方可见 | 通过 | 激活 Finder 后，覆盖层仍 `onscreen=1` 且保持主屏顶部居中；前台 App 仍为 Finder。 |
| 全屏 App 上方可见 | 通过 | Finder 进入全屏后，覆盖层仍 `onscreen=1`；悬停可展开，鼠标离开后恢复为收起态。 |
| Space 切换 | 通过 | 使用 `Control-Left` 从全屏 Space 切换后，覆盖层仍 `onscreen=1` 且保持 `X=820, Y=0, Width=280, Height=34`。 |
| 展开弹窗替代刘海屏 | 通过 | 鼠标移动到顶部热区后，唯一的 XWXTodo 覆盖层窗口变为 `X=730, Y=0, Width=460, Height=360`；未同时出现独立 `280x34` 刘海屏窗口。 |
| 弹窗文本输入 | 通过 | 本轮通过 Computer Use 对运行中的 Debug app 直接验证：展开弹窗后焦点元素为 `text field (settable, string)`，输入 `QA input focus` 后控件值变为该字符串；随后选中并清空，未点击 Add。 |
| 焦点行为 | 通过 | 悬停展开后，`System Events` 仍报告前台 App 为 Finder；不交互时覆盖层没有抢当前 App 焦点。 |
