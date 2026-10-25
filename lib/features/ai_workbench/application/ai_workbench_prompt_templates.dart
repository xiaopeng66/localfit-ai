import 'package:localfit_ai/features/ai/domain/prompt_catalog.dart';

/// AI 创作任务卡的 prompt 模板（**单一来源**）。
///
/// docs/32 §4 T6c（D6）：这些模板原先内联在 6 个 `*WorkbenchTask` 类里；
/// 本包退役了那些任务类的**执行体**，但模板是真实资产——`PromptCatalog`
/// 仍注册它们（训练页 AI 生成计划的 provider、egress 评测集都读目录正文），
/// 因此原样迁到本文件（正文逐字不动）。

/// 原 `menu_normalize_workbench_task` 的 `defaultTemplate`（逐字迁移）。
const menuNormalizePromptTemplate = PromptTemplate(
  taskId: 'menu-normalize',
  promptVersion: 'menu-normalize-prompt-2',
  template:
      'Extract the menu text below into menu-normalize v1 JSON only. '
      'The JSON must contain schema_version (integer 1), source_date '
      '(YYYY-MM-DD, the date the menu is for: use the date from the '
      'menu text when it has one, otherwise use the today= value in '
      'the input), venue_name, services (array), warnings (array). '
      'Each service must contain service_name, open_time and close_time '
      '(HH:MM), items (array). Each item must contain display_name, and '
      'may contain station_name, reported_nutrition (object with kcal, '
      'protein_g, carbs_g, fat_g, evidence_text), ingredient_hints, '
      'allergen_hints, questions, needs_confirmation (boolean). '
      'task_id={task_id} prompt_version={prompt_version}\n{user_input}\n'
      'All human-readable values in the JSON (venue_name, service_name, '
      'display_name, warnings) MUST be written in Simplified Chinese. '
      'Keep JSON keys exactly as specified.',
  sendsWhat: '用户粘贴的菜单文本',
  neverSends: '完整食物目录、健康档案、图片',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);

/// 原 `dish_nutrition_workbench_task` 的 `defaultTemplate`（逐字迁移）。
const dishNutritionPromptTemplate = PromptTemplate(
  taskId: 'dish-nutrition',
  promptVersion: 'dish-nutrition-prompt-2',
  template:
      'Estimate nutrition per 100g for each dish below and return '
      'dish-nutrition v1 JSON only. The JSON must contain schema_version '
      '(integer 1) and estimates (non-empty array). Each estimate must '
      'contain dish_name, kcal_per_100g, protein_per_100g, '
      'carbs_per_100g, fat_per_100g (numbers per 100g as served), grade '
      '(A|B|C|D), basis_text, warnings. '
      'task_id={task_id} prompt_version={prompt_version}\n{user_input}\n'
      'All human-readable values (dish_name, basis_text, warnings) MUST be '
      'in Simplified Chinese. kcal_per_100g and the three macros are per '
      '100g of the dish as served, not per portion. The energy of the '
      'three macros (4/4/9 kcal per gram) must not exceed kcal_per_100g. '
      'grade: A=official/label data, B=authoritative database, '
      'C=similar-dish reference, D=rough estimate. Keep JSON keys exactly.',
  sendsWhat: '菜品名称与配料提示',
  neverSends: '健康档案、完整食物目录、图片、定位',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);

