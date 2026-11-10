# 2026-11-06 Findings（结案状态）

## 本轮已修复并复核

| ID | 严重度 | 结论 | 证据 |
|---|---|---|---|
| F-01 | P0 | **fixed**：槽位编辑只传当前槽位记录，不再跨餐合并/删除 | `record_tab.dart`, `nutrition_record_slot_grouping.dart`; cross-slot regression + nutrition/meal-card tests |
| F-02 | P1 | **fixed in code**：删除回调不再二次 pop branch navigator；真实 StatefulShellRoute 视觉仍 unverified | `training_page.dart`; training 217 tests |
| F-03 | P1 | **fixed**：scan cooking/range metadata 在 update/partial delete/restore 保留 | `meal_record.dart`, `meal_repository.dart`; meal repository/food_scan 207 tests |
| F-04 | P1 | **fixed**：地点删除处理全部 snapshots/sources | `canteen_repository.dart`; campus menu 20 tests |
| F-05 | P1 | **fixed**：recognition 清理、cardio FK 删除顺序、clear 顺序 | `meal_repository.dart`, `workout_plan_repository.dart`, `clear_all_local_data.dart`; 34 tests |
| F-06 | P1 | **fixed**：true v1 backup 缺 profiles/foods 后续 key 自动补默认 | `backup_table_registry.dart`; strengthened old backup fixture + 20 tests |
| F-07 | P1 | **fixed**：MealRepository 写入层拒未来且只允许近 30 天补记 | `meal_repository.dart`; boundary + reactivity 12 tests |
| F-08 | P1 | **fixed**：菜单发布失败清理本次新建 venue/source | `publish_menu_normalize_draft.dart`; menu 11 tests |
| F-09 | P1 | **fixed**：executor generic persistence exception 翻成结构化失败，不留 applying | `chat_edit_executor.dart`; executor 51 tests |
| F-10 | P1 | **fixed**：食堂营养仓储调用数值/置信度/区间边界校验 | `canteen_repository.dart`; canteen 26 tests |
| F-16 | P2 | **fixed**：下载进度增加 semantics label/value/liveRegion | `lf_progress_bar.dart`, `update_download_sheet.dart`; update 12 tests |
| F-UI | P2 | **test harness fixed/limited**：narrow audit 使用稳定 key；当前 shell fixture 两个入口未构建，记录 unverified | `narrow_layout_audit_test.dart`; audit +3 green |

## 仍存在的 P2 / 发布 blocker（不伪装通过）

- F-11：water/weight/steps/workout/daily-target 日期守卫仍不完全一致；self-check GLOB 不识别 impossible dates。
- F-12：source-sync delete ghost、部分 undo/restore 交错场景仍需更深故障注入。
- F-13：Water/Nutrition target stream 对 daily_targets/app-settings 变更的当前订阅失效未补。
- F-14：training set 的 plannedExercise 归属 session plan/exercise 未校验。
- F-15：manual meal editor / training review / canteen / steps 的部分 320×2 实帧未覆盖；StatefulShellRoute review 删除未实机取帧。
- F-17：生产 `debugPrint` 与隐私文档声明不一致，未在本轮清理。
- F-18：旧 dist 已移到 `E:/AI/Zcode/backups/localfit-dist-20261106/`；新 dist/index/SHA/LAN manifest 已与 2112 对齐。
- F-19：生产签名已确认存在且与 v4111 证书一致；Gradle 仍保留缺 key 时 debug fallback，作为后续安全改进。
- F-20：公共/Play 发布仍被 bundled/derived food 数据许可、归因 UI、REQUEST_INSTALL_PACKAGES/AAB 政策阻塞；本轮明确只做个人自用三 ABI。
- F-21：clean checkout 依赖 ignored `reports/review_ledger.jsonl`，未在本轮重构 fixture。

## 结论

S0/S1/P1 已清零到有证据的修复状态；P2 与公共发行阻塞已逐项列出。新包仅作为个人自用三 ABI，不宣称公共商店合规、ARM 真机通过或全量 P2 已清除。
