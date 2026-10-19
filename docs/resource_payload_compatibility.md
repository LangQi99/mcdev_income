# 保存表单兼容性

平台详情响应不能直接作为保存表单。2026-10-19 的 B7 失败请求包含未选择的 `pri_effect_type: null`、`sub_effect_type: null`；同日普通 PE 作品的实测已确认，这两个字段的空值会触发 `params error`。`ResourceDraft.toPayload` 保留已有的空效果分类省略修复，选择了值的分类仍正常提交。

同一次表单核对还发现这些与官网编辑器不同的值，现统一在 GUI 和 CLI 的保存边界处理：

- 关闭的 DLC 使用 `master: {}`、`slave_list: []`；详情中的两个 `null` 不原样回传。开启 DLC 时保留主副包关联与自身名称更新。
- 空的 PE 专题 `subject_id` 使用 `null`。其他未知字段和 `game_host` 保持原值。
- 平台生成的大厅资源、操作日志、统计和审核状态不作为可编辑字段回传。
- 平台类别配置声明 `lobby: true`、并启用 `lobby_commercialize` 时，保存请求省略 `sub_type`；草稿保留原类别，上传文件仍按该类别校验。
- 类别要求 ModSDK 版本时，上传前按平台版本选项校验 `mod_version`，给出字段名称。不会从 ZIP 文件名自动推断 SDK 版本。

依据为官网 PE 编辑器 `2.843eee13c3642013ebba.js` 中的 `getData`、`dealDlcInfo` 和 `dealFormData`，以及平台的类别配置。B7 的包目标是 ModSDK 3.8，上传清单显式将旧表单的 3.4 改为 3.8。

`test/resource_payload_compatibility_test.dart` 覆盖详情转保存的 HTTP 载荷、DLC 空值、生成字段过滤、类别规则、SDK 版本和文件替换链路。使用模拟 HTTP 与本地表单快照验证，不把模拟保存当成平台保存成功。此次 B7 尚未重新保存或提交自测。
