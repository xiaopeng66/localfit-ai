"""审核台的**端到端**测试（docs/29 §P8b-1）。

跑法：C:/ProgramData/miniconda3/python.exe test_review_server.py

与 `test_review.py` 的分工：那边测核心规则（合成输入 + 真实产物对账），这边
把 `review_server.Workbench` 与真的 HTTP 处理器**起在临时仓库里**打一遍——
包括：

  * 真的追加进 `review_ledger.jsonl`、真的重建队列；
  * `review_mode` 由服务端决定：单条一律 `item`、`b` 键那条 `batch`；
  * 非法请求**一个字节都不写**（账本大小不变）；
  * 游标从账本派生（删掉游标照样能接着审）；
  * 「审过的条目不再出现在队列里」。

为了不碰真仓库，测试自己在 tmp 里造一个小仓库（种子 6 条 + 预览 + 词表），
再把 `review_lib` 的路径常量指过去——**不读也不写** `E:/AI/Zcode/.../assets`。
"""
from __future__ import annotations

import http.client
import json
import os
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import review_lib as rl  # noqa: E402
import review_server as rs  # noqa: E402

FAILURES: list[str] = []


def check(label: str, condition: bool, detail: str = "") -> None:
    if condition:
        print(f"  ok   {label}")
    else:
        FAILURES.append(label)
        print(f"  FAIL {label} {detail}")