/// 原 `daily_menu_plan_workbench_task` 的 `defaultTemplate`（逐字迁移）。
// 2026-10-24 批次 4（`RV4-P1-08` / `docs/56` R12）：**本模板已从
// `promptCatalog` 摘除注册**。
//
// 它要求模型返回 `daily-menu-plan v1` JSON（`schema_version` / `slots` /
// `candidate_ids` / `selected_candidate_id` …），而该契约的解码器已在
// `RV2-P2-01` 整族退役——继续渲染它就是「要求模型输出一个 App 已经不能解析
// 的形状」。**文件保留**（不物理删）：`ai_egress_evaluation_test` 的出口评测集
// 仍引用这份正文做「不会再被执行」的对照。
//
// 现行「生成今日吃法」的启动提示词在 `ai_starter.dart::_dailyMenuPlanPrompt`
// （chat-edit 口径：`meal.create` 逐餐提议）。
const dailyMenuPlanPromptTemplate = PromptTemplate(
  taskId: 'daily-menu-plan',
  promptVersion: 'daily-menu-plan-prompt-2',
  template:
      'Choose only from the provided candidate ids; return daily-menu-plan '
      'v1 JSON. The JSON must contain schema_version (integer 1), '
      'local_date (YYYY-MM-DD), slots (array), unresolved (array of '
      'candidate ids you could not place, may be empty), warnings '
      '(array). Each slot must contain slot (breakfast|lunch|dinner|'
      'snack), candidate_ids (array copied from the provided ids), '
      'selected_candidate_id (one of candidate_ids or null), explanation '
      '(non-empty text), reason_codes (array of short English codes), '
      'needs_confirmation (boolean). '
      'task_id={task_id} prompt_version={prompt_version}\n'
      '{user_input}\n'
      'All human-readable values in the JSON (explanation, warnings) MUST '
      'be written in Simplified Chinese. Keep JSON keys, enum literals and '
      'the copied candidate ids exactly as provided.',
  sendsWhat:
      '日期与餐次、本地候选菜品（id、名称与热量/蛋白/碳水/脂肪估算）、'
      '你填写的偏好',
  neverSends: '完整食物目录、健康档案、真实图片',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);

/// 原 `dish_guidance_workbench_task` 的 `defaultTemplate`（逐字迁移）。
const dishGuidancePromptTemplate = PromptTemplate(
  taskId: 'dish-guidance',
  promptVersion: 'dish-guidance-prompt-2',
  template:
      'Explain how to eat the dish below. Return only dish-guidance v1 '
      'JSON. The JSON must contain schema_version (integer 1), dish_name, '
      'portion_grams_min and portion_grams_max (positive numbers in '
      'grams, max ≥ min), portion_note, slot_suggestion '
      '(breakfast|lunch|dinner|snack or null), pairing, substitutions, '
      'cautions, questions (pairing, substitutions, cautions and '
      'questions are each an array of short Chinese strings). Never '
      'output any nutrition numbers. '
      'task_id={task_id} '
      'prompt_version={prompt_version}\n{user_input}\n'
      'All human-readable values in the JSON (dish_name, portion_note, '
      'pairing, substitutions, cautions, questions) MUST be written in '
      'Simplified Chinese. Keep JSON keys and enum literals exactly as '
      'specified.',
  sendsWhat: '用户输入的菜名与补充说明',
  neverSends: '完整食物目录、健康档案、真实图片、历史餐食',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);

/// 原 `meal_pairing_workbench_task` 的 `defaultTemplate`（逐字迁移）。
const mealPairingPromptTemplate = PromptTemplate(
  taskId: 'meal-pairing',
  promptVersion: 'meal-pairing-prompt-2',
  template:
      'Organize the provided local foods into 1-5 meal combinations. '
      'Return only meal-pairing v1 JSON. The JSON must contain '
      'schema_version (integer 1), combos (array of 1-5 objects, each '
      'with name, slot (breakfast|lunch|dinner|snack or null), items '
      '(array of 1-6 objects with food_id copied exactly from the '
      'provided list plus grams, a number from 1 to 1000), optional '
      'note), warnings (array). Never invent food ids. '
      'task_id={task_id} '
      'prompt_version={prompt_version}\n{user_input}\n'
      'All human-readable values in the JSON (name, note, warnings) MUST '
      'be written in Simplified Chinese. Keep JSON keys and the copied '
      'food_id values exactly as provided.',
  sendsWhat: '用户点名的食材 allow-list（id、名称与每 100g 宏量）与搭配偏好',
  neverSends: '完整食物目录、健康档案、完整餐食历史',
  destinationHint: '设置中的 BYOK AI 供应商主机',
);
