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
- 测试日期：2026-05-07
- `panel.level`：`NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))`，实测窗口层级 `1000`
- 全屏 App 测试结果：通过。Finder 全屏 Space 中覆盖层仍 `onscreen=1`，收起态位于 `X=820, Y=0, Width=280, Height=34`，展开态位于 `X=730, Y=0, Width=460, Height=360`。
- 层级选择说明：当前选择 `screenSaverWindow`，因为覆盖层需要贴物理屏幕顶边并覆盖全屏 Space。该层级偏强，风险是覆盖系统或 App 顶部内容；当前通过小尺寸收起态、固定宽高展开态和鼠标离开自动收起来控制遮挡范围。暂不降级到 `.statusBar`、`.popUpMenu` 或 `.modalPanel`。

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