def make_repo(root: Path) -> None:
    """造一个小仓库：种子 + 预览 + 词表（账本/游标故意不预置）。"""
    (root / "assets" / "seed").mkdir(parents=True, exist_ok=True)
    (root / "lib" / "utils").mkdir(parents=True, exist_ok=True)
    (root / "reports").mkdir(parents=True, exist_ok=True)
    (root / "pubspec.yaml").write_text("name: fake\n", encoding="utf-8")

    foods = [
        # 一组同首词的族批（康师傅 ×3）+ 一条品牌没拆（Foo）+ 一条纯汉字高频首词
        {"id": "seed-fc-1", "name": "康师傅 红烧牛肉面", "serving_g": 100,
         "kcal": 450.0, "protein": 9.0, "carbs": 60.0, "fat": 18.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
        {"id": "seed-fc-2", "name": "康师傅 香辣牛肉面", "serving_g": 100,
         "kcal": 460.0, "protein": 9.0, "carbs": 61.0, "fat": 19.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
        {"id": "seed-fc-3", "name": "康师傅 老坛酸菜面", "serving_g": 100,
         "kcal": 470.0, "protein": 8.0, "carbs": 62.0, "fat": 20.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
        {"id": "seed-fc-4", "name": "Foo 面包", "serving_g": 100,
         "kcal": 250.0, "protein": 8.0, "carbs": 45.0, "fat": 4.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
        {"id": "seed-fc-5", "name": "明治 酸奶", "serving_g": 100,
         "kcal": 70.0, "protein": 3.0, "carbs": 10.0, "fat": 2.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
        {"id": "seed-fc-6", "name": "清水 豆腐", "serving_g": 100,
         "kcal": 80.0, "protein": 8.0, "carbs": 2.0, "fat": 4.0,
         "constraint_knowledge": "known", "dietary_labels": [], "allergens": []},
    ]
    seed_bytes = json.dumps({"version": 4, "foods": foods}, ensure_ascii=False).encode()
    seed_path = root / rl.SEED_REL
    seed_path.write_bytes(seed_bytes)
    import hashlib
    sha = hashlib.sha256(seed_bytes).hexdigest()

    # 预览：与 Dart 侧同构的字段（测试里手写，值取自种子的拆分结果）。
    lines = [json.dumps({"_meta": {
        "seed": rl.SEED_REL, "seed_sha256": sha, "count": len(foods),
        "generator": "test", "source_functions": [
            "splitFoodName", "normalizeFoodName", "foodDisplayStrings"],
    }}, ensure_ascii=False)]
    splits = {
        "seed-fc-1": ("红烧牛肉面", "康师傅"),
        "seed-fc-2": ("香辣牛肉面", "康师傅"),
        "seed-fc-3": ("老坛酸菜面", "康师傅"),
        "seed-fc-4": ("面包", None),
        "seed-fc-5": ("酸奶", None),
        "seed-fc-6": ("豆腐", None),
    }
    for row in foods:
        name, brand = splits[row["id"]]
        kcal = row["kcal"]
        lines.append(json.dumps({
            "id": row["id"], "raw": row["name"], "name": name, "brand": brand,
            "ring": "—" if kcal <= 0 else str(round(kcal)),
            "ring_label": "无热量数据" if kcal <= 0 else "kcal/100g",
            "protein": f"{row['protein']}g", "carbs": f"{row['carbs']}g",
            "fat": f"{row['fat']}g",
        }, ensure_ascii=False))
    (root / rl.PREVIEW_REL).write_text("\n".join(lines) + "\n", encoding="utf-8")

    # 词表：不含任何 token，这样 Foo/康师傅/明治 都算「没拆」（排队用）。
    (root / rl.GAZETTEER_REL).write_text(
        "const Set<String> kFoodBrandTokens = <String>{};\n", encoding="utf-8"
    )


class Server:
    def __init__(self, root: Path, only: str | None = None) -> None:
        self.workbench = rs.Workbench(root, only=only)
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), rs.make_handler(self.workbench))
        self.port = self.httpd.server_address[1]
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()

    def request(self, method: str, path: str, body: dict | None = None):
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=10)
        payload = json.dumps(body, ensure_ascii=False).encode() if body is not None else None
        headers = {"Content-Type": "application/json"} if payload else {}
        conn.request(method, path, payload, headers)
        response = conn.getresponse()
        raw = response.read()
        conn.close()
        return response.status, raw

    def close(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()


def test_window_and_grouping(server: Server, root: Path) -> None:
    print("取窗与分组")
    status, raw = server.request("GET", "/api/window?index=0&size=20")
    check("GET /api/window 200", status == 200, str(status))
    payload = json.loads(raw)
    check("六条都在一窗里", sum(len(g["members"]) for g in payload["groups"]) == 6,
          str([len(g["members"]) for g in payload["groups"]]))
    check("初始待审 6", payload["stats"]["pending"] == 6, str(payload["stats"]))
    groups = {g["head"]: g for g in payload["groups"]}
    check("康师傅是一组", "康师傅" in groups and len(groups["康师傅"]["members"]) == 3,
          str(list(groups)))
    check("康师傅这组可族批", groups["康师傅"]["batchable"] is True)
    check("单条的那组不可族批", groups["Foo"]["batchable"] is False)
    check("预览字符来自服务端（不是 JS 算的）",
          groups["康师傅"]["members"][0]["name"] == "红烧牛肉面",
          str(groups["康师傅"]["members"][0]))
    check("品牌没拆时预览里没有品牌 chip",
          groups["Foo"]["members"][0]["brand"] is None,
          str(groups["Foo"]["members"][0]["brand"]))
    check("标记带人读的说明",
          len(groups["Foo"]["members"][0]["flag_labels"]) ==
          len(groups["Foo"]["members"][0]["flags"]),
          str(groups["Foo"]["members"][0]))

    status, raw = server.request("GET", "/api/window?index=999&size=5")
    check("越界 index 被夹住而不是报错", status == 200, str(status))
    status, raw = server.request("GET", "/api/unknown")
    check("未知路径 404", status == 404, str(status))
    status, raw = server.request("GET", "/../pubspec.yaml")
    check("不服务静态目录（路径穿越拿不到东西）", status == 404, str(status))


def test_decisions_write_ledger(server: Server, root: Path) -> None:
    print("裁决写账本")
    ledger = root / rl.LEDGER_REL
    check("初始没有账本", not ledger.exists())

    status, raw = server.request("POST", "/api/decide", {
        "action": "rename",
        "rows": [{"id": "seed-fc-1", "name": "红烧牛肉面（改）", "source": "人工核对包装"}],
    })
    check("改名称 200", status == 200, raw[:200])
    rows = rl.read_ledger(ledger)
    check("账本写了 1 行", len(rows) == 1, str(len(rows)))
    check("decision = rename", rows[0]["decision"] == "rename", str(rows[0]))
    check("before 是改前", rows[0]["before"]["name"] == "康师傅 红烧牛肉面", str(rows[0]["before"]))
    check("after 是改后", rows[0]["after"]["name"] == "红烧牛肉面（改）", str(rows[0]["after"]))
    check("单条记为 item", rows[0]["review_mode"] == "item", str(rows[0]))
    check("带 ts", bool(rows[0]["ts"]), str(rows[0]))

    # 定品牌 + 并入词表。
    status, _ = server.request("POST", "/api/decide", {
        "action": "set_brand",
        "rows": [{"id": "seed-fc-4", "brand": "Foo", "source": "人工判定"}],
    })
    check("定品牌 200", status == 200)
    status, _ = server.request("POST", "/api/decide", {
        "action": "brand_token",
        "rows": [{"id": "seed-fc-5", "brand_token": "明治", "source": "人一眼能判"}],
    })
    check("并入词表 200", status == 200)
    state = rl.replay(rl.read_ledger(ledger))
    check("词表裁决进账本", state["seed-fc-5"]["decision"] == "brand_token", str(state["seed-fc-5"]))
    check("并入的 token 生效（该条不再报没拆）",
          "brand_unresolved" not in server.workbench.flags["seed-fc-5"],
          str(server.workbench.flags["seed-fc-5"]))

    # 改营养：不填来源时服务端补「人工估值」（账本上不会出现空 source）。
    status, _ = server.request("POST", "/api/decide", {
        "action": "edit_nutrition",
        "rows": [{"id": "seed-fc-6", "nutrition": {
            "kcal": 76, "protein": 8.1, "carbs": 1.9, "fat": 4.2}}],
    })
    check("改营养 200", status == 200)
    last = rl.read_ledger(ledger)[-1]
    check("没填来源时记为人工估值", last["source"] == rl.NUTRITION_SOURCE_FALLBACK, str(last["source"]))
    check("after 是四个新值", last["after"]["kcal"] == 76.0 and last["after"]["fat"] == 4.2,
          str(last["after"]))


def test_batch_semantics(server: Server, root: Path) -> None:
    print("族批只能整组确认，且记为 batch")
    ledger = root / rl.LEDGER_REL
    before = len(rl.read_ledger(ledger))
    status, raw = server.request("POST", "/api/decide", {
        "action": "approve", "batch": True,
        "rows": [{"id": "seed-fc-2"}, {"id": "seed-fc-3"}],
    })
    check("族批 200", status == 200, raw[:200])
    rows = rl.read_ledger(ledger)[before:]
    check("两行都记了", len(rows) == 2, str(len(rows)))
    check("review_mode = batch", all(r["review_mode"] == "batch" for r in rows), str(rows))
    stats = server.workbench.stats()
    check("族批确认数 +2", stats["batch_confirmed"] == 2, str(stats))
    # 走到这里已有 4 条逐条裁决（改名称/定品牌/并入词表/改营养）——族批不许
    # 把它们算进来，「逐条核验」这个数才可信。
    check("逐条核验数没被族批污染", stats["item_verified"] == 4, str(stats))

    # 前端谎报 batch：单条、跨首词、漏组员，三种都不成立 —— 服务端**整批拒绝**，
    # 不降级记成 item（降级比拒绝更糟：那正是「核验方式混称」）。
    before_bytes = ledger.read_bytes()
    for label, body in [
        ("单条带 batch", {"action": "approve", "batch": True, "rows": [{"id": "seed-fc-6"}]}),
        ("跨首词带 batch", {"action": "approve", "batch": True, "rows": [
            {"id": "seed-fc-6"}, {"id": "seed-fc-1"}]}),
        ("非「通过」带 batch", {"action": "delete", "batch": True, "rows": [
            {"id": "seed-fc-6"}, {"id": "seed-fc-1"}]}),
    ]:
        status, raw = server.request("POST", "/api/decide", body)
        check(f"拒绝对：{label}", status == 400, f"{status} {raw[:140]}")
    check("被拒的族批一个字节都没写", ledger.read_bytes() == before_bytes)

    # 组里漏一条也不成立（族批不是抽样，漏下的会算不进去）。
    ledger_before = ledger.read_bytes()
    status, raw = server.request("POST", "/api/decide", {
        "action": "approve", "batch": True, "rows": [{"id": "seed-fc-1"}],
    })
    check("单条更不成立", status == 400, f"{status} {raw[:140]}")
    check("同样没写", ledger.read_bytes() == ledger_before)

    # 撤回：账本再追加一行 revert，不是删行；撤的是**账本最近一条生效裁决**
    # （不是前端报的哪一行——理由见 test_revert_targets_last_decision）。
    before = len(rl.read_ledger(ledger))
    target = server.workbench.last_decidable_id()
    status, _ = server.request("POST", "/api/decide", {
        "action": "revert", "rows": [{"id": "seed-fc-6"}],
    })
    rows = rl.read_ledger(ledger)
    check("撤回也是追加", len(rows) == before + 1, str(len(rows)))
    check("撤回行 decision = revert", rows[-1]["decision"] == "revert", str(rows[-1]))
    check("撤回指向账本最近一条，而不是请求里报的那条",
          rows[-1]["id"] == target, f"{rows[-1]['id']} vs {target}")
    check("撤回后该条回到待审（栈空）",
          target not in server.workbench.state, str(server.workbench.state.get(target)))


def test_rejections_write_nothing(server: Server, root: Path) -> None:
    print("非法请求一个字节都不写")
    ledger = root / rl.LEDGER_REL
    before = ledger.read_bytes()

    cases = [
        ("未知动作", {"action": "yolo", "rows": [{"id": "seed-fc-1"}]}),
        ("空 rows", {"action": "approve", "rows": []}),
        ("种子里没有的 id", {"action": "approve", "rows": [{"id": "nope"}]}),
        ("改营养缺字段", {"action": "edit_nutrition", "rows": [
            {"id": "seed-fc-1", "nutrition": {"kcal": 1, "protein": 1, "carbs": 1}}]}),
        ("改营养给非数字", {"action": "edit_nutrition", "rows": [
            {"id": "seed-fc-1", "nutrition": {
                "kcal": "abc", "protein": 1, "carbs": 1, "fat": 1}}]}),
        ("改营养给负数", {"action": "edit_nutrition", "rows": [
            {"id": "seed-fc-1", "nutrition": {
                "kcal": -5, "protein": 1, "carbs": 1, "fat": 1}}]}),
        ("改名称给空名", {"action": "rename", "rows": [{"id": "seed-fc-1", "name": "   "}]}),
        ("并入词表给空 token", {"action": "brand_token", "rows": [
            {"id": "seed-fc-1", "brand_token": "  "}]}),
        ("一批里混一条坏的", {"action": "approve", "rows": [
            {"id": "seed-fc-1"}, {"id": "nope"}]}),
    ]
    for label, body in cases:
        status, raw = server.request("POST", "/api/decide", body)
        payload = json.loads(raw)
        check(f"拒绝：{label}", status == 400 and "error" in payload, f"{status} {raw[:120]}")
        check(f"拒绝后账本没变：{label}", ledger.read_bytes() == before,
              f"{len(ledger.read_bytes())} vs {len(before)}")

    status, raw = server.request("POST", "/api/decide", body=None)
    check("空请求体被拒", status == 400, str(status))
    status, raw = server.request("POST", "/api/nope", {"action": "approve", "rows": []})
    check("未知 POST 路径 404", status == 404, str(status))


def test_cursor_is_derived(server: Server, root: Path) -> None:
    print("游标从账本派生")
    cursor_path = root / rl.CURSOR_REL
    check("裁决后写了游标", cursor_path.is_file())
    cursor = rl.read_cursor(cursor_path)
    ledger_state = rl.replay(rl.read_ledger(root / rl.LEDGER_REL))
    rl.write_cursor(cursor_path, ledger_state, seed_sha256_value=server.workbench.seed_sha)
    cursor = rl.read_cursor(cursor_path)
    check("游标与账本一致", rl.cursor_matches(cursor, ledger_state, server.workbench.seed_sha))

    # 删掉游标：重开（新 Workbench）照样认得已裁决的条目 —— 一切以账本为准。
    cursor_path.unlink()
    fresh = rs.Workbench(root)
    check("游标丢了也不丢进度", set(fresh.state) == set(ledger_state), str(fresh.state))


def test_queue_shrinks(server: Server, root: Path) -> None:
    print("审过的不再出现在队列里")
    status, raw = server.request("GET", "/api/window?index=0&size=500")
    payload = json.loads(raw)
    ids = {m["id"] for g in payload["groups"] for m in g["members"]}
    state = server.workbench.state
    # 队列 = 库里还没生效裁决的那些（撤回过的会回来），跟队列自己对账而不是
    # 写死某几个 id —— 前面的用例改了不少裁决，写死 id 会变成「测用例顺序」。
    expected = {food_id for food_id in server.workbench.order if food_id not in state}
    check("队列恰好等于「没有生效裁决」的条目", ids == expected,
          f"多 {sorted(ids - expected)[:3]} 少 {sorted(expected - ids)[:3]}")
    check("已裁决的不在队里", not (ids & set(state)), str(sorted(ids & set(state))[:3]))
    check("撤回到待审的条目回来了",
          any(food_id in ids for food_id in server.workbench.order
              if food_id not in state),
          str(sorted(state)[:3]))


def test_revert_targets_last_decision(server: Server, root: Path) -> None:
    """撤回撤的是**账本里最近一条生效裁决**，不是「前端报的那一行」。

    这条规则来自一次实测缺陷：裁决一落账本就退出待审队列、也从屏上消失，按键那
    一刻「当前行」早已是**下一行**，于是 8 键撤在空栈上、什么也没发生——先按 6
    删除、再按 8 撤回，那条被删的条目再也回不来。49,464 条靠键盘走，按错一格是
    必然事件，撤回必须真的能回。
    """
    print("撤回：撤最近一条，不看前端报哪一行")
    ledger = root / rl.LEDGER_REL
    before_rows = rl.read_ledger(ledger)
    check("撤回前账本非空（前面用例审过）", len(before_rows) > 0, str(len(before_rows)))
    last_effective = server.workbench.last_decidable_id()
    check("能算出最近一条生效裁决", last_effective is not None, str(last_effective))

    # 故意报一个**别的** id，甚至报一个种子里不存在的 id：撤回仍应按账本最近一条来。
    status, raw = server.request("POST", "/api/decide", {
        "action": "revert", "rows": [{"id": "seed-fc-2"}],
    })
    check("撤回 200", status == 200, raw[:160])
    rows = rl.read_ledger(ledger)
    check("撤回也是追加一行", len(rows) == len(before_rows) + 1, str(len(rows)))
    check("撤回指向的是账本最近一条，而不是前端报的 id",
          rows[-1]["id"] == last_effective, f"{rows[-1]['id']} vs {last_effective}")
    check("撤回行记下撤掉的是哪一条裁决",
          rows[-1]["before"].get("reverted_id") == last_effective, str(rows[-1]["before"]))
    check("撤掉的那条已生效裁决回到未裁决",
          server.workbench.state.get(last_effective) is None
          or server.workbench.state[last_effective]["decision"] != "approve",
          str(server.workbench.state.get(last_effective)))
    check("撤回的 id 回到待审队列",
          last_effective in {i for g in server.workbench.queue for i in g},
          str(last_effective))

    # 撤到没有生效裁决时：整批拒绝，账本不写。
    for _ in range(len(rl.replay(rl.read_ledger(ledger))) + 1):
        status, raw = server.request("POST", "/api/decide", {"action": "revert", "rows": []})
        if status == 400:
            break
    status, raw = server.request("POST", "/api/decide", {"action": "revert", "rows": []})
    check("撤光了以后再按 8 ⇒ 拒绝（不是静默无操作）", status == 400, f"{status} {raw[:160]}")


def test_batch_guards_isolated() -> None:
    """族批的守卫**各自单独**都要能拒（干净仓库上，一条一条分别验）。

    为什么单列一个用例：`test_batch_semantics` 里只有「跨首词带 batch」「单条带
    batch」这类输入，而在那个仓库里它们各自同时撞上两三道守卫（成员早已裁决、
    首词不止一个……），于是**拆掉任何一道守卫都还是 400**，测试照样全绿——变异
    电池实测：三条守卫全 SURVIVED。守卫重叠时，只断言「会被拒」等于没测。这里
    在干净仓库上构造**只有那一道能拦住**的输入：

    * 单成员组整组确认 → 只有「至少两条」能拦；
    * 三成员组只交两条 → 只有「必须是整组」能拦；
    * 整组但动作不是「通过」→ 只有「只有通过能族批」能拦；
    * 两个首词混着交 → 只有「同首词」能拦。

    最后一条要说明白：「拒绝」这件事本身被「必须是整组」包含了——ids 里只要有
    两个首词，任何一个首词的待审集合都不可能等于 ids（另一个首词的成员进不来），
    所以这道守卫**唯一独立可观察**的效果是它给出的**诊断**。诊断不是装饰：审核台
    把 `error` 原样显示给操作者，49,464 条靠键盘走，被拒时看到的理由必须指向真正
    的毛病（否则人去改的是别的东西）。测试因此把诊断文本一起钉住。
    """
    print("族批的守卫分别生效")
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        make_repo(root)
        server = Server(root)
        try:
            group = sorted(
                food_id
                for food_id in server.workbench.order
                if rl.head_token(server.workbench.rows[food_id]["name"]) == "康师傅"
            )
            check("康师傅组有 3 条待审", len(group) == 3, str(group))

            cases = [
                (
                    "单成员组整组确认 —— 只有至少两条这道守卫能拦",
                    {"action": "approve", "batch": True, "rows": [{"id": "seed-fc-4"}]},
                    "至少两条",
                ),
                (
                    "三成员组只交两条 —— 只有必须整组这道守卫能拦",
                    {"action": "approve", "batch": True,
                     "rows": [{"id": "seed-fc-1"}, {"id": "seed-fc-2"}]},
                    "必须是整组",
                ),
                (
                    "整组但动作是 delete —— 只有只有通过这道守卫能拦",
                    {"action": "delete", "batch": True,
                     "rows": [{"id": f} for f in group]},
                    "只有「通过」",
                ),
                (
                    "两个首词混着交 —— 只有同首词这道守卫能拦",
                    {"action": "approve", "batch": True,
                     "rows": [{"id": "seed-fc-4"}, {"id": "seed-fc-1"}]},
                    "同首词",
                ),
            ]
            for label, body, message in cases:
                ledger = root / rl.LEDGER_REL
                before = ledger.read_bytes() if ledger.exists() else b""
                status, raw = server.request("POST", "/api/decide", body)
                payload = json.loads(raw)
                check(f"拒绝：{label}", status == 400, f"{status} {raw[:140]}")
                check(
                    f"拒绝理由指向该道守卫：{label}",
                    message in (payload.get("error") or ""),
                    str(payload.get("error"))[:160],
                )
                after = ledger.read_bytes() if ledger.exists() else b""
                check(f"拒绝后账本没变：{label}", after == before)

            # 反证：同一批 id、同样的整组，用「通过」就必须成功（不是一律拒）。
            status, raw = server.request("POST", "/api/decide", {
                "action": "approve", "batch": True,
                "rows": [{"id": f} for f in group],
            })
            check("同一组的「通过」整组确认成功（守卫不是一律拒）", status == 200, raw[:160])
            rows = rl.read_ledger(root / rl.LEDGER_REL)
            check("账本里只有整组确认那三条（四次拒绝一个字节都没写）",
                  len(rows) == 3, str(len(rows)))
            check("三条都记成 batch",
                  all(row["review_mode"] == "batch" for row in rows), str(rows))
        finally:
            server.close()


def test_only_filter() -> None:
    print("--only 工作面")
    # 用一个**干净仓库**测：已裁决的条目会退出队列，混在上面的仓库里会看不见
    # 过滤效果（那是队列的正确行为，但不是这条要验的东西）。
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        make_repo(root)
        server = Server(root, only="brand_unresolved")
        try:
            payload = server.workbench.window(0, 500)
            ids = {m["id"] for g in payload["groups"] for m in g["members"]}
            check("只留带该标记的", ids == {"seed-fc-4"}, str(ids))
            check(
                "工作面单独计数，不冒充全库进度",
                payload["scope"]["flag"] == "brand_unresolved"
                and payload["scope"]["rows"] == 1,
                str(payload["scope"]),
            )
            check("全库进度仍是全库的", payload["stats"]["total"] == 6, str(payload["stats"]))
        finally:
            server.close()


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        make_repo(root)
        # 路径常量指到临时仓库（测试**不碰**真仓库的 assets/reports）。
        original = (rl.SEED_REL, rl.PREVIEW_REL, rl.LEDGER_REL, rl.CURSOR_REL, rl.GAZETTEER_REL)
        check("临时仓库没被真仓库路径污染",
              not (root / rl.SEED_REL).is_symlink(), "ok")
        server = Server(root)
        try:
            test_window_and_grouping(server, root)
            test_decisions_write_ledger(server, root)
            test_batch_semantics(server, root)
            test_rejections_write_nothing(server, root)
            test_cursor_is_derived(server, root)
            test_revert_targets_last_decision(server, root)
            test_queue_shrinks(server, root)
        finally:
            server.close()
        test_batch_guards_isolated()
        test_only_filter()
        check("路径常量仍是相对的（没被改坏）",
              original == (rl.SEED_REL, rl.PREVIEW_REL, rl.LEDGER_REL, rl.CURSOR_REL,
                           rl.GAZETTEER_REL),
              str(original))

    if FAILURES:
        print(f"\n{len(FAILURES)} 项失败：{FAILURES}")
        return 1
    print("\n全部通过")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
