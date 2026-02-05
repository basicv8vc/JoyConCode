# 方案：Joy-Con 自定义映射 + 震动反馈 + Claude Code Hook 震动

## 摘要
使用 Apple GameController 框架为 JoyConCode 增加 Joy-Con 支持，提供独立的“映射弹窗”完成完整按键自定义（支持任意键盘按键与组合键）。Joy-Con 输入受主开关控制，动作触发时提供震动反馈并可调强度。新增 URL Scheme 接口，使 Claude Code 的 `UserPromptSubmit` hook 能触发短促震动提示。

## 公共接口 / 类型变更
- 新增服务：`JoyConManager`（ObservableObject）
- `AppSettings` 新增：
  - `joyConEnabled: Bool`（默认 `false`）
  - `joyConRumbleEnabled: Bool`（默认 `true`）
  - `joyConRumbleStrength: Double`（默认 `0.6`）
  - `joyConStickMode: JoyConStickMode`（`.dpad` / `.off`）
  - `joyConBindings: [JoyConInput: KeyChord]`（Data 持久化）
- 新增类型：
  - `JoyConInput: String, CaseIterable, Codable`
  - `KeyChord: Codable`（`keyCode: UInt16`, `modifiers: CGEventFlags`）
  - `JoyConStickMode: String, CaseIterable`
- `MenuBarView` / `SettingsView` 接收 `JoyConManager`
- `KeyboardSimulator` 增加 `simulateKey(chord:)`

## URL Scheme 扩展
- 新增：`joyconcode://joycon/rumble`
- 行为：触发一次短促震动
- 受 `settings.isEnabled && settings.joyConEnabled && settings.joyConRumbleEnabled` 约束
- 未连接 Joy-Con 时静默忽略

## 映射模型
`JoyConInput` 覆盖所有可绑定输入（按钮 + 摇杆方向）：
- `dpadUp`, `dpadDown`, `dpadLeft`, `dpadRight`
- `buttonA`, `buttonB`, `buttonX`, `buttonY`
- `leftShoulder`, `rightShoulder`
- `leftTrigger`, `rightTrigger`
- `leftThumbstickButton`, `rightThumbstickButton`
- `buttonMenu`（Plus）, `buttonOptions`（Minus）
- `buttonHome`, `buttonCapture`（若存在）
- `leftStickUp`, `leftStickDown`, `leftStickLeft`, `leftStickRight`
- `rightStickUp`, `rightStickDown`, `rightStickLeft`, `rightStickRight`

未绑定输入不触发动作。

## 摇杆处理
- 当 `joyConStickMode == .dpad`：
  - 摇杆方向映射为对应 `JoyConInput`。
  - 采用阈值 + 边沿触发（示例：触发阈值 0.5，回死区阈值 0.2）。
- 当 `joyConStickMode == .off`：忽略摇杆。

## 动作触发与震动
输入触发流程：
1. 检查 `settings.isEnabled && settings.joyConEnabled`。
2. 查找 `JoyConInput` 对应 `KeyChord`。
3. 调用 `keyboardSimulator.simulateKey(chord:)`。
4. 更新 `keyboardSimulator.lastKeyPressed`。
5. 若 `joyConRumbleEnabled`，播放短促震动，强度为 `joyConRumbleStrength`。

震动使用 `controller.haptics` + `GCHapticEngine`。不支持时静默跳过。

## UI 变更
- Settings 面板新增 “Joy‑Con” 区域：
  - Enable Joy‑Con Input（开关）
  - Rumble Feedback（开关）
  - Rumble Strength（滑条）
  - Joy‑Con Stick Mode（分段选择）
  - “配置映射”按钮
- “配置映射”按钮打开独立映射弹窗：
  - 按类别分组（按钮 / D‑pad / 摇杆）
  - 每项显示当前绑定（如 `Shift+Enter`）
  - “绑定”进入捕获模式
  - 捕获监听 `keyDown`，必须包含非修饰键
  - “清除”删除绑定
  - Esc 不作为取消键（Esc 可被绑定）

## 实现步骤
1. 新增 `JoyConManager`：
   - 启动发现、监听连接/断开
   - 过滤 Joy-Con
   - 适配 `GCExtendedGamepad` / `GCMicroGamepad`
   - 将输入映射到 `JoyConInput` 并触发回调
2. `AppDelegate`：
   - 创建 `JoyConManager`
   - 绑定 action 回调到键盘模拟 + 震动
   - 扩展 URL handler 处理 `joyconcode://joycon/rumble`
3. `KeyboardSimulator`：
   - 新增 `simulateKey(chord:)`
   - 增加组合键显示辅助
4. 映射弹窗 View：
   - 读写 `settings.joyConBindings`
   - 实现绑定/捕获/清除流程
5. `AppSettings`：
   - 新增字段并做 UserDefaults 持久化
6. `Info.plist`：
   - 增加 `NSBluetoothAlwaysUsageDescription`
7. README：
   - 说明 Joy‑Con 支持、映射方式、Hook 震动

## Claude Code Hook 示例
```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "open -g \"joyconcode://joycon/rumble\"", "timeout": 5 }]
      }
    ]
  }
}
```

## 测试场景
1. 连接 Joy‑Con，打开 Joy‑Con 输入，绑定按键，触发后产生键盘输入。
2. 关闭主开关，Joy‑Con 输入不生效。
3. 摇杆模式为方向键时可触发；为忽略时不触发。
4. 震动开关/强度变更生效。
5. 断开 Joy‑Con 后状态更新为未连接。
6. 特殊键（Esc/Enter/Tab/箭头）能绑定并触发。
7. `joyconcode://joycon/rumble` 在 `UserPromptSubmit` 时震动一次。
8. 映射持久化，重启后仍保留。

## 假设与默认
- Joy‑Con 输入默认关闭，避免影响现有用户。
- 震动默认开启，强度 0.6。
- 自定义映射仅支持键盘按键 + 组合键。
- 未绑定输入不触发动作。
- 目前仅支持 `UserPromptSubmit` hook 触发震动。
